# 33.1 What the Simulation Runs Internally

The simulation runs the following processes for every kingdom on every game-day. The player sees only the **downstream conditions** these produce.

## Processes

- **Tax collection** — the kingdom attempts to collect silver from each province. Collection efficiency varies by province loyalty, administrative capacity, distance from the capital, and presence of corrupt officials. The result feeds the treasury condition. The player does not see the collection mechanics — they see the treasury condition and its trend.
- **Army maintenance** — the kingdom pays its armies from the treasury, feeds them from food reserves, and replaces equipment losses from iron and material stocks. If any input fails, morale, supply state, or army size degrades. The player sees morale and supply state on the military intelligence layer.
- **Food distribution** — grain and food stocks are distributed from production provinces to population centres. Surplus is stored, deficit causes hardship. The player sees the famine and scarcity layer if their coverage is sufficient.
- **Diplomatic processing** — the kingdom evaluates its current relationships and takes autonomous diplomatic actions — sending envoys, making offers, issuing warnings. These produce relationship score changes and occasionally public events. The player sees the outcomes through diplomatic intelligence.
- **Factional management** — internal factions — military, clergy, merchants, nobility — compete for the ruler's attention and policy direction. The dominant faction shapes the kingdom's priorities. The player sees factional control through the political intelligence layer.
