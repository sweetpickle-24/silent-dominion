# 8.10 Map Intelligence Layers

The map begins **nearly empty.** At game start the player sees only country borders, labelled cities, and coastlines — drawn in the cartographic style of the era. Everything else is darkness.

As the player builds their network and gathers intelligence, layers of information unlock and overlay the map. **Each layer reflects what the player actually knows, not ground truth.**

## The three states of every layer

| **State** | **Appearance** |
| --- | --- |
| **Unknown** | The layer is not displayed. The player has no data. |
| **Known but wrong** | The layer is displayed with corrupted data — false routes, inflated figures, misidentified loyalties — sourced from unreliable or turned informants. The player cannot tell this from verified data without cross-referencing. |
| **Verified** | Accurate, cross-referenced from at least two independent sources. Displayed with full confidence markers. |

**Wrong data is the most dangerous state** because it is invisible. A merchant spy who has been turned feeds you a trade route that does not exist. You plan around it for a decade. The map shows it confidently. The only defence is **triangulation** — never trusting a layer that rests on a single source.

## Economic layers

| **Layer** | **Unlocked by** | **What wrong data looks like** |
| --- | --- | --- |
| **Trade routes** | Merchant or spy host in a trading city | Routes shown through wrong cities; commodities mislabelled; revenue figures inflated or deflated by a corrupt informant |
| **Wealth distribution** | Merchant host with tax access or banker host | Rich regions shown as poor (hidden wealth); poor regions shown prosperous (official figures vs. reality) |
| **Debt and leverage** | Banker or court advisor host | A ruler shown as solvent when deeply in debt; dependency relationships inverted or missing entirely |
| **Famine and scarcity** | Local merchant, priest, or civic host | Crop failure underreported by officials trying to prevent panic; famine shown a season late |

## Political layers

| **Layer** | **Unlocked by** | **What wrong data looks like** |
| --- | --- | --- |
| **Loyalty map** | Advisor, spy, or general host within a court | A general shown as loyal who has already been flipped by a rival society; a wavering noble shown as committed |
| **Succession tension** | Court insider or ruler host | A healthy succession shown as disputed; a genuine crisis hidden because all informants are loyalists |
| **Factional control** | Multiple court-level hosts needed for accuracy | The merchant faction shown as dominant when the military has already seized informal control |
| **Diplomatic relations** | Ambassador, merchant, or high-court host | Secret alliances invisible; public alliances shown as genuine when they are performative |

## Military layers

| **Layer** | **Unlocked by** | **What wrong data looks like** |
| --- | --- | --- |
| **Army positions** | Spy or general host near the force | Positions one to three months out of date; army shown in winter quarters when already on the march |
| **Army strength** | Spy embedded in military supply or command | Deliberately inflated numbers fed by an enemy to deter you; genuine strength hidden by a paranoid commander |
| **Fortification quality** | Engineering spy or local civic host | Old walls shown as repaired; new construction invisible; garrison sizes wrong by a factor of two |
| **Campaign readiness** | Supply chain spy or military advisor host | An army shown as ready that is underpaid and near mutiny; a depleted force shown as undeployable when it has recovered |

## Social layers

| **Layer** | **Unlocked by** | **What wrong data looks like** |
| --- | --- | --- |
| **Religiousness** | Priest, philosopher, or civic host | Official piety overstated; genuine spiritual searching invisible to a host embedded in the institution |
| **Literacy and education** | Scholar or merchant host in urban centres | Rural literacy wildly underestimated; court literacy overstated; idea propagation speed miscalculated |
| **Ethnic and linguistic tension** | Long-term civic or merchant host in mixed regions | Suppressed tension invisible until it erupts; manufactured tension (by a rival society) shown as organic |
| **Popular unrest** | Civilian host — merchant, priest, or minor official | Grievance levels systematically underreported by officials; unrest shown as stable until the day before it breaks |

## Secret layers

These layers are **never fully reliable** regardless of source quality.

| **Layer** | **Unlocked by** | **Notes** |
| --- | --- | --- |
| **Rival society footprints** | Long observation of anomalous events + pattern recognition | Shown as faint traces, never precise markers. Rival societies actively obscure this layer and feed false footprints. |
| **Your own historical footprint** | Always visible — only to you | Shows where you have acted before, how much legend has accumulated, where you are still remembered or feared. Your personal risk map. |
| **Corruption networks** | Very high-trust insider host over many years | The gap between who holds the title and who holds the actual power. Almost never accurate from a single source. |
| **Ideological undercurrents** | Philosopher or dissident host in intellectual centres | Ideas moving through the population before they have a name or a leader. The earliest warning system for coming upheaval. |
