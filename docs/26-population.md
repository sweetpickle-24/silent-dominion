# 26. Population and Demographics

Every settlement and province in the game carries a **population figure.** Population is not simply a number — it is the foundation of everything else:

- Agricultural productivity requires labour.
- Armies require recruits.
- Trade requires consumers.
- Cities require residents.
- Ideas require minds to inhabit.

The population model is **what makes the world feel like it has weight** rather than being a collection of abstract values.

## 26.1 Population dynamics

| **Driver** | **Effect on population** | **Player lever** |
| --- | --- | --- |
| **Agricultural surplus** | Positive: excess food above subsistence allows population growth | Develop farmland, improve irrigation, protect trade routes that import grain |
| **Famine or scarcity** | Negative: shortage below subsistence causes mortality and out-migration | Disrupting grain supply as an economic weapon; protecting food security of allied regions |
| **Disease and plague** | Sharply negative: mass mortality in dense urban settlements | Cannot be directly prevented; can be anticipated through sanitation intelligence and used as a timing tool |
| **War and displacement** | Negative in affected regions; positive in receiving regions through refugee flow | Engineering wars in regions the player wants to weaken; maintaining peace where the player wants growth |
| **Trade prosperity** | Positive: trade income raises living standards and attracts migrants | Building and protecting trade routes; developing port and market infrastructure |
| **Stability and governance quality** | Positive: low unrest and fair governance allows long-term demographic investment | Maintaining the political stability of regions the player wants to develop |

## 26.2 Population and the world simulation

Population figures directly drive the simulation's outputs.

- A province with high population produces more agricultural yield, more military recruits, more tax revenue, and more social complexity (more potential hosts and more active factions).
- A province devastated by plague or war regresses toward simplicity — fewer named individuals, lower economic output, reduced strategic value.

**The player who manages to keep their core operating regions prosperous and well-populated has a structural advantage** in host availability and financial network capacity.

### Rules

- **City slot unlocking** is tied to population thresholds — a city cannot develop new districts without the people to fill them.
- **Character generation rate** scales with population — high-population regions produce more named individuals per generation.
- **Military levy capacity** scales directly with provincial population and stability.
- The [weight system](./08-map-and-provinces/weighted-generation.md) operates on the next generation of a population, not individuals — a population of 100,000 shifts its trait distribution meaningfully; a population of 1,000 does not.
