# 22.3 The Travel Animation and Map Shift

When the player initiates a move, the table **shifts perspective visually.** The pin marking the player's current location lifts and travels across the era-appropriate map to the new city — following the route the player has chosen, moving at the realistic speed of travel for the era.

The journey is shown as a **continuous animation** rather than an instant transition.

## Route matters mechanically

- Travelling through provinces where the player has **coordinator coverage** is faster and produces intelligence along the way — local reports are available from familiar sources.
- Travelling through **dark territory** is slower, produces no intelligence, and means the player is operating without a safety net for that leg of the journey.

| **Route type** | **Travel speed** | **Intelligence during travel** | **Risk level** |
| --- | --- | --- | --- |
| **Covered route** — coordinator presence throughout | Full era speed | Current reports from sources along the way | Minimal — established network provides situational awareness |
| **Partially covered route** | Era speed with gaps | Intelligence available only in covered segments | Low to moderate — dark segments are brief and bounded |
| **Dark route** — no coverage | Era speed, no advantage | None until destination | Moderate — player cannot respond to events during transit |
| **Route through hostile territory** | Slowed by caution | None, plus risk of route intelligence being observed | Elevated — only attempted if no alternative route exists |
