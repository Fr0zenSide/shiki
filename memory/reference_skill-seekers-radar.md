---
name: yusufkaraaslan/Skill_Seekers — Documentation-to-Claude-Skills Pipeline
type: reference
description: Automated pipeline converting 17+ source types into structured Claude AI Skills with conflict detection
source: https://github.com/yusufkaraaslan/Skill_Seekers
radar_date: 2026-04-02
relevance: HIGH
---

## What It Is

Skill Seekers is a data preprocessing pipeline that ingests documentation in 17+ formats and outputs structured AI skill files. It directly solves the "how do we get external knowledge into our skills system" problem that Shikki's `/ingest` pipeline addresses manually.

## Processing Pipeline

```
Input Sources (17+ types)
  └─ Documentation sites, GitHub repos, PDFs, videos, Jupyter notebooks,
     Word docs, EPUB, OpenAPI specs, PowerPoint, RSS feeds, man pages,
     Confluence wikis, Notion pages, Slack/Discord exports
         ↓
Ingestion → AST Analysis → Structuring → Enhancement (AI-powered) → Export
         ↓
Output Formats (16 targets)
  └─ Claude Skills (ZIP + YAML manifest), LangChain, LlamaIndex,
     Vector DBs (Pinecone/Chroma/FAISS), Markdown, IDE context files
```

## Key Capabilities Relevant to Shikki

### 1. Conflict Detection
The headline feature for Shikki. When ingesting new skill content, Skill Seekers detects conflicts with existing skills — preventing duplicate skill definitions and surfacing skill overlap. Shikki's current `/ingest` pipeline has no conflict detection; manual review is required. This is a direct gap to close.

### 2. SKILL.md Generation
Outputs `SKILL.md` files with code examples, patterns, usage guides, and quick references. Shikki's current skill format uses frontmatter + markdown prompts; Skill Seekers' structured SKILL.md format is worth standardizing against.

### 3. Claude Skills ZIP + YAML Manifest Export
Produces Claude-native skill packages (ZIP with YAML manifest) — the same format Shikki distributes skills through. The YAML manifest schema is worth auditing for fields Shikki's own manifests may be missing.

### 4. OpenAPI Spec Ingestion
Direct ingestion of OpenAPI specs → skills means Shikki could auto-generate tool-invocation skills from any MCP server's OpenAPI manifest. Powerful for Shikki's MCP tool surface.

### 5. 15–45 Minute Turnaround
Claims reduction from "days to 15–45 minutes" for comprehensive skill corpus generation. Relevant benchmark for Shikki's `/ingest` pipeline SLA.

## Shikki Integration Assessment

| Shikki Workflow | Skill Seekers Capability | Integration Path |
|----------------|--------------------------|-----------------|
| `/ingest` pipeline | Full automated ingestion | Replace/augment manual `/ingest` steps |
| Skill conflict detection | Built-in | Add pre-ingest conflict check gate |
| MCP server skills | OpenAPI spec ingestion | Auto-generate skills from MCP manifests |
| Skill distribution | 16-format export | Use for cross-tool skill portability |
| Memory reference files | Documentation site ingestion | Bulk-ingest external libraries |

## Concerns

- Python-based: Adds Python dependency to Shikki workflow if integrated directly
- "AI-powered enhancement" step is a black box — output quality depends on model used
- Conflict detection mechanism unspecified — need to audit for false positive rate

## Action Items

- [ ] Test Skill Seekers against Shikki's own `CLAUDE.md` and skill definitions to evaluate output quality
- [ ] Audit YAML manifest schema for Claude Skills ZIP format — compare to Shikki's current skill manifests
- [ ] Evaluate conflict detection mechanism — could this replace manual skill deduplication in Shikki's library?
- [ ] Test OpenAPI spec ingestion on a sample MCP server manifest
