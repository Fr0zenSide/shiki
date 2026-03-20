# Design Slop Audit — AI-Generated Pattern Detection

> Used by @Hanami and @Metsuke during design review.
> Invoke via `shiki review --design` or `@Hanami` mention with design context.

## How to Use

Score each section: CLEAN (0 findings) / ACCEPTABLE (1-2 minor) / SLOP (3+ or any critical).
Overall verdict: ALL sections CLEAN or ACCEPTABLE → PASS. Any SLOP → NEEDS WORK.

---

## 1. Layout & Structure (10 items)

- [ ] No generic card grid that adds nothing (cards for the sake of cards)
- [ ] No unnecessary hero section with stock gradient background
- [ ] Spacing is intentional, not uniform padding everywhere
- [ ] Content hierarchy exists — not everything is the same visual weight
- [ ] Sections serve a purpose — no "features" section with 3 generic icons
- [ ] No orphaned whitespace (large gaps with no content purpose)
- [ ] Grid doesn't break at intermediate viewport widths
- [ ] Scroll depth is justified — no padding to make the page feel "longer"
- [ ] Navigation structure matches actual content depth
- [ ] Footer isn't a dumping ground of links nobody clicks

## 2. Typography (8 items)

- [ ] Font pairing is intentional (not default system font + random Google Font)
- [ ] Heading hierarchy is semantic (h1 > h2 > h3, not visual-only sizing)
- [ ] Line length stays 45-75 characters for body text
- [ ] No text that says nothing ("We believe in excellence" / "Powered by innovation")
- [ ] Dynamic Type / responsive text sizing works (not fixed px everywhere)
- [ ] Text contrast passes WCAG AA (4.5:1 body, 3:1 large text)
- [ ] No walls of text without visual breaks
- [ ] Truncation/overflow handled (long names, translations, edge cases)

## 3. Color & Visual (10 items)

- [ ] No generic blue-to-purple gradient as primary visual
- [ ] Color palette has a reason (brand, emotion, accessibility) — not "AI picked nice colors"
- [ ] Dark mode isn't just inverted colors (shadows, contrast ratios rechecked)
- [ ] No more than 3-4 primary colors (not a rainbow)
- [ ] Hover/focus/active states exist and are distinct
- [ ] No decorative elements that don't serve comprehension
- [ ] Shadows are consistent (not 5 different shadow styles)
- [ ] Border radius is consistent (not mixing sharp and round arbitrarily)
- [ ] Opacity/transparency used sparingly (not everything at 0.7)
- [ ] No glassmorphism/neumorphism unless it's the actual design system

## 4. Icons & Imagery (8 items)

- [ ] Icons mean something specific (not generic "gear" for every settings concept)
- [ ] Icon style is consistent (not mixing outlined, filled, and custom in one view)
- [ ] No placeholder illustrations that could be any SaaS landing page
- [ ] Images are real content or real mockups (not Unsplash stock pretending to be the product)
- [ ] Icon sizes are consistent within the same context
- [ ] No icons used as decoration (icon + text where text alone is clearer)
- [ ] SVG/SF Symbols used properly (not rasterized icons at wrong sizes)
- [ ] Empty states have intentional design (not just "No data" text)

## 5. Interaction & Motion (8 items)

- [ ] Animations serve a purpose (guide attention, show state change)
- [ ] No animation for animation's sake (bouncing logos, spinning loaders where unnecessary)
- [ ] Transitions are fast (150-300ms) — not slow-motion reveals
- [ ] Loading states exist (not blank screen → sudden content)
- [ ] Touch targets are 44pt minimum (iOS HIG)
- [ ] Scroll behavior is native (no hijacked scroll, parallax abuse)
- [ ] Reduced Motion preference is respected
- [ ] Micro-interactions give feedback (button press, toggle state, success/error)

## 6. Copy & Content (8 items)

- [ ] Headlines say something specific (not "Welcome to [Product]")
- [ ] CTAs are action-oriented and specific ("Start free trial" not "Get started")
- [ ] No buzzword bingo ("AI-powered", "next-gen", "seamless", "revolutionary")
- [ ] Error messages are human-readable and actionable
- [ ] Placeholder text is gone (no "Lorem ipsum" or "TODO" in production)
- [ ] Tone is consistent across all screens
- [ ] Numbers and data are formatted properly (locale-aware)
- [ ] Empty state copy guides the user to action

## 7. Component Quality (8 items)

- [ ] Forms have proper validation (inline, not alert popup)
- [ ] Buttons have only 2-3 visual variants (primary, secondary, destructive)
- [ ] No component does two unrelated things (button that's also a link that's also a toggle)
- [ ] Lists handle 0, 1, and 1000 items gracefully
- [ ] Modals/sheets are used sparingly (not modal-in-modal)
- [ ] Tables work on mobile (horizontal scroll or card layout)
- [ ] Switches/toggles show their current state clearly
- [ ] Destructive actions require confirmation

## 8. AI-Specific Slop Patterns (10 items)

- [ ] No "dashboard" layout when a simple list would do
- [ ] No unnecessary charts/graphs with fake data shapes
- [ ] Component names are specific ("UserProfileCard" not "Card1")
- [ ] No over-abstraction (generic `<Container>` wrapping everything)
- [ ] No commented-out code blocks with "// TODO: implement"
- [ ] No hardcoded strings that should be localized
- [ ] No excessive prop drilling / configuration objects for one-time components
- [ ] No skeleton loaders for content that loads in <100ms
- [ ] No "smart" defaults that hide important configuration
- [ ] No feature flags for features that will obviously ship

---

## Scoring

| Section | Items | Score |
|---------|-------|-------|
| Layout & Structure | /10 | |
| Typography | /8 | |
| Color & Visual | /10 | |
| Icons & Imagery | /8 | |
| Interaction & Motion | /8 | |
| Copy & Content | /8 | |
| Component Quality | /8 | |
| AI-Specific Slop | /10 | |
| **Total** | **/70** | |

**CLEAN**: 0-3 findings | **ACCEPTABLE**: 4-8 findings | **SLOP**: 9+ findings
