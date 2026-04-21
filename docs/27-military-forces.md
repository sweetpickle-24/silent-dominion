# 27. Military Forces — Armies as Simulation Objects

**The player never commands armies.** But armies are real objects in the simulation with internal state the player can observe, influence, and be affected by.

Understanding how armies work as simulation objects is essential to knowing which levers actually matter for military outcomes.

## 27.1 Army attributes

| **Attribute** | **What it represents** | **How the player can affect it** |
| --- | --- | --- |
| **Size** | Number of soldiers, including cavalry, infantry, and support | Manipulating recruitment funding through financial network; disrupting or enabling provincial levies |
| **Quality** | Equipment, training, veteran experience | Long-horizon investment in a specific general's reputation attracts better soldiers; can be degraded by disrupting supply of weapons from resource provinces |
| **Morale** | Willingness to fight; composite of pay, recent outcomes, cause legitimacy, and general's leadership | Seeding rumours that undermine the cause; disrupting pay through financial manipulation; amplifying or deflating the significance of recent outcomes |
| **Supply state** | Whether the army can sustain operations given its current position and supply line integrity | Collapsing a supply route through economic or political manipulation; protecting supply routes for allied armies |
| **Command quality** | The general's trait-weighted tactical and leadership performance | Direct host cultivation of the general; planting paranoia or overconfidence; bribing or cultivating key subordinate officers |
| **Loyalty direction** | Who the army ultimately fights for — the state, the general personally, or a faction | Separating army loyalty from ruler loyalty is a core destabilisation tool; a general whose army is loyal to him personally is a potential coup instrument |

## 27.2 Recruitment and composition

Armies are recruited from the province's population and levy system.

- A plains province with high population and a standing martial tradition produces more and better infantry.
- A steppe province produces cavalry.
- A coastal city produces naval forces.

The composition of an army **reflects the geography and culture it was raised from**, which is itself a function of the historical conditions the player may have shaped.

### Rules

- A province that has been under **continuous warfare for two generations** produces a militarised population weighted toward military traits — soldiers of higher quality, generals of greater ambition.
- A province that has been **prosperous and peaceful for a century** produces poor soldiers but excellent administrators and merchants — and is difficult to defend when threatened.
- **Religious composition** of the army matters — a highly devout army fighting a campaign against a culturally similar enemy may have morale complications the player can exploit.

## 27.3 Movement and logistics

Armies move between provinces at speeds determined by:

- Terrain.
- Season.
- Road infrastructure.
- Supply state.

Movement is visible on the map to any operative with coverage of the relevant provinces. A well-supplied army on Roman roads moves fast. An army crossing mountains in winter without prepared supply depots attrits rapidly regardless of its size or quality.

### Rules

- **Road infrastructure** directly affects army movement speed — a strategic reason to invest in or sabotage road construction.
- **Mountain and forest** provinces impose movement penalties; **desert** provinces impose attrition on supply.
- **Siege operations** are the slowest military action — taking a well-fortified city can take months or years, during which the besieging army is vulnerable to supply disruption.
- **Naval movement** is faster than land movement for coastal operations but entirely dependent on weather and season in the ancient and medieval eras.

## Cross-reference

See [§9.1 Battle Resolution](./09-autonomous-world/battle-resolution.md) for how battles are resolved.
