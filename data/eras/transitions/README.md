# Era transition data — placeholder discipline

These four `.tres` files define the era boundaries for the 500 BCE–1900s arc. **All trigger
conditions are PLACEHOLDER date-based rules** (`world.year >= N`).

Per `design/systems/progression-and-time.md`, the design intent is **condition-based** triggers:
eras should shift when the underlying dynamics of the world change (imperial overextension,
ideological vacuum, mass migration, etc.), not on a calendar date.

These placeholders exist to make the architecture testable at Step 10. Replacing them with
condition-based rules is content authoring work that unlocks when world simulation mechanics
(Kingdom, Population, ReligionIdeology, AutonomousWorld) produce queryable state.

| File | From → To | Placeholder year | Approx real-world date |
|---|---|---|---|
| ancient_to_classical_collapse.tres | ancient → classical_collapse | year >= 700 | ~200 CE |
| classical_collapse_to_medieval.tres | classical_collapse → medieval | year >= 1100 | ~600 CE |
| medieval_to_early_modern.tres | medieval → early_modern | year >= 1800 | ~1300 CE |
| early_modern_to_modern.tres | early_modern → modern | year >= 2200 | ~1700 CE |
