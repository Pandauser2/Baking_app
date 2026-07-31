# V2 Backlog

Product improvements deferred from Phase B MVP. These are not release blockers.

## Open Items

### V2-001 — Make the active starter card clearly tappable and add a visible View starter details affordance

- **Priority:** P2 UX improvement
- **Area:** Home
- **Status:** Open
- **Date logged:** 2026-07-31

#### Evidence

During manual QA, the product owner could not identify how to open starter details from Home and asked which button to tap.

#### Problem

- The active starter summary card visually appears important but is not an obvious navigation control.
- The only explicit entry point is `Open starter details` inside the separate Recent activity card.
- This creates unnecessary ambiguity.

#### Proposed V2 behavior

- Make the entire active starter card clearly tappable.
- Add a visible `View starter details` affordance inside the card.
- Preserve accessibility labels and adequate tap target.
- Do not rely on Recent activity as the primary details entry point.

#### Acceptance criteria

- A user can identify the starter-details entry point without guidance.
- Tapping anywhere on the starter card opens details.
- VoiceOver announces the card as a button/link.
- Existing Home actions remain unchanged.

#### Note

Logged for V2 only. Do not implement in Phase B.
