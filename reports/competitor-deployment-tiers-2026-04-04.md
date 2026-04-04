# Competitor Deployment Tiers & Multi-Tenant Architecture

**Date**: 2026-04-04
**Purpose**: Factual comparison of pricing, isolation, and deployment models across developer platforms

---

## 1. GitHub (Copilot + Actions + Codespaces)

### Platform Tiers (repository hosting)

| Tier | Price | Key Inclusions |
|------|-------|----------------|
| Free | $0 | Unlimited public/private repos, 2,000 Actions min/mo, 500 MB Packages |
| Team | $4/user/mo | 3,000 Actions min/mo, 2 GB Packages, org controls |
| Enterprise Cloud | $21/user/mo | 50,000 Actions min/mo, 50 GB Packages, SAML SSO, audit log, data residency |
| Enterprise Server | $21/user/yr (license) + infra | Self-hosted, full control, custom workflows |

### Copilot Tiers (separate billing)

| Tier | Price | Key Inclusions |
|------|-------|----------------|
| Free | $0 | 2,000 completions/mo, 50 premium requests/mo |
| Pro | $10/mo | Unlimited completions, 300 premium requests/mo |
| Pro+ | $39/mo | 1,500 premium requests, all models (Claude Opus 4, o3) |
| Business | $19/user/mo | Org management, policy controls, IP indemnity |
| Enterprise | $39/user/mo | Everything in Business + knowledge bases, fine-tuning |

### Isolation Model

- **Free/Team/Enterprise Cloud**: Shared multi-tenant infrastructure on GitHub.com. Organizations are logically isolated (org-level permissions, SAML SSO) but share underlying compute.
- **Enterprise Cloud with Data Residency**: Choose storage region (US/EU). Still shared infra, but data-at-rest pinned to region.
- **Enterprise Server**: Fully self-hosted on customer's own infrastructure (on-prem or private cloud). Complete physical isolation. Customer manages upgrades, backups, scaling.
- **Actions Runners**: Shared GitHub-hosted runners by default. Enterprise can use self-hosted runners or larger dedicated runners.
- **Codespaces**: Usage-based ($0.18/hr compute, $0.07/GB storage). Each codespace is an isolated VM. Org admins control which repos/users can create codespaces.

### Key Enterprise Differentiators
- SAML SSO, SCIM provisioning
- Audit log streaming (Splunk, Datadog, S3)
- IP allow lists
- Enterprise Managed Users (EMU) -- org controls user lifecycle
- GitHub Advanced Security (code scanning, secret scanning, dependency review) -- included in Enterprise, add-on for Team
- Self-hosted runners for air-gapped environments

---

## 2. GitLab

### Tiers

| Tier | Price | Deployment |
|------|-------|------------|
| Free | $0 | SaaS (gitlab.com) only. 5 GB storage, 400 CI/CD min/mo |
| Premium (SaaS) | $29/user/mo | SaaS. 10,000 CI/CD min/mo, merge approvals, code quality |
| Premium (Self-Managed) | $19/user/mo | On-prem. Same features, customer manages infra |
| Ultimate (SaaS) | $99/user/mo | SaaS. 50,000 CI/CD min/mo, SAST/DAST, compliance dashboards |
| Ultimate (Self-Managed) | $99/user/mo | On-prem. Full security suite |
| Ultimate Plus (Dedicated) | Custom (sales) | Single-tenant SaaS on dedicated AWS infra |

### AI Add-on

- **GitLab Duo Pro**: +$19/user/mo on Premium or Ultimate. Code generation, test generation, refactoring.

### Isolation Model

- **gitlab.com (SaaS)**: Multi-tenant shared infrastructure. Logical isolation by group/project. Data stored in US (GCP).
- **Self-Managed**: Customer deploys on own servers. Full physical isolation. Available for Premium and Ultimate.
- **GitLab Dedicated (Ultimate Plus)**: Single-tenant SaaS. GitLab deploys and manages a dedicated instance in customer's preferred AWS region. No shared infrastructure with other tenants. GitLab engineers do not have direct access to customer environments. Launched 2023, aimed at regulated industries (finance, healthcare, government).

### Key Enterprise Differentiators
- SAST, DAST, container scanning, dependency scanning (Ultimate)
- Compliance frameworks and audit events
- Self-managed option at every paid tier
- Dedicated single-tenant SaaS for orgs that want isolation without ops burden
- GitLab Dedicated for Government (FedRAMP, separate offering)

---

## 3. Linear

### Tiers

| Tier | Price | Key Inclusions |
|------|-------|----------------|
| Free | $0 | Up to 250 issues, 2 teams |
| Standard | $8/user/mo (monthly) / ~$6.40 annual | Unlimited issues, guests, integrations |
| Plus | $14/user/mo (monthly) | Advanced workflows, time tracking |
| Enterprise | Custom | SAML SSO, SCIM, audit logs, HIPAA, dedicated support |

All plans billed annually for the discount (~20% off monthly).

### Isolation Model

- **SaaS only**. No self-hosted or on-premise option.
- Multi-tenant shared infrastructure for all tiers.
- Logical isolation per workspace.
- **Multi-region support**: Linear built multi-region infrastructure (announced publicly on their engineering blog). Data residency by workspace region.

### Key Enterprise Differentiators
- SAML SSO and SCIM provisioning (Enterprise only)
- Audit logs
- HIPAA compliance (Enterprise)
- Custom SLAs and dedicated support
- No self-hosted path -- enterprise customers who need on-prem are out of luck

### Architecture Notes
Linear is known for its local-first sync engine. The client maintains a local SQLite database and syncs with the server, which is why the app feels instantaneous. Server-side, multi-tenant with workspace-level data partitioning.

---

## 4. AI Coding Tools (Cursor / Windsurf / Claude Code)

### Cursor

| Tier | Price | Key Inclusions |
|------|-------|----------------|
| Hobby | $0 | Limited completions + agent requests |
| Pro | $20/mo | Unlimited completions, $20 credit pool for premium models |
| Pro+ | $60/mo | $60 credit pool |
| Ultra | $200/mo | 20x Pro usage, priority features |
| Teams | $40/user/mo | Pooled usage, admin controls |
| Enterprise | Custom | SSO, RBAC, audit logs, self-hosted agents |

**Isolation**: Cloud-hosted SaaS by default on SOC 2 Type II AWS infra. No full on-premise deployment. However, as of March 2026, Cursor offers **self-hosted cloud agents** -- agent execution runs on customer's own network (code/builds/secrets never leave customer infra). Each agent gets a dedicated VM. Enterprise admins can whitelist/blocklist repos, models, and MCP servers.

**BYOK**: Users can bring their own API keys (OpenAI, Anthropic, etc.) to bypass Cursor's credit system.

### Windsurf (Codeium)

| Tier | Price | Key Inclusions |
|------|-------|----------------|
| Free | $0 | 25 credits/mo, unlimited SWE-1 Lite, 1 deploy/day |
| Pro | $15/mo | 500 credits/mo, SWE-1 model, 5 deploys/day |
| Max | $200/mo | Higher quotas for power users |
| Teams | $30/user/mo | 500 credits/user, admin tools |
| Enterprise | $60+/user/mo | RBAC, SSO, hybrid deployment, 1000 credits at 200+ seats |

**Isolation**: SaaS by default. Enterprise tier mentions "hybrid deployment" but details are sparse. Pricing overhauled March 2026 (credits replaced by quotas).

### Claude Code (Anthropic)

| Tier | Price | Key Inclusions |
|------|-------|----------------|
| Pro | $20/mo | Claude Code CLI + web + desktop, Sonnet 4.6 + Opus 4.6 |
| Max 5x | $100/mo | 5x Pro usage |
| Max 20x | $200/mo | 20x Pro usage |
| Team Standard | $20/seat/mo | No Claude Code access |
| Team Premium | $100/seat/mo | Claude Code, min 5 seats, mix-and-match |
| Enterprise | Custom | 500K context, HIPAA BAA, compliance tooling |
| API | Pay-per-token | Sonnet: $3/$15 per MTok in/out. Opus: higher. |

**Isolation**: No self-hosted Claude Code. Enterprise isolation is achieved through:
- **AWS Bedrock**: Run Claude within customer's VPC. Zero data egress. Private Service Connect.
- **Google Vertex AI**: Same VPC isolation via PSC.
- SOC 2 Type II certified. HIPAA BAA available for API and Enterprise (not Pro/consumer).
- BYOK (Bring Your Own Key) for encryption coming H1 2026.

### Summary: AI Tools Isolation

| Tool | Self-hosted? | Enterprise Isolation | Compliance |
|------|-------------|---------------------|------------|
| Cursor | Partial (self-hosted agents, not full IDE) | SOC 2, dedicated VMs per agent | SOC 2 Type II |
| Windsurf | No (hybrid mentioned) | Unclear | Not publicly stated |
| Claude Code | No (but Bedrock/Vertex for API) | VPC via Bedrock/Vertex | SOC 2 Type II, HIPAA BAA |

---

## 5. Supabase

### Tiers

| Tier | Price | Key Inclusions |
|------|-------|----------------|
| Free | $0 | 2 projects, 500 MB DB, 50K MAUs, auto-pause after 7 days idle |
| Pro | $25/mo + usage | 8 GB DB, 100K MAUs, 100 GB storage, no pause |
| Team | $599/mo + usage | SOC 2 Type II, SSO, audit logs, 14-day backups, priority support |
| Enterprise | Custom | HIPAA, dedicated infra, custom quotas, regional replication |

### Compute Add-ons (available on Pro+)

| Size | vCPUs | RAM | Price |
|------|-------|-----|-------|
| Micro (default) | shared | 1 GB | Free ($10 credit covers it) |
| Small | 2 | 2 GB | $40/mo |
| Medium | 2 | 4 GB | $70/mo |
| Large | 2 | 8 GB | $110/mo |
| XL | 4 | 16 GB | $210/mo |
| 2XL | 8 | 32 GB | $410/mo |
| 4XL | 16 | 64 GB | $960/mo |

IPv4 add-on: $4/mo per database (required if clients can't resolve IPv6).

### Isolation Model

- **Free/Pro**: Each project gets its own dedicated Postgres instance (not shared DB). However, the underlying compute is shared/burstable (Micro tier). Physical isolation comes from running your own Postgres process, but the host machine is shared.
- **Pro + Compute Add-on**: Dedicated compute at chosen tier. Still managed by Supabase.
- **Team**: Same as Pro but with compliance features. Still shared host infra.
- **Enterprise**: Dedicated infrastructure, regional replication, custom networking.
- **Self-hosted**: Full Docker Compose stack (12 containers: Postgres, GoTrue, PostgREST, Realtime, Kong, Studio, etc.). 100% free, unlimited. One Postgres instance per deployment. Customer manages everything.

### Multi-tenancy via RLS

Supabase heavily promotes Row Level Security (RLS) as the multi-tenancy pattern:
- Single database, multiple tenants, RLS policies filter by `tenant_id`
- Built into Postgres, zero application-level query filtering needed
- Used internally by Supabase for their own platform
- Alternative: schema-per-tenant or database-per-tenant (more expensive, better isolation)

### Key Enterprise Differentiators
- HIPAA compliance (Enterprise only)
- SOC 2 Type II (Team+)
- Dedicated compute (any paid tier via add-on)
- Point-in-time recovery (Pro: 7 days, Team: 14 days)
- Custom domains, vanity URLs
- Read replicas (paid add-on)
- Self-hosted option is genuinely production-viable

---

## 6. Vercel / Netlify

### Vercel

| Tier | Price | Key Inclusions |
|------|-------|----------------|
| Hobby | $0 | Non-commercial only. 100 GB transfer, 1M edge requests |
| Pro | $20/user/mo | $20 credit/mo, 1 TB transfer, 10M edge requests, team features |
| Enterprise | ~$45K/yr median (custom) | Dedicated infra, 99.99% SLA, SAML SSO, audit logs |

**Isolation Model**:
- **Hobby/Pro**: Shared multi-tenant edge network and build infrastructure.
- **Enterprise**: Isolated build infrastructure on dedicated high-grade hardware (no build queues). **Secure Compute**: dedicated private network with unique IP pair not shared with any other customer. KVM-based build isolation (each build in its own VM). Custom SSL, IP allowlisting.

**Key Enterprise Features**: SAML SSO ($300/mo add-on for Pro, included in Enterprise), HIPAA BAA ($350/mo add-on for Pro, included in Enterprise), Secure Compute (private network), dedicated account manager, SLA.

### Netlify

| Tier | Price | Key Inclusions |
|------|-------|----------------|
| Free | $0 | Credit-based (limited) |
| Personal | $9/mo | More credits |
| Pro | $20/user/mo | Team features |
| Enterprise | Custom | Volume, advanced security, dedicated support |

**Note**: Netlify transitioned to credit-based pricing in September 2025, replacing the old Starter/Pro/Business structure. One credit balance replaces 15+ separate metrics.

**Isolation Model**: Multi-tenant at all tiers. Enterprise gets priority build infrastructure and advanced security features but no fully dedicated infra offering documented publicly.

---

## 7. Slack

### Tiers

| Tier | Price | Key Inclusions |
|------|-------|----------------|
| Free | $0 | 90-day message history, 10 app integrations, 5 GB storage |
| Pro | $7.25/user/mo (annual) | Unlimited history, basic AI, group huddles |
| Business+ | $15/user/mo | Advanced AI (search, recaps, translations), Salesforce integration |
| Enterprise Grid | Custom (~$15+/user) | Unlimited workspaces, centralized admin, compliance tools |
| GovSlack | Custom (gov procurement) | FedRAMP High, DoD IL4, AWS GovCloud |

### Isolation Model

- **Free/Pro/Business+**: Multi-tenant shared infrastructure. Single database serving multiple workspaces. Data isolation via tenant identifiers (workspace_id) with Row-Level Security. Sharding prevents noisy-neighbor issues.
- **Enterprise Grid**: Still multi-tenant shared infrastructure, but with organizational overlay. An "organization" contains unlimited workspaces. Shared channels bridge workspaces. Centralized admin console controls all workspaces. Data Loss Prevention, eDiscovery, key management (EKM -- Enterprise Key Management, customer controls encryption keys).
- **GovSlack**: **Dedicated infrastructure**. Runs on AWS GovCloud (US personnel only). FIPS 140 validated encryption. FedRAMP High authorized. Physically separated from commercial Slack. Dedicated DNS, VPCs, Transit Gateways. Built with Terraform modules.

### Architecture Details
Built on AWS, PostgreSQL, and Vitess (MySQL sharding). Slack re-architected for Enterprise Grid (see "Unified Grid" engineering blog post). Each workspace has its own ID, directory, channels, and files. Cross-workspace operations route through the org layer.

### Key Enterprise Differentiators
- EKM (Enterprise Key Management) -- customer-owned encryption keys
- DLP integrations
- eDiscovery export
- Org-level admin console
- Custom retention policies
- HIPAA, SOC 2, FedRAMP (GovSlack)
- Cannot downgrade from Grid (lock-in)

---

## 8. Notion

### Tiers

| Tier | Price | Key Inclusions |
|------|-------|----------------|
| Free | $0 | Unlimited pages, 7-day page history, 5 MB file upload |
| Plus | $10/user/mo (annual) | Unlimited file uploads, 30-day history, unlimited guests |
| Business | $20/user/mo (annual) | Notion AI included, private teamspaces, bulk export, 90-day history |
| Enterprise | Custom | SAML SSO, SCIM, audit log, data residency, unlimited history |

**AI**: After May 2025 restructure, Notion AI is included only in Business and Enterprise. Free/Plus cannot access it at any price.

### Isolation Model

- **SaaS only**. No self-hosted or on-premise option whatsoever.
- Multi-tenant shared infrastructure for all tiers.
- Logical isolation by workspace.
- **Data Residency** (Enterprise only): Choose US or EU (Frankfurt, AWS). Japan and South Korea regions rolling out May 2026 for Enterprise customers.
- No customer-managed encryption keys documented.

### Key Enterprise Differentiators
- SAML SSO and SCIM provisioning
- Audit log with user activity tracking
- Data residency (US/EU/JP/KR)
- Advanced permissions and private teamspaces
- Unlimited page history
- Workspace analytics
- Dedicated customer success manager

### Self-hosted Alternatives
Notion has no self-hosted option. The open-source alternatives in this space are AFFiNE, AppFlowy, and Outline.

---

## Cross-Platform Comparison Matrix

### Pricing Summary (per user/month, annual billing)

| Platform | Free | Mid-tier | Top SaaS | Enterprise/Dedicated |
|----------|------|----------|----------|---------------------|
| GitHub (platform) | $0 | $4 (Team) | $21 (Enterprise Cloud) | $21/yr license (Server) |
| GitHub Copilot | $0 | $10 (Pro) | $19 (Business) | $39 (Enterprise) |
| GitLab | $0 | $29 (Premium SaaS) | $99 (Ultimate) | Custom (Dedicated) |
| Linear | $0 | $8 (Standard) | $14 (Plus) | Custom |
| Cursor | $0 | $20 (Pro) | $40 (Teams) | Custom |
| Windsurf | $0 | $15 (Pro) | $30 (Teams) | $60+ |
| Claude Code | $20 (Pro) | $100 (Max 5x) | $100 (Team Premium) | Custom |
| Supabase | $0 | $25 (Pro) | $599 (Team) | Custom |
| Vercel | $0 | $20 (Pro) | -- | ~$45K/yr |
| Netlify | $0 | $9 (Personal) | $20 (Pro) | Custom |
| Slack | $0 | $7.25 (Pro) | $15 (Business+) | Custom (Grid) |
| Notion | $0 | $10 (Plus) | $20 (Business) | Custom |

### Isolation Model Summary

| Platform | Shared Multi-tenant | Logical Isolation | Dedicated SaaS | Self-hosted/On-prem |
|----------|-------------------|-------------------|-----------------|-------------------|
| GitHub | Free/Team/EC | Org-level, SAML | No (EC is still shared) | Enterprise Server |
| GitLab | Free/Premium/Ultimate SaaS | Group/project | Ultimate Plus (Dedicated) | Premium + Ultimate |
| Linear | All tiers | Workspace | No | No |
| Cursor | All tiers | Org-level | Self-hosted agents only | Partial (agents) |
| Windsurf | All tiers | Org-level | "Hybrid" (unclear) | No |
| Claude Code | All tiers | Org-level | VPC via Bedrock/Vertex | No (API via Bedrock) |
| Supabase | Free/Pro | Per-project Postgres | Enterprise | Full Docker stack |
| Vercel | Hobby/Pro | Project/team | Enterprise (Secure Compute) | No |
| Netlify | All tiers | Team/site | No | No |
| Slack | Free/Pro/Business+ | workspace_id + RLS | GovSlack (AWS GovCloud) | No |
| Notion | All tiers | Workspace | No | No |

### Self-hosted Availability

| Platform | Self-hosted? | Notes |
|----------|-------------|-------|
| GitHub | Yes | Enterprise Server, $21/user/yr license + own infra |
| GitLab | Yes | CE (free, MIT) + EE (Premium $19, Ultimate $99) |
| Linear | No | SaaS only, no plans announced |
| Cursor | Partial | Self-hosted agents (March 2026), not the full IDE |
| Windsurf | No | Enterprise "hybrid" mentioned, no details |
| Claude Code | No | But API available via Bedrock/Vertex in customer VPC |
| Supabase | Yes | Full Docker Compose stack, genuinely production-viable |
| Vercel | No | Open-source Next.js, but Vercel platform is SaaS only |
| Netlify | No | SaaS only |
| Slack | No | GovSlack is dedicated but still Slack-managed |
| Notion | No | SaaS only. AFFiNE/AppFlowy/Outline as OSS alternatives |

---

## Key Patterns & Takeaways

### 1. The Three Deployment Models
Almost every platform converges on three levels:
1. **Shared SaaS** (multi-tenant, cheapest, most common)
2. **Dedicated SaaS** (single-tenant, vendor-managed, premium pricing) -- GitLab Dedicated, Vercel Secure Compute, GovSlack
3. **Self-hosted** (customer-managed, full control) -- GitHub Enterprise Server, GitLab Self-Managed, Supabase Docker

### 2. Pricing Jumps at the Enterprise Boundary
The jump from top public tier to enterprise is typically 2-5x:
- Supabase: $25/mo (Pro) to $599/mo (Team) -- 24x jump
- Vercel: $20/user/mo (Pro) to ~$3,750/mo (~$45K/yr) -- massive jump
- GitLab: $99/user/mo (Ultimate) to custom (Dedicated) -- unknown multiplier
- The enterprise tax pays for: SSO, audit logs, compliance certs, SLAs, and dedicated support

### 3. RLS as the Multi-tenancy Standard
Slack and Supabase both use PostgreSQL Row-Level Security for tenant isolation in shared infrastructure. This is the dominant pattern for multi-tenant SaaS on Postgres.

### 4. Self-hosted is Rare Outside DevOps
Only GitHub, GitLab, and Supabase offer genuine self-hosted deployment. The AI coding tools, project management tools, and communication platforms are all SaaS-only (or nearly so). Cursor's self-hosted agents are the most interesting middle ground -- agent execution on customer infra, IDE remains SaaS.

### 5. AI is Reshaping Pricing Models
- GitHub Copilot: premium request quotas (model-dependent)
- Cursor: credit pools (June 2025 switch from request-based)
- Windsurf: shifted from credits to quotas (March 2026)
- Claude Code: token-based API + subscription caps
- All are converging on usage-based pricing gated by model tier

### 6. Data Residency is Enterprise-only
Every platform that offers data residency (GitHub, GitLab, Notion, Linear) gates it behind Enterprise pricing. No mid-tier product offers region selection.

### 7. Government/Regulated = Dedicated Infra
GovSlack (AWS GovCloud), GitLab Dedicated for Government, GitHub Enterprise Server -- regulated industries always get physically isolated infrastructure, never shared. FedRAMP/HIPAA/DoD compliance requires it.

---

## Sources

- [GitHub Pricing](https://github.com/pricing)
- [GitHub Copilot Plans](https://github.com/features/copilot/plans)
- [GitHub Enterprise](https://github.com/enterprise)
- [GitLab Pricing](https://about.gitlab.com/pricing/)
- [GitLab Dedicated Docs](https://docs.gitlab.com/subscriptions/gitlab_dedicated/)
- [Linear Pricing](https://linear.app/pricing)
- [Linear Multi-Region Blog](https://linear.app/now/how-we-built-multi-region-support-for-linear)
- [Cursor Pricing](https://cursor.com/pricing)
- [Cursor Enterprise](https://cursor.com/enterprise)
- [Cursor Self-Hosted Agents (The New Stack)](https://thenewstack.io/cursor-self-hosted-coding-agents/)
- [Windsurf Pricing](https://windsurf.com/pricing)
- [Claude Pricing](https://claude.com/pricing)
- [Anthropic Privacy Center](https://privacy.claude.com/)
- [Supabase Pricing](https://supabase.com/pricing)
- [Supabase Self-Hosting Docs](https://supabase.com/docs/guides/self-hosting/docker)
- [Supabase Compute and Disk Docs](https://supabase.com/docs/guides/platform/compute-and-disk)
- [Vercel Pricing](https://vercel.com/pricing)
- [Vercel Enterprise Plan Docs](https://vercel.com/docs/plans/enterprise)
- [Vercel Build Infrastructure Blog](https://vercel.com/blog/a-deep-dive-into-hive-vercels-builds-infrastructure)
- [Netlify Pricing](https://www.netlify.com/pricing/)
- [Slack Pricing](https://slack.com/pricing)
- [Slack Enterprise Grid](https://slack.com/resources/why-use-slack/slack-enterprise-grid)
- [Slack Unified Grid Architecture](https://slack.engineering/unified-grid-how-we-re-architected-slack-for-our-largest-customers/)
- [GovSlack Engineering Blog](https://slack.engineering/what-we-learned-from-building-govslack/)
- [Slack Multi-Tenancy Architecture](https://dev.to/devcorner/deep-dive-slacks-multi-tenancy-architecture-m38)
- [Notion Pricing](https://www.notion.com/pricing)
- [Notion Data Residency](https://www.notion.com/help/data-residency)
