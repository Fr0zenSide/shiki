# @Hanami — UX Review Checklist

Run this checklist when UI changes are detected in the diff. Mark each item PASS/FAIL/N/A.
Only invoked when UI files are modified (detection based on project adapter platform).

## Accessibility

- [ ] All interactive elements have accessibility labels or visible text
- [ ] Custom controls have appropriate accessibility traits
- [ ] Screen reader reading order makes semantic sense
- [ ] Accessibility hints on non-obvious actions
- [ ] Images have accessibility labels or are marked decorative

## Dynamic Type / Text Scaling

- [ ] No hardcoded font sizes (use system-relative sizes)
- [ ] If custom sizes used, they scale with system settings
- [ ] Layout doesn't break at large text sizes
- [ ] Truncation handled gracefully

## Color & Contrast

- [ ] WCAG AA contrast ratio met (4.5:1 for text, 3:1 for large text)
- [ ] Colors use project design tokens, not hardcoded values
- [ ] Dark mode / theme variant verified
- [ ] No information conveyed by color alone (use icons/labels alongside)

## Touch / Click Targets

- [ ] All tappable areas >= 44pt x 44pt (mobile) or adequately sized (web)
- [ ] Adequate spacing between adjacent targets
- [ ] Interactive areas have sufficient hit area

## States

- [ ] Loading state shown during async operations
- [ ] Empty state with helpful message (not blank screen)
- [ ] Error state with user-actionable message
- [ ] Disabled state visually distinct

## Motion & Animation

- [ ] Animations respect reduced motion preferences
- [ ] No auto-playing animations without user opt-in
- [ ] Transitions are smooth (0.2-0.4s duration, ease curves)
- [ ] No jarring layout shifts during state changes

## Navigation

- [ ] Follows project navigation pattern (per project adapter)
- [ ] Back navigation works correctly
- [ ] Modal/sheet dismissal works via gesture and button
- [ ] Deep links resolve correctly (if applicable)

## Design Philosophy

- [ ] Design feels calm, unhurried — no urgency or pressure
- [ ] Negative space used intentionally
- [ ] Consistent with project brand identity
- [ ] Authentic, not decorative

## Output Format

```markdown
## @Hanami Review
| Category | Status | Issues |
|----------|--------|--------|
| Accessibility | FAIL | CTA button missing label |
| Text Scaling | PASS | — |
| Color | PASS | — |
| Touch Targets | PASS | — |
| States | FAIL | No empty state for list |
| Motion | N/A | No animations |
| Navigation | PASS | — |
| Philosophy | PASS | — |
```
