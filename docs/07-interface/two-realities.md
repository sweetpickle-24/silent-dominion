# 7.6 Two Realities — Ground Truth and the Player's Picture

The game runs **two simultaneous world states** at all times.

- **Ground truth** — what is actually happening. The real army positions, the real trade routes, the real loyalties, the real health of every ruler.
- **The player's intelligence picture** — what the player believes is happening, built from their network's reports, which may be incomplete, outdated, or actively falsified.

## Silent divergence

These two states **diverge silently.** The player receives no warning that their picture is wrong.

When they issue an action based on false intelligence — sending influence toward a trade route that was abandoned two years ago, cultivating a general who was quietly executed last month, expecting a ruler to be receptive because their spy does not know he had a stroke — the action misfires.

**No correction. No explanation. The world simply does not respond the way the player expected.**

## The two states

| **State** | **Description** |
| --- | --- |
| **Ground truth** | The actual simulation state. Never directly visible to the player in Realistic mode. |
| **Intelligence picture** | What the player's network reports. Displayed on all map layers and dossiers. May contain errors at any layer. |
| **Divergence events** | Moments when the player's picture is provably wrong — an action fails, a promised ally doesn't show, a route doesn't exist. |
| **Calibration** | Cross-referencing multiple independent sources to identify corrupted data and bring the picture closer to truth. |

## Why this matters

- This is the system that makes [Intelligence Rechecks](../18-intelligence-rechecks.md) meaningful.
- It is also why [Save Architecture](../29-save-architecture.md) matters — Ironman mode preserves the teeth of this system.
- Automations in [Memoirs](../13-memoirs/README.md) run on the intelligence picture, not ground truth. Stale pictures produce stale automations that misfire.
