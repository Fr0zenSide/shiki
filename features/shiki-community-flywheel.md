# Feature: Community Data Flywheel — Self-Improving Engine

> **Type**: /md-feature
> **Priority**: P2 — post-launch, but architecture must support it now
> **Status**: Spec (validated by @Daimyo 2026-03-17)
> **Depends on**: Event Bus (Wave 2A — DONE), Shiki DB (existing)

---

## 1. Problem

Shiki collects structured data about agent behavior (events, decisions, watchdog patterns, recovery outcomes, review verdicts) but this data only benefits the local instance. There's no mechanism for the system to improve with usage — every new user starts from the same hardcoded thresholds and heuristics.

Competitors can copy the code. They cannot copy 6 months of calibration data across 500 projects.

## 2. Solution — Data Flywheel

More users → more outcome data → better engine → more value → more users.

### 2A. Risk Scoring Engine (strongest candidate)

**Input**: PRs across projects with post-merge bug data
**Output**: "files matching pattern X with Y complexity have Z% chance of bugs"

Currently `PRRiskEngine` uses heuristics (file size + test coverage). With community data, risk scoring becomes ML-driven — trained on actual outcomes.

### 2B. Watchdog Threshold Learning

**Input**: Watchdog events with outcomes (did agent recover? was it stuck?)
**Output**: Per-language, per-task-type optimal thresholds

A Swift refactoring agent has different idle patterns than a TypeScript test agent. Community data teaches this.

### 2C. Prompt Template Evolution (most unique)

**Input**: Task completions with prompt template used, success rate, context resets
**Output**: Which prompt structures produce best outcomes for which task types

Users don't write prompts — they use Shiki, and Shiki learns which prompts work.

### 2D. Spec Pattern Library

**Input**: Living specs that led to successful implementations
**Output**: Suggested spec structures for common task types

## 3. Privacy Model

```
shiki config --telemetry community    # share anonymized outcomes
shiki config --telemetry local        # local only (default)
shiki config --telemetry off          # no collection
```

**Shared (anonymized)**: task type + outcome, persona chain + effectiveness, watchdog patterns, risk scores vs bug rates, prompt template ID + success rate, time-to-completion buckets.

**Never shared**: source code, diffs, file paths, company names, project details, prompt content, spec content, PII.

## 4. Architecture

```
EventBus (Wave 2A — DONE)
    ↓
CommunityAggregator (new EventPersister — anonymizes + batches)
    ↓
Shiki Cloud API (future — receives anonymized outcomes)
    ↓
Model Training (offline — produces updated configs)
    ↓
shiki update --models (users pull new thresholds/weights)
```

The `CommunityAggregator` is a new `EventPersister` implementation (protocol exists in Wave 2A). It strips PII, aggregates into statistical buckets, and periodically syncs.

## 5. Deliverables

- `CommunityAggregator: EventPersister` — anonymize + batch events
- `TelemetryConfig` — user opt-in/out settings
- `shiki config --telemetry` command
- Cloud API endpoint (post-launch)
- Model training pipeline (post-launch)
- `shiki update --models` command (post-launch)

## 6. What makes this defensible

The value is in the aggregate, not individual data points. Even if someone copies the code:
- They don't have 6 months of watchdog calibration
- They don't have prompt effectiveness scores across 10,000 completions
- They don't have risk patterns trained on real post-merge bugs

This IS the Maya playbook: the engine improves with usage, the improvement is the moat.
