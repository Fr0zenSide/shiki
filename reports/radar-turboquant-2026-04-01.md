# Radar: TurboQuant -- Google's Extreme KV-Cache Compression

**Date**: 2026-04-01
**Source**: [Google Research Blog](https://research.google/blog/turboquant-redefining-ai-efficiency-with-extreme-compression/) (published 2026-03-24)
**Papers**: [TurboQuant](https://arxiv.org/abs/2504.19874) (ICLR 2026), [PolarQuant](https://arxiv.org/abs/2502.02617) (AISTATS 2026), [QJL](https://arxiv.org/abs/2406.03482)
**Authors**: Amir Zandieh (Research Scientist), Vahab Mirrokni (VP / Google Fellow), + 6 collaborators

---

## 1. What is TurboQuant?

TurboQuant is a **KV-cache quantization** algorithm -- NOT a weight quantization method. This is the critical distinction.

It compresses the Key-Value embeddings that accumulate during LLM inference, which grow linearly with sequence length and become the dominant memory bottleneck for long-context workloads.

**Two-stage pipeline:**

1. **PolarQuant (Stage 1)**: Randomly rotates data vectors into polar coordinates where angles exhibit tightly bounded distributions. Applies optimal scalar quantizers per dimension. No normalization constants needed, reducing storage overhead.
2. **QJL (Stage 2)**: Applies a 1-bit Quantized Johnson-Lindenstrauss transform to the residual errors from Stage 1. Zero memory overhead -- eliminates the zero points and scale factors that traditional quantization requires.

**Key property**: Post-training, requires ZERO fine-tuning or retraining. Pure inference-time optimization.

## 2. Compression Levels

| Bits per channel | Quality impact | KV-cache reduction |
|------------------|----------------|-------------------|
| 3.5-bit | Zero accuracy loss | ~9x vs FP32 |
| 3-bit | Zero accuracy loss (blog claim) | ~10x vs FP32 |
| 2.5-bit | Marginal quality degradation | ~12x vs FP32 |
| KV memory overall | -- | At least 6x (blog) |

Information-theoretically near-optimal: only ~2.7x factor from theoretical lower bounds.

## 3. Quality vs Size Tradeoff

**Zero accuracy loss at 3-bit** across all tested benchmarks:

- LongBench
- Needle In A Haystack
- ZeroSCROLLS
- RULER
- L-Eval

At 4-bit, achieves **8x performance speedup** over 32-bit unquantized keys on H100 GPUs. Faster runtime than the original uncompressed models (Gemma, Mistral).

"Perfect downstream results across all benchmarks while reducing the key value memory size."

Also validated on vector search (GloVe dataset, d=200): "consistently achieves superior recall ratios compared to baseline methods" including Product Quantization and RabbiQ.

## 4. Tested Models

- **Gemma** (Google)
- **Mistral**
- **Llama-3.1-8B-Instruct** (Meta)

All open-source transformer-based LLMs. No vision model testing mentioned.

## 5. Open Source Status

**Not available.** No code repository linked in the blog post. The underlying QJL paper mentions "codes are available" on GitHub, but TurboQuant itself (the combined system) has no public release announced. PolarQuant also has no stated code availability.

**Verdict**: Research-only as of 2026-03-30.

## 6. Comparison to GGUF Quantization (llama.cpp / MLX)

This is where the honest assessment matters. TurboQuant and GGUF/MLX quantization solve **completely different problems**:

| Aspect | TurboQuant | GGUF (llama.cpp / MLX) |
|--------|-----------|----------------------|
| **Target** | KV-cache (activations at inference time) | Model weights (static) |
| **When applied** | During inference, on-the-fly | Pre-quantized, saved to disk |
| **What it shrinks** | Runtime memory for long sequences | Model file size + VRAM for weights |
| **Bit-widths** | 2.5-3.5 bit KV entries | Q2_K through Q8_0 for weights |
| **Complementary?** | **YES** -- can stack on top of GGUF | Yes -- KV-cache is separate from weights |
| **Hardware** | H100 CUDA kernels demonstrated | CPU, Metal (Apple Silicon), CUDA |
| **Apple Silicon** | No support mentioned | Native via MLX and llama.cpp |

**They are orthogonal.** You could theoretically run a Q4 GGUF model AND use TurboQuant-style KV-cache compression simultaneously. One shrinks the model, the other shrinks the context window memory.

---

## Shikki Ecosystem Evaluation

### AIKit / Local Inference

**Impact: LOW (currently), HIGH (if ported to Metal)**

TurboQuant does NOT help you fit a larger model into less RAM. It helps you run longer context windows within the same RAM budget. A 70B model that needs 40GB for weights still needs 40GB -- but the KV-cache that balloons during a 128K-token conversation would shrink 6-10x.

On Apple Silicon (M4 Max with 128GB unified memory), the bottleneck is usually weight memory, not KV-cache. For a 7B Q4 model (~4GB weights), the KV-cache at 8K context is only ~256MB. TurboQuant would compress that to ~25MB -- nice but not game-changing.

**Where it matters**: Running 70B+ models at 128K+ context where the KV-cache can exceed 8-16GB. On an M4 Max, this is the scenario where TurboQuant would unlock capabilities you cannot achieve today.

**Blocker**: No Metal/MLX implementation exists. Only CUDA kernels demonstrated.

### AgentProvider (Local models vs Claude for code generation)

**Impact: NEGLIGIBLE**

TurboQuant does not improve model quality. A local Mistral-7B with compressed KV-cache produces the exact same outputs as without it (that is the point -- zero accuracy loss). The quality gap between local 7B models and Claude for code generation is about model capability, not inference efficiency.

Local models are not going to become competitive with Claude for code generation because of better KV-cache compression. They need better weights, better training, better architecture. TurboQuant does not address any of that.

### Flsh Revival (Voice models on-device)

**Impact: LOW-MODERATE**

Voice models (Whisper, Moshi, Pocket TTS, Hibiki) are typically short-context. A 30-second audio clip transcription does not generate massive KV-caches. TurboQuant's benefit scales with sequence length -- voice inference is usually <1K tokens.

One scenario where it helps: streaming voice-to-voice with long conversation history (Moshi-style). If you maintain a growing KV-cache across a 30-minute conversation, TurboQuant could keep that in memory. But this is a niche use case and the models need Metal support first.

### Cost Reduction (API costs to zero)

**Impact: ZERO**

TurboQuant does not change the fundamental equation. API costs are driven by using powerful frontier models (Claude, GPT-4). Local models are already free to run. TurboQuant does not make local models better -- it just makes their KV-cache smaller. You can already run Llama-3.1-8B locally for zero cost; the problem is it is not good enough to replace Claude for complex tasks.

---

## Honest Assessment

### Production-ready?

**No.** This is a research paper with CUDA kernel implementations tested on H100 GPUs. No public code for the full TurboQuant pipeline. No integration with any inference framework (vLLM, llama.cpp, MLX, TensorRT-LLM).

### Works with MLX?

**No.** Zero Apple Silicon support. The CUDA kernels would need to be rewritten for Metal. The algorithmic ideas (random rotation + polar transform + 1-bit residual) are portable, but someone needs to write the Metal shaders.

### Timeline to usability

| Milestone | Estimate |
|-----------|----------|
| Google releases code | 3-6 months (ICLR 2026 publication incentive) |
| Community ports to llama.cpp | 6-12 months after code release |
| MLX integration | 12-18 months (if Apple or community picks it up) |
| Production-ready for local inference | 18-24 months minimum |

### What to actually watch

The real advances for the Shikki ecosystem in quantization are:

1. **llama.cpp IQ (importance-aware) quants** -- already shipping, Q2 and Q3 variants that are better than naive low-bit. Available NOW on MLX.
2. **MLX quantization improvements** -- Apple's team is actively improving their quantization. Metal-native, available today.
3. **KV-cache quantization in vLLM** -- server-side, if we ever run inference servers. Already partially implemented.
4. **BitNet / 1-bit LLMs** -- Microsoft's approach to training 1-bit models from scratch. Different paradigm, more promising for truly tiny local models.

---

## Verdict

**PARK.** TurboQuant is an elegant piece of research that solves KV-cache compression near-optimally. But for the Shikki ecosystem:

- It does not solve our bottleneck (model quality, not KV-cache size)
- It has no Apple Silicon support
- It is not open source
- The timeline to usability is 18+ months
- Existing GGUF/MLX quantization is more relevant and available today

**Re-evaluate when**: (a) Google releases code, (b) someone ports it to Metal/MLX, or (c) we start running 128K+ context inference locally where KV-cache becomes the bottleneck.

**One-line summary**: Impressive KV-cache compression research from Google, but solves the wrong bottleneck for local Apple Silicon inference and is 18+ months from being usable in our stack.
