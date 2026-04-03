# Radar: Kokoro TTS -- Lightweight Open-Weight TTS for Local Voice AI
> Date: 2026-04-03 | Source: https://github.com/hexgrad/kokoro

## Overview

**Kokoro** is an open-weight text-to-speech model with **82 million parameters**, created by hexgrad. It is based on the StyleTTS 2 architecture (yl4579) and delivers quality comparable to much larger commercial TTS models despite being 5-10x smaller.

| Metric | Value |
|--------|-------|
| Stars | 6,277 |
| Forks | 704 |
| License | Apache-2.0 |
| Language | Python (pip) + JavaScript (npm) |
| Model Size | 82M params (~330MB weights) |
| Version | v0.9.4 (Python), v1.2.1 (JS) |
| Sample Rate | 24kHz mono |
| Languages | 9 (EN-US, EN-GB, ES, FR, HI, IT, JA, PT-BR, ZH) |
| Voices | 56+ presets (graded A through F) |
| Last Push | 2025-08-06 |
| Open Issues | 163 |

## Architecture

### Model Stack (StyleTTS 2 derivative)

```
Text -> G2P (misaki) -> Phonemes -> [KModel] -> Audio (24kHz)
                                        |
                    +-------------------+-------------------+
                    |                   |                   |
              CustomALBERT        TextEncoder         ProsodyPredictor
              (phoneme BERT)     (CNN+BiLSTM)       (Duration+F0+Noise)
                    |                   |                   |
                    +-------------------+-------------------+
                                        |
                                    Decoder
                              (AdainResBlk1d x4)
                                        |
                                    Generator
                              (iSTFTNet + SineGen)
                                        |
                                   Waveform Out
```

**Key components:**
1. **CustomALBERT (PLBERT)** -- contextual phoneme understanding via ALBERT transformer
2. **TextEncoder** -- weight-normed CNN + bidirectional LSTM
3. **ProsodyPredictor** -- predicts duration, F0 (pitch), noise; style-conditioned via AdaLayerNorm
4. **Decoder** -- 4x AdainResBlk1d blocks with style injection, upsampling to Generator
5. **Generator (iSTFTNet)** -- source-filter model: SineGen for harmonics + inverse STFT for waveform synthesis. Uses Snake activation (sin^2)

**Two-class API design:**
- `KModel` -- language-blind inference engine (one instance shared across languages)
- `KPipeline` -- language-aware wrapper handling G2P, voice management, text chunking, streaming

**Voice representation:** 256-dim style embeddings stored as `.pt` tensors (~50KB each). Supports voice mixing (comma-separated averaging).

### Deployment Paths

| Path | Backend | Quantization | Platform |
|------|---------|-------------|----------|
| Python pip | PyTorch | fp32 | Linux/Mac/Win |
| ONNX export | ORT | fp32 | Server/Edge |
| kokoro-js (npm) | ONNX Runtime Web | fp32/fp16/q8/q4/q4f16 | Browser |
| Apple Silicon | PyTorch MPS | fp32 | Mac M1-M4 |
| Triton | ONNX | fp32 | Cloud GPU |

## Flsh Fit Assessment

### Direct Fit Criteria

| Criterion | Score | Notes |
|-----------|-------|-------|
| Runs locally without cloud | YES | 100% local, weights auto-download once from HuggingFace |
| Apple Silicon support | YES | MPS backend via `PYTORCH_ENABLE_MPS_FALLBACK=1` |
| Model size for Mac/iPhone | EXCELLENT | 82M params. ~330MB fp32, ~80MB q4. Fits any device. |
| MLX support | NOT YET | No native MLX. PyTorch MPS works. ONNX->CoreML path exists. mlx-community may have conversions. |
| Real-time capable | LIKELY | 82M is very small. Sub-RTF on Apple Silicon GPU probable. No published benchmarks. |
| French support | PARTIAL | `ff_siwis` voice exists. Uses espeak-ng G2P (not native French phonemizer). Quality tier below English. |
| License compatibility | YES | Apache-2.0 is compatible with AGPL-3.0. No restrictions on local use. |
| Streaming | YES | Generator pattern yields chunks. JS version has `TextSplitterStream` for LLM-to-TTS piping. |

### Integration Path for Flsh

**Option A: PyTorch MPS (quickest)**
- `pip install kokoro`, set `PYTORCH_ENABLE_MPS_FALLBACK=1`
- Call `KPipeline(lang_code='f')` for French, `'a'` for English
- Wrap in a Swift process via `Process()` or embed via PythonKit
- Downside: PyTorch is a ~2GB dependency

**Option B: ONNX -> CoreML (production path)**
- Export via `examples/export.py` with `disable_complex=True`
- Convert ONNX to CoreML via `coremltools`
- Run natively in Swift via CoreML framework
- Eliminates Python dependency entirely
- q4/q8 quantization for ~20-80MB on-device model

**Option C: MLX conversion (ideal for Flsh)**
- Community MLX ports may exist on HuggingFace (mlx-community)
- If not, the 82M model is small enough for manual conversion
- Would integrate natively with Flsh's MLX ecosystem
- Best latency + Apple Silicon optimization

### Gaps for Flsh

1. **TTS only** -- Kokoro handles speech output but not speech input (STT), voice activity detection, or conversational turn-taking. Flsh needs a separate STT model (Whisper MLX) and VAD.
2. **French quality** -- Only 1 French voice (ff_siwis) vs 27 English voices. espeak-ng G2P for French is functional but not as polished as native English processing.
3. **No emotion control** -- Voice style is fixed per voice embedding. No explicit emotion/sentiment parameter (unlike Moshi's expressive capabilities).
4. **espeak-ng dependency** -- System library needed for French and English OOD fallback. Would need to bundle or replace for iOS.

## Comparison Matrix

| Feature | Kokoro | Moshi (Kyutai) | Pocket TTS (Kyutai) | Parler TTS | Coqui/XTTS |
|---------|--------|----------------|---------------------|------------|-------------|
| **Type** | TTS only | Full-duplex voice conversation | Compact TTS | TTS with description | TTS + voice cloning |
| **Params** | 82M | ~7B (Mimi codec + Helium LM) | ~82M (estimated) | 880M | ~500M |
| **License** | Apache-2.0 | CC-BY-4.0 (weights) | Apache-2.0 | Apache-2.0 | MPL-2.0 |
| **Languages** | 9 | EN, FR | EN, FR | EN | 16+ |
| **French** | 1 voice (espeak G2P) | Native French | Native French | No | Yes |
| **Local inference** | Yes (CPU/GPU/MPS) | Yes (GPU heavy) | Yes | Yes (GPU) | Yes |
| **Apple Silicon** | MPS backend | Too large for M1 | Likely feasible | GPU only | CPU/MPS |
| **Streaming** | Yes (generator) | Yes (real-time) | Unknown | No | Yes |
| **MLX support** | Not yet (convertible) | Not yet | Rust impl (Hibiki) | Not yet | Not yet |
| **ONNX export** | Yes (included) | No | No | No | No |
| **Browser** | Yes (WebGPU/WASM) | No | No | No | No |
| **Voice cloning** | No (preset voices) | No | No | Description-based | Yes |
| **Model download** | ~330MB | ~14GB | Unknown | ~3.5GB | ~2GB |
| **Quality (EN)** | A- (af_heart) | A+ (conversational) | B+ (estimated) | B+ | A- |
| **Real-time factor** | <1x (estimated) | ~1x on GPU | <1x | >1x on CPU | ~1x |

### Key Insight

Kokoro and Moshi are **complementary, not competing**:
- **Moshi** = full conversation engine (STT + LLM + TTS in one loop, real-time duplex)
- **Kokoro** = high-quality TTS output engine (text in, audio out, very lightweight)

For Flsh, the ideal stack could be:
- **STT**: Whisper (MLX) or Moshi's Mimi encoder
- **LLM**: Local model via AgentProvider
- **TTS**: Kokoro (via CoreML/MLX) for speech output
- **VAD**: Silero VAD or Moshi's built-in

## Action Items for Shiki

1. **[P1] Benchmark Kokoro on Apple Silicon** -- Install locally, run `device_examples.py` timing harness on M-series Mac. Measure RTF (real-time factor) for French and English voices. Estimate iPhone feasibility.

2. **[P1] Check mlx-community for Kokoro** -- Search HuggingFace `mlx-community` org for existing Kokoro MLX conversions. If none exist, evaluate manual conversion effort (82M model is small enough).

3. **[P2] CoreML conversion proof-of-concept** -- Run `examples/export.py` to get ONNX, then `coremltools.convert()` to CoreML. Test inference from Swift. This is the production path for Flsh iOS.

4. **[P2] Evaluate French voice quality** -- Generate sample sentences with `ff_siwis` voice, compare against Pocket TTS and Moshi French output. French quality is critical for Flsh's target market.

5. **[P3] Voice cloning investigation** -- Kokoro uses fixed 256-dim style embeddings. Investigate if custom voices can be trained/fine-tuned with the StyleTTS 2 training pipeline (separate repo). Would enable personalized Flsh voice.

6. **[WATCH] Hibiki (Kyutai)** -- Rust-native TTS from Kyutai. If it matures with French support + Apple Silicon, it could be a stronger Flsh fit than Kokoro. Monitor monthly.

## Verdict

**INTEGRATE (conditional)** -- Kokoro is the strongest candidate for Flsh's TTS layer.

**Reasoning:**
- 82M parameters is the sweet spot: small enough for iPhone, large enough for near-production quality
- Apache-2.0 license is clean for AGPL-3.0 projects
- ONNX export path provides a clear CoreML conversion pipeline for native Swift/iOS
- MPS support already works on Apple Silicon today
- French language support exists (even if limited to 1 voice)
- The browser deployment via kokoro-js demonstrates the model runs on constrained hardware

**Condition:** Benchmark on Apple Silicon first. If RTF < 0.5x on M1 for French, proceed with CoreML conversion. If RTF > 1x, investigate MLX conversion or wait for Hibiki.

**Role in Flsh stack:** TTS output engine, sitting behind AgentProvider's LLM response. Not a replacement for Moshi's full conversation loop -- use Kokoro for high-quality speech synthesis, use Moshi patterns for the conversation orchestration.
