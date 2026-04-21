# 7.8 Difficulty Modes

Difficulty in Silent Dominion is primarily about **how much the intelligence system lies to the player.**

| **Mode** | **Intelligence** | **What changes** |
| --- | --- | --- |
| **Casual** | Ground truth always shown | All map layers show accurate real-world data. Wrong intelligence from bad sources is flagged visually. The game becomes a pure strategy puzzle with full information. |
| **Advisors** | Picture with inconsistency flags | The intelligence picture is shown, but the game flags when a source has not been updated recently or when two sources contradict each other. Wrong data is not corrected — only flagged as uncertain. |
| **Realistic** | Intelligence picture only | The player sees only what their network reports. Ground truth is never revealed. Wrong data looks identical to correct data. The only way to detect errors is triangulation and watching for misfires. |

## Design intent

- **Realistic** is the intended full experience. Every other system is tuned against it.
- **Advisors** is for players who want to understand the game's systems without being punished by hidden-data mistakes yet.
- **Casual** is for players who want to engage with the strategy layer without the epistemic layer.

These modes interact with [Save Architecture](../29-save-architecture.md) — Realistic + Ironman is the deepest experience the game offers.
