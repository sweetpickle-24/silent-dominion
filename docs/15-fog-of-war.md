# 15. Fog of War — Epistemic Visibility

The fog in Silent Dominion is **not geographic — it is epistemic.** The question is never just 'have you been there' but 'what do you actually know, how current is it, and how much do you trust the source'.

- A city you had a spy in three years ago is not revealed — it is aging data at declining confidence.
- A city you have a spy in right now may be showing you a lie.

**The map reflects not the world but the player's knowledge of it.**

## 15.1 The visibility score

Every location in the world carries a **visibility score from 0 to 100.** This score is not binary, it decays continuously over time, and it is built from stacked inputs that each contribute differently.

The map's visual state is a direct rendering of this score — there is no hard line between revealed and unrevealed, only a spectrum from darkness to clarity.

| **Score range** | **Map appearance** | **Data available** | **What this means** |
| --- | --- | --- | --- |
| **0–20** | Blank or name only, period-speculative cartography | Nothing current. May show historical data that is decades old. | No coverage. The player is operating blind in this location. |
| **20–50** | Borders, city markers, ruler names. Static. | Political structure only. No dynamic data. | The location is known but not watched. Data reflects last time coverage existed. |
| **50–75** | Active intelligence layers visible but faded in colour. | Dynamic data present but aging. Confidence indicators show degradation. | Coverage exists but is thinning. Reports are arriving but less frequently. |
| **75–100** | Full sharp layers, current confidence colouring. | All unlocked layers current and cross-referenced. | Strong coverage. Multiple sources active. High confidence in displayed data. |

## 15.2 Visibility inputs and decay rates

Different types of intelligence decay at different speeds. **Geographic facts** are slow to change and slow to decay. **Military facts** are fast to change and fast to decay. The player's coverage assignments must account for the decay rate of the information they need.

| **Intelligence type** | **Decay rate** | **Primary source** | **Consequence of staleness** |
| --- | --- | --- | --- |
| **Geographic / borders** | Very slow — years | Any operative presence | Rarely critical unless in a period of active territorial change |
| **Political structure** | Slow — months to a year | Court-level hosts or coordinators | Wrong faction shown as dominant; deposed ruler shown as reigning |
| **Loyalty and sentiment** | Medium — weeks to months | Multiple insider sources | Loyal general shown as reliable; wavering noble shown as committed |
| **Economic activity** | Medium — months | Merchant or trade operatives | Dead route shown as active; new route invisible; revenue figures wrong |
| **Military positions** | Fast — days to weeks | Spy or general host near the force | Army shown in winter quarters when already on the march |
| **Court mood and decisions** | Very fast — days | Host embedded in the court | A decision made yesterday invisible; a reversal undetected |

## 15.3 The three fog states

- **Geographic fog** — the location is not covered. The map shows nothing or period-speculative guesses. Lifted by sending any operative to the area.
- **Intelligence fog** — the location is covered but data is incomplete, old, or from a single unverified source. Lifted by increasing source density and freshness.
- **Confidence fog** — the location has current data but source reliability is uncertain. Only lifted through triangulation from independent sources. Sometimes never fully resolved.

## 15.4 Coverage assignments

The player manages fog at scale through **coverage assignments** — standing orders issued to the coordinator layer that maintain minimum visibility thresholds in specified areas.

> A coverage assignment is a persistent instruction: 'keep the Levantine coast above 60% visibility'.

The organisation allocates operatives, rotates sources, and refreshes reports automatically to maintain the threshold.

- Coverage assignments **consume organisation bandwidth** — too many assignments in too many regions degrades quality everywhere.
- When coverage drops below threshold (operative lost, coordinator burned), the player receives a notification and the affected area begins visually fading.
- **Priority assignments** concentrate resources — the player can mark a region as critical, which pulls coverage from lower-priority areas.
- In **Realistic mode**, coverage degradation happens silently until the player notices the map fading or an action misfires on stale data.
