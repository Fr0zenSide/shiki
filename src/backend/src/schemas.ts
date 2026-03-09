import { z } from "zod";

// --- Agent Event ---
export const AgentEventSchema = z.object({
  agentId: z.string().uuid(),
  sessionId: z.string().uuid(),
  projectId: z.string().uuid(),
  eventType: z.string().min(1).max(100),
  payload: z.record(z.unknown()).optional().default({}),
  progressPct: z.number().int().min(0).max(100).optional(),
  message: z.string().max(10000).optional(),
});
export type AgentEventInput = z.infer<typeof AgentEventSchema>;

// --- Performance Metric ---
export const PerformanceMetricSchema = z.object({
  agentId: z.string().uuid(),
  sessionId: z.string().uuid(),
  projectId: z.string().uuid(),
  metricType: z.string().min(1).max(100),
  tokensInput: z.number().int().min(0).optional(),
  tokensOutput: z.number().int().min(0).optional(),
  durationMs: z.number().int().min(0).optional(),
  costUsd: z.number().min(0).optional(),
  model: z.string().max(200).optional(),
});
export type PerformanceMetricInput = z.infer<typeof PerformanceMetricSchema>;

// --- Chat Message ---
export const ChatMessageSchema = z.object({
  sessionId: z.string().uuid(),
  projectId: z.string().uuid(),
  agentId: z.string().uuid().optional(),
  role: z.enum(["user", "assistant", "system", "orchestrator"]).optional().default("assistant"),
  content: z.string().min(1).max(100000),
  tokenCount: z.number().int().min(0).optional(),
  metadata: z.record(z.unknown()).optional().default({}),
});
export type ChatMessageInput = z.infer<typeof ChatMessageSchema>;

// --- Memory ---
export const MemorySchema = z.object({
  projectId: z.string().uuid(),
  sessionId: z.string().uuid().optional(),
  agentId: z.string().uuid().optional(),
  content: z.string().min(1).max(50000),
  category: z.string().min(1).max(100).optional().default("general"),
  importance: z.number().min(0).max(10).optional().default(1.0),
});
export type MemoryInput = z.infer<typeof MemorySchema>;

// --- Memory Search ---
export const MemorySearchSchema = z.object({
  query: z.string().min(1).max(5000),
  projectId: z.string().uuid(),
  limit: z.number().int().min(1).max(100).optional().default(10),
  threshold: z.number().min(0).max(1).optional().default(0.7),
});
export type MemorySearchInput = z.infer<typeof MemorySearchSchema>;

// --- Data Sync ---
export const DataSyncSchema = z.object({
  projectId: z.string().uuid(),
  sessionId: z.string().uuid().optional(),
  type: z.string().min(1).max(100),
  data: z.record(z.unknown()),
});
export type DataSyncInput = z.infer<typeof DataSyncSchema>;

// --- PR Created ---
export const PrCreatedSchema = z.object({
  projectId: z.string().uuid(),
  sessionId: z.string().uuid().optional(),
  agentId: z.string().uuid().optional(),
  prUrl: z.string().url(),
  title: z.string().min(1).max(500),
  branch: z.string().min(1).max(200),
  baseBranch: z.string().min(1).max(200).optional().default("main"),
  metadata: z.record(z.unknown()).optional().default({}),
});
export type PrCreatedInput = z.infer<typeof PrCreatedSchema>;

// --- Ingestion ---
export const IngestChunkSchema = z.object({
  content: z.string().min(1).max(50000),
  category: z.string().min(1).max(100).optional(),
  importance: z.number().min(0).max(10).optional(),
  filePath: z.string().optional(),
  chunkIndex: z.number().int().min(0).optional(),
});

export const IngestRequestSchema = z.object({
  projectId: z.string().uuid(),
  sourceType: z.enum(["github_repo", "local_path", "url", "raw_text"]),
  sourceUri: z.string().min(1).max(2000),
  displayName: z.string().max(200).optional(),
  contentHash: z.string().max(128).optional(),
  chunks: z.array(IngestChunkSchema).min(1).max(500),
  totalChunks: z.number().int().min(1).optional(),
  config: z.object({
    dedupThreshold: z.number().min(0).max(1).optional().default(0.92),
    autoCategory: z.boolean().optional().default(true),
  }).optional().default({}),
});
export type IngestRequestInput = z.infer<typeof IngestRequestSchema>;

export const IngestSourceQuerySchema = z.object({
  projectId: z.string().uuid(),
});

// --- Radar ---
export const RadarWatchItemSchema = z.object({
  slug: z.string().min(1).max(200),
  kind: z.enum(["repo", "dependency", "technology"]),
  name: z.string().min(1).max(200),
  sourceUrl: z.string().url().optional(),
  relevance: z.string().max(500).optional(),
  tags: z.array(z.string().max(50)).optional().default([]),
  metadata: z.record(z.unknown()).optional().default({}),
});
export type RadarWatchItemInput = z.infer<typeof RadarWatchItemSchema>;

export const RadarScanTriggerSchema = z.object({
  itemIds: z.array(z.string().uuid()).optional(),
  sinceDays: z.number().int().min(1).max(365).optional().default(30),
});
export type RadarScanTriggerInput = z.infer<typeof RadarScanTriggerSchema>;

export const RadarIngestSchema = z.object({
  scanRunId: z.string().uuid(),
  projectId: z.string().uuid(),
});
export type RadarIngestInput = z.infer<typeof RadarIngestSchema>;

// --- Pipeline Run ---
export const PipelineRunCreateSchema = z.object({
  pipelineType: z.enum(["quick", "md-feature", "dispatch", "pre-pr", "review"]),
  projectId: z.string().uuid().optional(),
  sessionId: z.string().uuid().optional(),
  config: z.record(z.unknown()).optional().default({}),
  initialState: z.record(z.unknown()).optional().default({}),
  metadata: z.record(z.unknown()).optional().default({}),
});
export type PipelineRunCreateInput = z.infer<typeof PipelineRunCreateSchema>;

export const PipelineRunUpdateSchema = z.object({
  status: z.enum(["running", "completed", "failed", "cancelled", "resuming"]).optional(),
  currentPhase: z.string().max(100).optional(),
  state: z.record(z.unknown()).optional(),
  error: z.string().max(10000).optional(),
});
export type PipelineRunUpdateInput = z.infer<typeof PipelineRunUpdateSchema>;

export const PipelineCheckpointSchema = z.object({
  phase: z.string().min(1).max(100),
  phaseIndex: z.number().int().min(0),
  status: z.enum(["completed", "failed", "skipped"]).optional().default("completed"),
  stateBefore: z.record(z.unknown()).optional().default({}),
  stateAfter: z.record(z.unknown()).optional().default({}),
  output: z.record(z.unknown()).optional().default({}),
  error: z.string().max(10000).optional(),
  durationMs: z.number().int().min(0).optional(),
  metadata: z.record(z.unknown()).optional().default({}),
});
export type PipelineCheckpointInput = z.infer<typeof PipelineCheckpointSchema>;

export const PipelineResumeSchema = z.object({
  fromPhase: z.string().max(100).optional(),
  stateOverrides: z.record(z.unknown()).optional().default({}),
});
export type PipelineResumeInput = z.infer<typeof PipelineResumeSchema>;

export const PipelineRoutingRuleSchema = z.object({
  pipelineType: z.string().min(1).max(50),
  sourcePhase: z.string().min(1).max(100),
  condition: z.enum(["on_failure", "on_success", "on_skip", "always"]),
  targetAction: z.string().min(1).max(100),
  config: z.record(z.unknown()).optional().default({}),
  priority: z.number().int().min(0).max(100).optional().default(0),
  enabled: z.boolean().optional().default(true),
});
export type PipelineRoutingRuleInput = z.infer<typeof PipelineRoutingRuleSchema>;

export const PipelineRouteEvalSchema = z.object({
  failedPhase: z.string().min(1).max(100),
});
export type PipelineRouteEvalInput = z.infer<typeof PipelineRouteEvalSchema>;

// --- WebSocket Messages ---
export const WsSubscribeSchema = z.object({
  type: z.literal("subscribe"),
  channel: z.string().min(1).max(200),
});

export const WsChatSchema = z.object({
  type: z.literal("chat"),
  sessionId: z.string().uuid(),
  projectId: z.string().uuid(),
  agentId: z.string().uuid().optional(),
  role: z.enum(["user", "assistant", "system", "orchestrator"]).optional().default("assistant"),
  content: z.string().min(1).max(100000),
});

export const WsUnsubscribeSchema = z.object({
  type: z.literal("unsubscribe"),
  channel: z.string().min(1).max(200),
});

export const WsMessageSchema = z.discriminatedUnion("type", [
  WsSubscribeSchema,
  WsChatSchema,
  WsUnsubscribeSchema,
]);
export type WsMessage = z.infer<typeof WsMessageSchema>;
