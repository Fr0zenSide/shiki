---
name: ml-explore/mlx-swift-lm
type: reference
description: LLMs and VLMs running natively via MLX Swift — local AI inference on Apple Silicon
source: https://github.com/ml-explore/mlx-swift-lm
relevance: HIGH — directly applicable to Shikki's local AI inference axis (MLX + CoreML + GGUF)
discovered: 2026-03-28
---

## What It Is

`mlx-swift-lm` is the official Apple MLX team's Swift library for running large language models (LLMs) and vision-language models (VLMs) on Apple Silicon using the MLX framework. It provides a Swift-native API for model loading, tokenization, generation, and streaming inference — no Python runtime required.

## Why It Matters to Shikki

- **Local inference in Swift**: Shikki's local AI inference goals (MLX, CoreML, GGUF) align exactly with this library. Any Shikki Swift component that needs to run a model locally should evaluate this as the baseline.
- **No Python bridge**: Pure Swift — eliminates the overhead of bridging to Python for inference in Mac-native tooling.
- **VLM support**: Vision-language models open up screenshot/visual context features for Shikki agents.
- **Official pedigree**: Maintained by the Apple MLX team — likely to track the MLX roadmap closely.

## Key Patterns to Study

- Model loading API (lazy vs. eager, quantized model support)
- Streaming token generation with Swift async/await
- Tokenizer integration
- How it handles context windows and KV cache on Apple Silicon

## Action Items

- [ ] Run `/ingest https://github.com/ml-explore/mlx-swift-lm` for detailed architecture notes
- [ ] Test with a 3B–7B quantized model to benchmark latency on M-series chips
- [ ] Evaluate as replacement/complement to any existing CoreML inference path in Shikki
