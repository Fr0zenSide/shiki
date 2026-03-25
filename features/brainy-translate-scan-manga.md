---
title: "Brainy Translate — On-the-fly Scan & Manga Translation"
status: draft
priority: P1
project: brainy
source: "Koharu (github.com/mayocream/koharu) + @team review"
created: 2026-03-25
---

# Brainy Translate — On-the-fly Scan & Manga Translation

## Summary

Dual-mode translation pipeline for Brainy: **Book/Scan mode** (overlay-based, illustration-aware) and **Manga/Manhwa mode** (inpaint + styled re-rendering). Adapted from Koharu's 5-stage Rust architecture. ~2,400 LOC across 6 waves.

## Motivation

No RSS/reading app does real-time scan translation with illustration awareness. Competitors translate text blobs. Brainy translates **pages as visual compositions** — preserving the reading experience across languages.

## Dual-Mode Architecture

```
ScanPage
  → LayoutDetector (PPDocLayoutV3 or Apple Vision)
    → regions: [TextRegion, IllustrationRegion, CaptionRegion, BubbleRegion]
  → OCR (Apple Vision for Latin, PaddleOCR-VL for CJK)
    → TextRegion.source_text
  → [Manga only] Inpaint (LaMa — remove original text)
    → clean background
  → LLMTranslator (AgentProvider: local GGUF | Claude API)
    → TextRegion.translated_text
  → Composer
    → [Book] Semi-transparent overlay + preserved illustrations
    → [Manga] Inpainted + styled text (stroke, color, vertical)
```

### Mode Comparison

| | Book/Scan Mode | Manga/Manhwa Mode |
|---|---|---|
| Detection | PPDocLayoutV3 | PPDocLayoutV3 + ComicTextDetector |
| OCR | Apple Vision / PaddleOCR-VL | PaddleOCR-VL (comic-trained) |
| Inpaint | Skip (overlay instead) | LaMa-manga (remove original text) |
| Translation | Paragraph-level, formal | Bubble-level, conversational tone |
| Rendering | Semi-transparent overlay | Inpainted + styled text (stroke, color) |
| Layout | Preserve illustrations, flow text | Preserve panels, respect reading order |
| Writing mode | Horizontal LTR | Horizontal + Vertical RTL (manga) |
| SFX | N/A | Detect + option to preserve or translate |
| Reading order | L→R top→bottom | R→L (manga) or L→R (manhwa) |

## Koharu Patterns Reused

1. **XML block tagging** — `<block id="N">text</block>` for multi-region pages
2. **AnyProvider trait** → AgentProvider protocol (runtime LLM switching)
3. **Broadcast progress** → ShikiCore event bus
4. **Lazy model loading** — download GGUF on demand
5. **PPDocLayoutV3** — handles both books and comics
6. **ComicTextDetector** — manga-specific bubble segmentation
7. **LaMa inpainting** — clean text removal for manga
8. **FontDetector** — predict text color, stroke, size for manga styling
9. **3-level output parsing** — XML tags → line split → pad/truncate fallback
10. **Parallel rendering** — rayon-style concurrent block processing

## Waves

### Wave 1 — Core Pipeline (~500 LOC, 15 tests)
- `ScanPageModel` — Document equivalent (regions, source image, translated layers)
- `LayoutDetector` protocol — pluggable detection backends
- `TranslationPipeline` orchestrator — 5-stage sequential execution
- `BlockTagger` — XML block format for LLM input/output
- `TranslationMode` enum — `.book` vs `.manga(readingOrder: .rightToLeft)`
- CLI: `brainy translate scan.jpg --to en --mode manga`

### Wave 2 — OCR Adapters (~350 LOC, 10 tests)
- `OCRProvider` protocol
- `AppleVisionOCR` — Latin/printed text, on-device, free
- `PaddleOCRAdapter` — CJK, comic-trained (PaddleOCR-VL)
- Text direction detection (vertical if height >= width * 1.15)

### Wave 3 — LLM Translation (~350 LOC, 12 tests)
- AgentProvider integration
- System prompts: formal (book) vs conversational (manga)
- `BlockParser` — XML block input/output with 3-level fallback
- `SFXDetector` — identify sound effects, option to preserve or translate
- Quote stripping, XML escaping

### Wave 4 — Manga Mode (~500 LOC, 15 tests)
- `InpaintProvider` — LaMa integration for text removal
- `StyledTextRenderer` — stroke/fill, font prediction, vertical writing
- `BubbleDetector` — ComicTextDetector for speech bubble segmentation
- `ReadingOrderDetector` — manga R→L vs manhwa L→R

### Wave 5 — Book Mode (~350 LOC, 8 tests)
- `OverlayComposer` — semi-transparent translated text overlay
- `IllustrationDetector` — never obscure images
- `PDFExporter` — export with translation layer

### Wave 6 — SwiftUI Reader + Camera AR (~400 LOC, 6 tests)
- `TranslateReaderView` — page-by-page, pinch-zoom, overlay toggle
- `ScanCameraView` — live Apple Vision + ARKit real-time overlay
- `TranslationOverlayView` — AR text rendering

## Estimated Totals

| Metric | Value |
|---|---|
| Source LOC | ~2,450 |
| Tests | ~66 |
| Waves | 6 |
| Dependencies | Apple Vision, PaddleOCR-VL, LaMa, PPDocLayoutV3 |

## Phased Delivery

- **Phase 1**: CLI `brainy translate` (Waves 1-3) — pipeline works end-to-end
- **Phase 2**: Manga mode (Wave 4) — inpaint + styled rendering
- **Phase 3**: Book overlay + PDF (Wave 5) — overlay composition
- **Phase 4**: SwiftUI + Camera AR (Wave 6) — full mobile experience

## @team Review Notes

- **@Sensei**: Dual-mode sharing one pipeline, mode selected by detection or user. AgentProvider protocol for LLM flexibility.
- **@Hanami**: Never obscure illustrations. Translation overlays semi-transparent, dismissable. Manga preserves panel reading order.
- **@Kintsugi**: Translation is access. Visual experience preserved across languages. Illustrations are content, not decoration.
- **@Shogun**: Killer differentiator — no RSS reader translates visual pages. Positions Brainy as "the reading AI".
