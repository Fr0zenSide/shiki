import { sql } from "./db.ts";
import { storeMemory } from "./memories.ts";
import { logDebug, logError } from "./middleware.ts";

// ── Types ──────────────────────────────────────────────────────────

interface WatchlistItem {
  id: string;
  slug: string;
  kind: string;
  name: string;
  source_url: string | null;
  relevance: string | null;
  tags: string[];
  metadata: Record<string, unknown>;
}

interface ScanResult {
  watchlistId: string;
  status: "ok" | "update" | "breaking" | "error";
  currentVersion: string | null;
  previousVersion: string | null;
  releases: Release[];
  notableCommits: Commit[];
  summary: string;
  rawData: Record<string, unknown>;
}

interface Release {
  tag: string;
  name: string;
  date: string;
  body: string;
  breaking: boolean;
}

interface Commit {
  sha: string;
  message: string;
  date: string;
  author: string;
}

// ── GitHub API ─────────────────────────────────────────────────────

const GITHUB_TOKEN = Deno.env.get("GITHUB_TOKEN") ?? "";

function githubHeaders(): Record<string, string> {
  const headers: Record<string, string> = {
    "Accept": "application/vnd.github+json",
    "User-Agent": "shiki-radar/1.0",
  };
  if (GITHUB_TOKEN) {
    headers["Authorization"] = `Bearer ${GITHUB_TOKEN}`;
  }
  return headers;
}

async function fetchGitHubReleases(owner: string, repo: string, since: Date): Promise<Release[]> {
  try {
    const response = await fetch(
      `https://api.github.com/repos/${owner}/${repo}/releases?per_page=10`,
      { headers: githubHeaders() },
    );
    if (!response.ok) return [];

    const data = await response.json();
    return data
      .filter((r: any) => new Date(r.published_at) > since)
      .map((r: any) => ({
        tag: r.tag_name,
        name: r.name || r.tag_name,
        date: r.published_at,
        body: (r.body || "").slice(0, 2000),
        breaking: /\bbreaking\b/i.test(r.body || "") || isBreakingVersion(r.tag_name, data),
      }));
  } catch (error) {
    logError(`GitHub releases fetch failed for ${owner}/${repo}:`, error);
    return [];
  }
}

async function fetchGitHubCommits(owner: string, repo: string, since: Date): Promise<Commit[]> {
  try {
    const response = await fetch(
      `https://api.github.com/repos/${owner}/${repo}/commits?since=${since.toISOString()}&per_page=20`,
      { headers: githubHeaders() },
    );
    if (!response.ok) return [];

    const data = await response.json();
    // Filter to notable commits (not merge commits, not trivial)
    return data
      .filter((c: any) => !c.commit.message.startsWith("Merge "))
      .slice(0, 10)
      .map((c: any) => ({
        sha: c.sha.slice(0, 8),
        message: c.commit.message.split("\n")[0].slice(0, 200),
        date: c.commit.committer.date,
        author: c.commit.author.name,
      }));
  } catch (error) {
    logError(`GitHub commits fetch failed for ${owner}/${repo}:`, error);
    return [];
  }
}

async function fetchLatestRelease(owner: string, repo: string): Promise<string | null> {
  try {
    const response = await fetch(
      `https://api.github.com/repos/${owner}/${repo}/releases/latest`,
      { headers: githubHeaders() },
    );
    if (!response.ok) return null;
    const data = await response.json();
    return data.tag_name ?? null;
  } catch {
    return null;
  }
}

function isBreakingVersion(tag: string, allReleases: any[]): boolean {
  // Detect major version bump
  const match = tag.match(/v?(\d+)\./);
  if (!match) return false;
  const major = parseInt(match[1]);

  // Find the previous release with a different major
  for (const r of allReleases) {
    const prevMatch = r.tag_name.match(/v?(\d+)\./);
    if (prevMatch && parseInt(prevMatch[1]) < major) return true;
  }
  return false;
}

// ── Scanning ───────────────────────────────────────────────────────

async function scanRepo(item: WatchlistItem, since: Date): Promise<ScanResult> {
  const parts = item.slug.split("/");
  if (parts.length !== 2) {
    return {
      watchlistId: item.id,
      status: "error",
      currentVersion: null,
      previousVersion: null,
      releases: [],
      notableCommits: [],
      summary: `Invalid repo slug: ${item.slug}`,
      rawData: {},
    };
  }

  const [owner, repo] = parts;
  const [releases, commits, latestVersion] = await Promise.all([
    fetchGitHubReleases(owner, repo, since),
    fetchGitHubCommits(owner, repo, since),
    fetchLatestRelease(owner, repo),
  ]);

  // Get previous version from last scan
  const lastScan = await sql`
    SELECT current_version FROM radar_scans
    WHERE watchlist_id = ${item.id}
    ORDER BY scanned_at DESC LIMIT 1
  `;
  const previousVersion = lastScan.length > 0 ? lastScan[0].current_version : null;

  // Determine status
  let status: "ok" | "update" | "breaking" = "ok";
  if (releases.some((r) => r.breaking)) {
    status = "breaking";
  } else if (releases.length > 0 || (latestVersion && latestVersion !== previousVersion)) {
    status = "update";
  }

  // Build summary
  let summary = `${item.name}: `;
  if (releases.length === 0 && commits.length === 0) {
    summary += "No changes";
  } else {
    const parts: string[] = [];
    if (releases.length > 0) parts.push(`${releases.length} release(s) — latest: ${releases[0].tag}`);
    if (commits.length > 0) parts.push(`${commits.length} notable commit(s)`);
    if (status === "breaking") parts.push("BREAKING CHANGES detected");
    summary += parts.join(". ");
  }

  return {
    watchlistId: item.id,
    status,
    currentVersion: latestVersion,
    previousVersion,
    releases,
    notableCommits: commits,
    summary,
    rawData: { releasesCount: releases.length, commitsCount: commits.length },
  };
}

// ── Public API ─────────────────────────────────────────────────────

export async function triggerScan(sinceDays: number, itemIds?: string[]): Promise<string> {
  const scanRunId = crypto.randomUUID();

  // Fetch watchlist
  let items: WatchlistItem[];
  if (itemIds && itemIds.length > 0) {
    items = await sql`SELECT * FROM radar_watchlist WHERE id = ANY(${itemIds}) AND enabled = TRUE`;
  } else {
    items = await sql`SELECT * FROM radar_watchlist WHERE enabled = TRUE`;
  }

  const since = new Date();
  since.setDate(since.getDate() - sinceDays);

  // Run scans (fire and forget for async, but we await to store results)
  scanAllItems(items, since, scanRunId);

  return scanRunId;
}

async function scanAllItems(items: WatchlistItem[], since: Date, scanRunId: string) {
  for (const item of items) {
    try {
      let result: ScanResult;
      if (item.kind === "repo") {
        result = await scanRepo(item, since);
      } else {
        // Dependency and technology scans — basic placeholder
        result = {
          watchlistId: item.id,
          status: "ok",
          currentVersion: null,
          previousVersion: null,
          releases: [],
          notableCommits: [],
          summary: `${item.name}: scan not yet implemented for kind '${item.kind}'`,
          rawData: {},
        };
      }

      // Store scan result
      await sql`
        INSERT INTO radar_scans (watchlist_id, scan_run_id, status, current_version, previous_version, releases, notable_commits, summary, raw_data)
        VALUES (
          ${result.watchlistId},
          ${scanRunId},
          ${result.status},
          ${result.currentVersion},
          ${result.previousVersion},
          ${JSON.stringify(result.releases)},
          ${JSON.stringify(result.notableCommits)},
          ${result.summary},
          ${JSON.stringify(result.rawData)}
        )
      `;

      logDebug(`Scanned ${item.slug}: ${result.status}`);
    } catch (error) {
      logError(`Scan failed for ${item.slug}:`, error);
      await sql`
        INSERT INTO radar_scans (watchlist_id, scan_run_id, status, summary)
        VALUES (${item.id}, ${scanRunId}, 'error', ${`Scan failed: ${error}`})
      `;
    }
  }

  // Generate digest after all scans complete
  await generateDigest(scanRunId);
}

// ── Digest Generation ──────────────────────────────────────────────

export async function generateDigest(scanRunId: string): Promise<string> {
  const scans = await sql`
    SELECT rs.*, rw.name, rw.slug, rw.relevance, rw.tags
    FROM radar_scans rs
    JOIN radar_watchlist rw ON rw.id = rs.watchlist_id
    WHERE rs.scan_run_id = ${scanRunId}
    ORDER BY
      CASE rs.status WHEN 'breaking' THEN 0 WHEN 'update' THEN 1 WHEN 'error' THEN 2 ELSE 3 END,
      rw.name
  `;

  if (scans.length === 0) return "No scan results found.";

  const breaking = scans.filter((s: any) => s.status === "breaking");
  const updates = scans.filter((s: any) => s.status === "update");
  const errors = scans.filter((s: any) => s.status === "error");
  const stable = scans.filter((s: any) => s.status === "ok");

  const lines: string[] = [];
  const date = new Date().toISOString().split("T")[0];

  lines.push(`## Tech Radar — ${date}`);
  lines.push(`**Scanned ${scans.length} items** | ${updates.length} updates | ${breaking.length} breaking changes`);
  lines.push("");

  if (breaking.length > 0) {
    lines.push("### Breaking Changes");
    for (const s of breaking) {
      const ver = s.previous_version && s.current_version
        ? `${s.previous_version} → ${s.current_version}`
        : s.current_version ?? "";
      lines.push(`- **${s.name}** ${ver} — ${s.summary}`);
      for (const r of (s.releases as Release[]).filter((r) => r.breaking)) {
        lines.push(`  - \`${r.tag}\` (${r.date.split("T")[0]}): ${r.body.split("\n")[0].slice(0, 150)}`);
      }
    }
    lines.push("");
  }

  if (updates.length > 0) {
    lines.push("### Notable Updates");
    for (const s of updates) {
      const ver = s.previous_version && s.current_version
        ? `${s.previous_version} → ${s.current_version}`
        : s.current_version ?? "";
      lines.push(`- **${s.name}** ${ver} — ${s.summary}`);
    }
    lines.push("");
  }

  if (errors.length > 0) {
    lines.push("### Scan Errors");
    for (const s of errors) {
      lines.push(`- **${s.name}**: ${s.summary}`);
    }
    lines.push("");
  }

  if (stable.length > 0) {
    lines.push("### Stable (no changes)");
    lines.push(stable.map((s: any) => s.name).join(", "));
    lines.push("");
  }

  const markdown = lines.join("\n");

  // Store digest
  await sql`
    INSERT INTO radar_digests (scan_run_id, markdown, item_count, update_count, breaking_count)
    VALUES (${scanRunId}, ${markdown}, ${scans.length}, ${updates.length}, ${breaking.length})
    ON CONFLICT (scan_run_id) DO UPDATE SET
      markdown = EXCLUDED.markdown,
      item_count = EXCLUDED.item_count,
      update_count = EXCLUDED.update_count,
      breaking_count = EXCLUDED.breaking_count
  `;

  return markdown;
}

// ── Digest Ingestion into Memories ─────────────────────────────────

export async function ingestDigest(scanRunId: string, projectId: string): Promise<number> {
  const scans = await sql`
    SELECT rs.*, rw.name, rw.slug, rw.relevance
    FROM radar_scans rs
    JOIN radar_watchlist rw ON rw.id = rs.watchlist_id
    WHERE rs.scan_run_id = ${scanRunId}
      AND rs.status IN ('update', 'breaking')
  `;

  let count = 0;
  for (const scan of scans) {
    const content = [
      `Tech Radar: ${scan.name} (${scan.slug})`,
      `Status: ${scan.status}`,
      scan.previous_version ? `Version: ${scan.previous_version} → ${scan.current_version}` : `Version: ${scan.current_version}`,
      `Relevance: ${scan.relevance || "tracked dependency"}`,
      scan.summary,
      ...(scan.releases as Release[]).map((r) => `Release ${r.tag}: ${r.body.split("\n")[0].slice(0, 300)}`),
    ].join("\n");

    await storeMemory({
      projectId,
      content,
      category: "radar",
      importance: scan.status === "breaking" ? 8.0 : 3.0,
    });
    count++;
  }

  // Mark digest as ingested
  await sql`UPDATE radar_digests SET ingested = TRUE WHERE scan_run_id = ${scanRunId}`;

  return count;
}

// ── Watchlist CRUD ─────────────────────────────────────────────────

export async function listWatchlist(kind?: string, tag?: string) {
  if (kind && tag) {
    return await sql`SELECT * FROM radar_watchlist WHERE kind = ${kind} AND ${tag} = ANY(tags) ORDER BY name`;
  } else if (kind) {
    return await sql`SELECT * FROM radar_watchlist WHERE kind = ${kind} ORDER BY name`;
  } else if (tag) {
    return await sql`SELECT * FROM radar_watchlist WHERE ${tag} = ANY(tags) ORDER BY name`;
  }
  return await sql`SELECT * FROM radar_watchlist ORDER BY name`;
}

export async function addWatchlistItem(item: {
  slug: string;
  kind: string;
  name: string;
  sourceUrl?: string;
  relevance?: string;
  tags?: string[];
  metadata?: Record<string, unknown>;
}) {
  const [row] = await sql`
    INSERT INTO radar_watchlist (slug, kind, name, source_url, relevance, tags, metadata)
    VALUES (${item.slug}, ${item.kind}, ${item.name}, ${item.sourceUrl ?? null}, ${item.relevance ?? null}, ${item.tags ?? []}, ${JSON.stringify(item.metadata ?? {})})
    RETURNING *
  `;
  return row;
}

export async function updateWatchlistItem(id: string, updates: Record<string, unknown>) {
  const fields: string[] = [];
  if (updates.name !== undefined) fields.push("name");
  if (updates.sourceUrl !== undefined) fields.push("source_url");
  if (updates.relevance !== undefined) fields.push("relevance");
  if (updates.tags !== undefined) fields.push("tags");
  if (updates.enabled !== undefined) fields.push("enabled");

  // Simple update — only update provided fields
  const [row] = await sql`
    UPDATE radar_watchlist SET
      name = COALESCE(${(updates.name as string) ?? null}, name),
      source_url = COALESCE(${(updates.sourceUrl as string) ?? null}, source_url),
      relevance = COALESCE(${(updates.relevance as string) ?? null}, relevance),
      enabled = COALESCE(${(updates.enabled as boolean) ?? null}, enabled),
      updated_at = NOW()
    WHERE id = ${id}
    RETURNING *
  `;
  return row ?? null;
}

export async function deleteWatchlistItem(id: string): Promise<boolean> {
  const result = await sql`DELETE FROM radar_watchlist WHERE id = ${id} RETURNING id`;
  return result.length > 0;
}

export async function getDigest(scanRunId: string) {
  const [digest] = await sql`SELECT * FROM radar_digests WHERE scan_run_id = ${scanRunId}`;
  return digest ?? null;
}

export async function getLatestDigest() {
  const [digest] = await sql`SELECT * FROM radar_digests ORDER BY created_at DESC LIMIT 1`;
  return digest ?? null;
}

export async function getScanResults(scanRunId: string) {
  return await sql`
    SELECT rs.*, rw.name, rw.slug, rw.relevance, rw.tags
    FROM radar_scans rs
    JOIN radar_watchlist rw ON rw.id = rs.watchlist_id
    WHERE rs.scan_run_id = ${scanRunId}
    ORDER BY
      CASE rs.status WHEN 'breaking' THEN 0 WHEN 'update' THEN 1 WHEN 'error' THEN 2 ELSE 3 END,
      rw.name
  `;
}

export async function listScanHistory(limit = 10) {
  return await sql`
    SELECT rd.*, COUNT(rs.id) as total_items
    FROM radar_digests rd
    LEFT JOIN radar_scans rs ON rs.scan_run_id = rd.scan_run_id
    GROUP BY rd.id
    ORDER BY rd.created_at DESC
    LIMIT ${limit}
  `;
}
