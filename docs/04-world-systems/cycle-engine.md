# 4.2 The Cycle Engine

The cycle engine is the game's simulation core. It tracks not historical events but **historical dynamics** — the forces that have always shaped civilisation. Regardless of which cultures are on the map, the engine continuously evaluates these dynamics:

| **Dynamic** | **Trigger condition** | **Historical analogue** |
| --- | --- | --- |
| **Republic to empire** | Military dominance + weak civilian oversight | Rome, Napoleon, Caesar |
| **Empire fragmentation** | Overextension + succession weakness + linguistic diversity | Mongol Empire, Alexander's successors |
| **Spiritual vacuum** | Institutional collapse + population trauma + no dominant faith | Rise of Christianity, Islam, Buddhism |
| **Merchant ascendancy** | Trade wealth exceeds land wealth + weak nobility | Italian city-states, Dutch Republic |
| **Reform and counter-reform** | Institutional corruption + literate dissenter class | Reformation, French Revolution |
| **Technological leap** | Accumulated knowledge + material surplus + competitive pressure | Industrial Revolution analogues |

## How it drives the simulation

- Every province, kingdom, and institution has state that feeds these dynamics.
- The engine runs every game-day, evaluating whether any dynamic's trigger threshold has been reached.
- When a threshold is crossed, an event fires that begins the corresponding transition.
- Historical gravity (Layer 1) biases *which* specific form the transition takes if the player has not intervened. Otherwise the cycle engine alone produces the outcome.

## Player interaction

- The player cannot stop a cycle, but they can accelerate, delay, or redirect one.
- Recognising which cycle is about to fire is a core skill encoded in the [Memoirs system](../13-memoirs/README.md).
- Cycles are also the simulation layer that [rival societies](../05-societies/README.md) manipulate — their agendas are typically expressed as pushing or resisting specific cycles.
