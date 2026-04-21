# 30. Memoirs Panel — Library Interface

The Memoirs system stores the player's accumulated pattern library. The Memoirs panel is the UI through which the player views, manages, and applies this library.

It appears on the table as a **leather-bound journal or codebook** whose visual presentation changes with the era — from wax tablets in the ancient world to printed ledgers in the early modern period.

## 30.1 Panel structure

| **Section** | **Contents** | **Player interaction** |
| --- | --- | --- |
| **Known profiles** | All character archetypes the player has fully worked through manually, with their trait profiles and approach recommendations | Browse, search by trait combination, apply to current target to check match quality |
| **Religion and ideology library** | All faiths and ideological movements the player has manually investigated, with their structural attributes and approach histories | Check if a current religion is in the library; see the approach that worked; flag as potentially stale for revalidation |
| **Rival fingerprints** | All identified rival society operational signatures, updated as new evidence accumulates | View the fingerprint; compare against current suspicious activity; flag a news event as potentially matching a known signature |
| **Active automations** | All currently running automated operations, their status, their last confirmed accuracy, and their next scheduled execution | Review, pause, cancel, or flag for manual revalidation; see which automations are running on unverified profiles |
| **Stale pattern alerts** | Patterns flagged by the system as potentially outdated based on elapsed time or detected condition changes | Review the alert, decide whether to revalidate manually or accept the risk of running a potentially stale automation |
| **System reference** | Summaries of all game systems the player has encountered, in the player's own words as recorded by the immortal over centuries | The living help system — consult without leaving the table |

## 30.2 Pattern match display

When the player selects a target for an operation, the Memoirs panel surfaces the **closest matching pattern** from the library alongside a **match quality indicator.**

- **High match quality** means the target's profile is very close to a known, verified pattern — the automation can be applied with confidence.
- **Low match quality** means the target is unusual or the closest pattern is from a culturally different context — the player is warned that the automation may misfire and should consider manual engagement.

### Thresholds

| **Match quality** | **Behaviour** |
| --- | --- |
| **Above 80%** | Automation available with standard confidence |
| **50–80%** | Automation available but flagged as approximate; risk is the player's |
| **Below 50%** | No reliable automation available; manual engagement recommended; player can still attempt automation but is explicitly warned |
| **No match found** | The target is outside the current library entirely; full manual engagement required; any successful operation adds a new pattern to the library |
