# 8.1 Full World Simulation

Silent Dominion simulates the **full world**, not a single region. Every major civilisation, kingdom, and power centre that has historically existed is present in the simulation. The player can operate anywhere.

Simulation fidelity **scales with player presence.** The world is detailed where the player has invested attention and abstracted where they have not. This makes the world feel vast without requiring an impossible amount of data.

When the player extends influence into an abstracted region it **populates**: individuals are generated, names assigned, personalities built from cultural templates.

## The fidelity model

| **Fidelity** | **Player state** | **What is modelled** |
| --- | --- | --- |
| **High fidelity** | Player is active here | Named individuals with personalities, real city names, specific events, detailed political relationships |
| **Medium fidelity** | Player has some network | Named rulers and major figures, rough political dynamics, events reported with a delay |
| **Low fidelity** | Player has no presence | Abstracted political blocs, cycle dynamics only, no named individuals. Shown on the map as it would appear on a period map — labelled but undetailed. |

## Implication for ruler AI

See [§9.6 Low-Fidelity Ruler AI](../09-autonomous-world/low-fidelity-ai.md). Low-fidelity regions still simulate rulers and decisions — just at lower granularity.
