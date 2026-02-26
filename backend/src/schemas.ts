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
