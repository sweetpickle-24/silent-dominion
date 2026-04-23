# Silent Dominion — Gameplay Reference

> This document describes what the code in this repository actually does.
> It was assembled by reading the scripts under `scripts/`, the data files
> under `data/`, the scenes under `scenes/`, and `project.godot`. Nothing
> from the `docs/` folder was used. If a claim isn't anchored to code,
> it isn't here.

---

## 1. What the game is, mechanically

Silent Dominion is a single-player, pause-and-plan game built in **Godot 4.6**
(`project.godot` → `config/features=PackedStringArray("4.6", "Forward Plus")`),
written entirely in **GDScript**. The player is an immortal sitting at a desk
in 500 BCE Athens, routing actions through a shadow organisation and reading
the world through letters. There is no direct avatar. There are no battles
fought by the player. The game is a paperwork loop:

1. Open inbox, read letters.
2. Compose an action through the Compose panel.
3. The action is scheduled as a future task (`scripts/scheduler.gd`).
4. Days/weeks later the Scheduler fires, the outcome is rolled, a report
   letter is produced and dropped back into the inbox.
5. Repeat.

The loop is documented at the top of `scripts/action_runner.gd`:

> `1. issue(action_id, target_id) -> builds a PendingAction descriptor,`
> `   schedules resolution via Scheduler ... emits EventBus.action_issued.`
> `2. Scheduler.task_due -> assembles an intelligence report Letter,`
> `   hands it to the Inbox via EventBus.letter_delivered.`

Time is controlled by the player: `Space` pauses, `1` runs day-by-day, `2`
runs month-by-month (`scripts/game_clock.gd` → `enum Speed { PAUSED, DAY, MONTH }`,
`SPEED_DAYS_PER_SECOND = { PAUSED: 0.0, DAY: 1.0, MONTH: 30.0 }`).

---

## 2. Starting state

From `data/actors_500bce.json`, `scripts/base_manager.gd`,
`scripts/org_registry.gd`, `scripts/codebook.gd`, `scripts/identity_registry.gd`,
and `scripts/finance_manager.gd`:

- **Date**: 1 January, 500 BCE. `GameClock` initialises with
  `year = -500, month = 1, day = 1`.
- **Base**: province `attica`, kingdom `athens` (`base_manager.gd`
  `DEFAULT_PROVINCE_ID = "attica"`).
- **One host**: `starter_host_athens` — *Pheidon of the Piraeus moorings*,
  a merchant. Seeded above the host-relationship threshold.
- **One coordinator**: `starter_coordinator_athens` — *Theron, the scribe at
  the Kerameikos*. Promoted to `OrgMember.Layer.COORDINATOR` by
  `OrgRegistry._seed_starter_cell()`.
- **One banking house**: auto-seeded by `Finance` at campaign start, narratively
  property of the starter coordinator.
- **One cipher**: `cipher_starter_coord` (display name "Athenian-Chalkidic
  rotation") shared with the starter coordinator
  (`codebook.gd` → `_seed_starter_cipher`).
- **One cover identity**: `ident_starter_trader` — *Demetrios of Miletos*,
  "itinerant grain-and-oil trader", anchored in Athens
  (`identity_registry.gd` → `_seed_starter_identity`).
- **`PlayerPicture` visibility**: Athens is warm on day one (seeded in
  `player_picture.gd`). Every other kingdom is cold until the player puts
  eyes on it.

The world itself contains **19 kingdoms and 91 provinces** at 500 BCE
(`data/world_500bce.json`): Athens, Sparta, Corinth, Macedon, Persia, Egypt,
Carthage, Rome, Etruscan League, Thebes, Syracuse, Massalia, Odrysia,
Molossia, Colchis, Nabatea, Kush, Cyrene, Tartessos.

---

## 3. The table (main UI)

Scene: `scenes/table/table.tscn`, script: `scenes/table/table.gd`.

It is a flat top-down desk. Every "object" on the desk opens a full-screen
overlay panel. Hotkeys (from `table.gd::_hotkey_sheet_text`):

| Key | Opens                                                 |
|-----|-------------------------------------------------------|
| `Space` | pause / resume                                    |
| `1` | day-by-day speed                                      |
| `2` | month-by-month speed                                  |
| `I` | Inbox                                                 |
| `R` | Memoirs (letter archive + system reference)           |
| `N` | Public News                                           |
| `M` | Map                                                   |
| `L` | Ledger                                                |
| `D` | Dossiers                                              |
| `O` | Organisation (Roster)                                 |
| `V` | Vault (banking network)                               |
| `C` | Compose a letter                                      |
| `B` | Codebook                                              |
| `F` | Fingerprint Library (rivals)                          |
| `Esc` | close top overlay                                   |
| `F5` / `F9` | quicksave / quickload                         |
| `F10` | Archive of saved seasons (slot browser)             |
| `Ctrl+,` | Preferences                                      |
| `Ctrl+Shift+K` | write chronicle markdown to disk           |
| `F12` / `Shift+F12` | fast-forward 100 / 500 years (dev)    |
| `Ctrl+Shift+F12` | save/reload round-trip harness (dev)     |
| `Shift+?` | show this hotkey sheet                          |

### 3.1 Unlock gating

`scripts/unlocks.gd` plus `table.gd::_LOCKED_COPY` gate four surfaces behind
simulation milestones. Locked surfaces dim and show a "Not yet" overlay when
clicked. Codebook and Roster are not locked at start (they have legitimate
day-one content).

Objects hover-scale on mouse-over (`OBJECT_HOVER_SCALE` tween) and animate in
via `scenes/title/title.gd` → `table.gd` handoff.

---

## 4. The autoload graph

Everything simulation-side runs as a Godot autoload. The full list from
`project.godot [autoload]` (in load order):

```
EventBus, GameClock, Scheduler, WorldData, Actors, Org, OrgRoles, Codebook,
Inbox, Actions, Exposure, KingdomEconomy, Relations, InstRelations, Purse,
Finance, Picture, Fidelity, Rivals, Fingerprints, Shadow, Immortals,
PublicNews, Digest, HostFlavor, Unrest, Population, PopWeights, Armies,
Battles, Infrastructure, Characters, Religions, Entities, Mandates,
Languages, Dynasties, Failures, Eras, Base, Memoirs, Automations,
AmbitionDrift, RandomEvents, Whispers, Notifications, Session, WorldAI,
Beats, SaveManager, Chronicle, Prefs, TimeCtl, MapData, Unlocks, EraTheme,
AudioDirector, WorldProfile, Identities
```

Cross-system communication is through `EventBus` signals (declared in
`scripts/event_bus.gd`) — `world_loaded`, `action_issued`, `action_resolved`,
`letter_delivered`, `public_event`, etc. Systems never hold direct refs to
each other.

---

## 5. Time

`scripts/game_clock.gd`:

- **30-day months, 12-month years, 360 days a year.** No leap days.
- Years stored as a signed int: `-500` = 500 BCE, `-499` = 499 BCE, etc.
  Arithmetic is natural — ticking advances toward zero and then positive.
- `absolute_day()` returns a monotonic day index; `Scheduler` keys all
  deferred tasks by that.
- Three signals: `day_passed(y,m,d)`, `month_passed(y,m)`, `year_passed(y)`.
  Almost every subsystem subscribes to one of them.

`scripts/time_controller.gd` (autoload `TimeCtl`) handles:
- **Auto-pause on high-priority letters** (§10.4 style; `Prefs.auto_pause_on_priority`).
- **Continuous autosave** to a rotating A/B pair of slots, every
  `Prefs.autosave_interval_days` (default 30 days = one game-month).

`scripts/era_manager.gd` (autoload `Eras`) tracks which of the five eras from
`data/eras.json` is active. The windows, from that file:

| id                       | years           |
|--------------------------|-----------------|
| `ancient_world`          | -800 to 200     |
| `classical_collapse`     | 200 to 600      |
| `medieval_consolidation` | 600 onward      |
| `early_modern_fracture`  | (next)          |
| `modern_era`             | (final)         |

Each era carries `communication_multiplier` and `visibility_decay_multiplier`
which Scheduler/Actions and Picture read to scale dispatch delay and
intel decay. Eras also swap the table's visual tokens via `EraTheme`.

---

## 6. Actors

`scripts/actor.gd` defines the universal person data model. Anyone in the
world — historical figure, procedural NPC, or member of the player's own
organisation — is an `Actor`.

### 6.1 Roles
`enum Role { RULER, HEIR, GENERAL, PRIEST, MERCHANT, ADVISOR, PHILOSOPHER, AGENT, COMMONER }`.

### 6.2 Canonical 10 traits (0–100)
`ambition, paranoia, loyalty, piety, intellect, greed, ruthlessness, curiosity,
resilience, charisma`. The player never sees raw numbers — `scripts/trait_cues.gd`
converts them into short in-world phrases, and only surfaces traits that are
below 30 or above 70.

### 6.3 Other Actor fields
- `relationship: -100..+100` — personal warmth toward the player.
- `languages` dict (language_id → fluency 0..3).
- `family_id`, `parent_id`, `children` — lightweight dynasty ties.
- `birth_year`, `death_year` (BCE negative).
- `province_id`, `kingdom_id`.

### 6.4 Registry
`scripts/actor_registry.gd` (autoload `Actors`) loads
`data/actors_500bce.json`, spawns new actors on demand, tracks hosts
(`Actors.hosts()` returns actors whose relationship ≥ threshold and are
not `AGENT` role), and handles deaths / aging.

---

## 7. The organisation

`scripts/org_member.gd` defines a single data shape for the player's network.

### 7.1 Layers
`enum Layer { LIEUTENANT, COORDINATOR, OPERATIVE }`. Per-layer *behaviour*
lives in sibling modules under `scripts/org/`:
`coordinator_ops.gd`, `lieutenant_ops.gd`, `operative_ops.gd`. `OrgMember`
itself is pure data + serialisation.

### 7.2 Specialisations (lieutenants only)
`enum Specialisation { NONE, FINANCIAL, INTELLIGENCE, IDEOLOGICAL, SECURITY, POLITICAL }`.
When a lieutenant comes from a dynasty whose background matches their
specialisation, they get a natural-authority bonus.

### 7.3 Per-member state
- `trust` 0..100 — player's operational confidence in them.
- `skill` 0..100 — success bonus on dispatched actions; drifts up with good runs.
- `heat` 0..100 — *their* exposure; burns them (cell dissolved) rather than
  the player.
- `source_actor_id` — back-pointer to their `Actor` row. Empty for
  operatives that a coordinator cooked up on their own.

### 7.4 Registry
`scripts/org_registry.gd` (autoload `Org`) owns the members dictionary,
dispatch routing, promotions, audits, and the starter-cell seed.

### 7.5 Role resolver
`scripts/org_roles.gd` (autoload `OrgRoles`) maps narrator role tokens
(`factotum`, `archivist`, `paymaster`, `go_between`, `watcher`, `secretary`,
`tutor`, `chief_of_mandates`, `counter_intel`, `coordinator`, `predecessor`,
`correspondent_harbour`, `man_of_affairs`, `broker`, `handler`) to the
best-matching live OrgMember/Actor. `OrgRoles.sender_line(role, region)`
always returns a non-empty sender string; if nobody fits, it returns a
neutral atmospheric fallback that never uses the word "Your".

---

## 8. Actions

### 8.1 Definitions
`scripts/action_definition.gd` is the static template. Loaded from
`data/actions.json` at boot.

- `enum Tier { DEEP_SHADOW, ACTIVE, HIGH }` — §3.4 exposure tier.
- `enum TargetKind { NONE, ACTOR, KINGDOM, PROVINCE, ORG_MEMBER, ENTITY }`.
- Fields: `silver_cost`, `exposure_cost`, `min_days_to_resolve`,
  `max_days_to_resolve`, `base_success_chance`, `report_sender` (role token),
  `blurb`.

### 8.2 Current palette
**35 actions** in `data/actions.json`. Grouped by what they do:

- **Intelligence / low-tier**: `observe`, `cultivate`, `plant_idea`,
  `seed_rumour`.
- **Influence**: `quiet_plot`, `fan_border`, `host_sway_court`,
  `host_agitate`.
- **Bribery (5-outcome path)**: `bribe_direct`, `bribe_retainer`,
  `bribe_career`, `bribe_info`, `bribe_gift`.
- **Organisation building**: `promote_coordinator`, `promote_lieutenant`,
  `audit_cell`, `rotate_roles`, `run_double_agent`.
- **Intel analysis**: `intel_cross_reference`, `intel_source_audit`,
  `intel_reinvestigate`.
- **Rival ops**: `investigate_anomaly`, `cross_reference_pattern`,
  `match_fingerprint`, `sweep_for_rivals`, `neutralize_rival_operative`,
  `turn_rival_operative`.
- **Legend management**: `quiet_the_legend`, `discredit_hunter`,
  `destroy_archive`, `false_flag_operation`.
- **Immortal diplomacy**: `request_contact`, `propose_truce`,
  `attempt_kill_immortal`.
- **Entities**: `audit_entity`.

### 8.3 Runner
`scripts/action_runner.gd` (autoload `Actions`):

- `issue(action_id, target_id, auto)` → stacks a `PendingAction` descriptor
  and schedules its resolution as a Scheduler task of kind
  `"action_resolution"`.
- Adds **dispatch-chain handoffs** (§14.2 style) — an action flows
  operative ← coordinator ← host before resolution. Each hop is a 1–3 day
  beat; if the relevant member is dead or burned the action dies with a
  distinct letter (`TASK_KIND_HANDOFF_COORD`, `TASK_KIND_HANDOFF_OPERATIVE`).
- **Bribery** takes the five-outcome path
  (`enum BribeOutcome { CLEAN_SUCCESS, MESSY_SUCCESS, SILENT_FAILURE,
  LOUD_FAILURE, COUNTER_LEVERAGED }`).
- On resolution, assembles an **intelligence report Letter**, runs it through
  the two-reality biasing, and emits `EventBus.letter_delivered`.

### 8.4 Retainers
Bribes of kind `bribe_retainer` register a recurring retainer in `Finance`.
`Finance.retainer_turned` / `retainer_at_risk` feed back into the action
system to generate turned-agent letters when a target gets cold feet.

---

## 9. Exposure and the legend

### 9.1 Exposure (`scripts/exposure_manager.gd`, autoload `Exposure`)

A single 0–100 global meter. Every action adds its `exposure_cost`; the meter
decays `DECAY_PER_DAY = 0.25` each game-day (~7.5 / month).

Five levels (`enum Level`), thresholds `[21, 46, 66, 86]`:

| Level | Band            | Behaviour                             |
|-------|-----------------|---------------------------------------|
| 0     | Deep shadow     | full palette available                |
| 1     | Whispered       | full palette, tier-3 starts to feel risky |
| 2     | Known quantity  | tier-3 actions blocked                |
| 3     | Hunted          | tier-2 also blocked                   |
| 4     | Exposed         | almost everything blocked             |

The player never reads the raw number. The `ExposureIndicator` widget on the
table only shows the qualitative level name.

### 9.2 Shadow / legend (`scripts/shadow_figure.gd`, autoload `Shadow`)

- Global `legend` 0–100, accumulated from exposure and loud public actions.
  Drives an era-appropriate epithet.
- Per-kingdom `awareness_heat` tiered into
  `NONE / CULTURAL / INSTITUTIONAL / PERSONAL` at thresholds `[0, 25, 55, 85]`.
  Awareness tiers apply exposure tail multipliers and spawn hunters.
- **Hunters**: actors generated from high-paranoia, high-intellect populations
  in high-awareness kingdoms. They produce a monthly exposure trickle and
  are a named opponent for `discredit_hunter`.

### 9.3 Whispers (`scripts/whispers.gd`)

When `seed_rumour`, `plant_idea`, or `host_agitate` succeed, a whisper is
registered. Strengths `LOUD → CARRIED → FADING → DEAD` decay one band per
month. While alive, a small monthly roll emits follow-up public dispatches;
`agitate` whispers also nudge province unrest.

---

## 10. The two-reality system

Ground truth lives in `Actors`, `WorldData`, `Rivals`, etc. What the player
*sees* routes through `scripts/player_picture.gd` (autoload `Picture`).

### 10.1 Per-kingdom visibility (0–100)

Constants from `player_picture.gd`:

- `MONTHLY_DECAY = 6` (no coverage) / `3` (operative) / `0` (coordinator).
- `OBSERVE_REFRESH = 25`, `CULTIVATE_REFRESH = 15`, `BRIBE_REFRESH = 10`.
- `STALE_THRESHOLD = 50`, `COLD_THRESHOLD = 20`, `COORDINATOR_FLOOR = 70`.

A kingdom below `COLD_THRESHOLD` is "cold" — its map tile shows no detail,
its actors vanish from the Dossier and from Compose target pickers.

### 10.2 Actor snapshots

When intel refreshes a region, `Picture` caches an actor snapshot with a
"last seen" stamp. Dossiers on stale regions render from the snapshot and
label themselves accordingly. Dead actors still appear if the player holds
a snapshot (your memory of them doesn't die).

### 10.3 Gating APIs

- `Picture.knows_actor(actor_id) -> bool`
- `Picture.known_actors() -> Array[Actor]`

`scripts/dossier_view.gd` and `scripts/compose_view.gd` filter through these
so the UI can never display an actor the player has no picture of.

### 10.4 Fidelity
`scripts/fidelity_manager.gd` (autoload `Fidelity`) suppresses *flavour*
public events for cold kingdoms. Structural events (wars, ruler deaths,
treasury collapses) still fire. When a kingdom crosses cold → warm, Fidelity
emits one catch-up dispatch summarising the structural history of the last
24 months.

### 10.5 Divergence
`action_runner.gd` bakes divergence into intelligence reports: stale sources
produce biased numbers. `intel_cross_reference` and `intel_reinvestigate`
compare the `Picture` snapshot with ground truth and raise a divergence
letter when they disagree.

---

## 11. Correspondence

### 11.1 Letters (`scripts/letter.gd`)

Fields: `id`, `sender`, `date` (`GameDate`), `subject`, `body` (multiline),
`is_read`, `kind` (one of `intel | action | host | digest | news | intro | misc`),
`cipher_id`.

A letter with a `cipher_id` the player hasn't opened reports as illegible —
`Letter.is_illegible()` checks `Codebook.knows_cipher(cipher_id)`. The
Letter view renders sender as "Unknown hand" and body as a generic
"Sealed under an unknown cipher" placeholder until the cipher is known.

### 11.2 Inbox (`scripts/inbox_manager.gd`, autoload `Inbox`)

- Holds every letter delivered.
- Indexed by actor for fast lookup.
- `EventBus.letter_delivered` is the sole ingestion path.
- On boot, drops one starter letter from the starter coordinator.
- When `Unlocks.surface_unlocked` fires for `Memoirs / Vault / Library / Roster`,
  Inbox emits a one-shot welcome letter from the factotum naming the object
  and its hotkey (see `_UNLOCK_COPY`).

### 11.3 Codebook (`scripts/codebook.gd`, autoload `Codebook`)

Not a glossary. It is the player's active-ciphers desk.

- `ciphers`: `cipher_id → { display, opened_day, contact_actor_id }`.
- `contact_cipher`: `actor_id → cipher_id`.
- `knows_cipher(cipher_id) -> bool`.
- One starter cipher seeded at campaign start
  (`cipher_starter_coord`, shared with the starter coordinator).

The Codebook UI (`scripts/codebook_view.gd`) shows three sections:
*Ciphered Contacts*, *Compose new ciphered message*, *Decrypt Inbox*.

### 11.4 Compose (`scripts/compose_view.gd`)

- Pick an action from the palette.
- Target picker is gated by `Picture.known_actors()` / known kingdoms.
- Success chance, delay, exposure cost are displayed as qualitative
  phrases only (see `_legend_band`, `_time_phrase`, `_cost_phrase`,
  `_exposure_phrase`).
- An automation hint from `Memoirs.match_for(...)` appears when a similar
  pattern has been run successfully before.

### 11.5 Public news (`scripts/public_news.gd`, autoload `PublicNews`)

Ring buffer of public events with three delivery channels (§34.4):

- `operative` — player's network, same-day to three days later.
- `neutral`   — merchants, travellers. Fortnight to ~2 months by distance.
- `official`  — crown announcements. Slowest but most formally phrased.

`PublicNews.news_added` feeds the `PublicNewsView` scroll and bumps the
`Notifications` badge on the scroll.

### 11.6 Host flavour (`scripts/host_flavor.gd`)

50% chance each month, if the player has at least one host, one host sends
a non-actionable flavour letter about their city. Pure texture.

### 11.7 Monthly digest (`scripts/monthly_digest.gd`, autoload `Digest`)

The "factotum" summarises the last month — active wars, treasury shifts,
unrest changes, outstanding mandates. Sender is always routed through
`OrgRoles.sender_line(OrgRoles.FACTOTUM)`.

---

## 12. Finance

`scripts/finance_manager.gd` (autoload `Finance`).

> *"The player has no gold balance. They have access — banking houses,
> merchant consortiums, temple treasuries that can produce silver in
> specific cities when asked. Every act of funding routes through those
> relationships; there is no single number that drains."*

### 12.1 Banking house (`scripts/banking_house.gd`)

Each house carries:

- `capacity` (spendable, regens monthly).
- `discretion` (how well it hides source/destination).
- `reach` (which kingdoms it can move money to/from).
- `home_kingdom`, `house_kind` flavour.
- Maturity — pushed too hard they grow curious (intel risk);
  ignored too long they atrophy.

### 12.2 Routing options
`enum RoutingOption { DIRECT, SINGLE_INTERMEDIARY, MULTI_HOP, EMBEDDED_TRADE }`.
`DIRECT` is cheap and fast but loud. `EMBEDDED_TRADE` is expensive and slow but
the quietest — and requires a merchant host. The routing algorithm picks the
cheapest viable path that satisfies discretion + reach + capacity.

### 12.3 Side-state
- `iou_added` / `iou_settled` signals for deferred debts.
- `retainer_registered` / `retainer_at_risk` / `retainer_turned` for
  long-running agent stipends (bribe_retainer output).
- `settlement_started` / `settlement_completed` for multi-hop clearances.

### 12.4 Player purse (`scripts/player_purse.gd`, autoload `Purse`)

A trunk under a floorboard. Small last-resort silver reserve, used when
the network can't move the money. Displayed as a qualitative band via
`Purse.band_entries()`; never as a raw number.

### 12.5 Ledger (`scripts/ledger_view.gd`)

Full-screen overlay showing treasury conditions per known kingdom, plus the
history of player financial events. Conditions are qualitative bands, not
silver figures.

---

## 13. Kingdom economy and politics

### 13.1 Treasury (`scripts/kingdom_economy.gd`, autoload `KingdomEconomy`)

Monthly tick. For every kingdom:

1. Sum owned-provinces' `production × tax_efficiency`.
2. Subtract `BASE_MONTHLY_COST = 3.0` + `PER_PROVINCE_UPKEEP = 0.6 * provinces`.
3. Reclassify treasury into the five bands: `FLUSH, STABLE, STRAINED,
   INDEBTED, BROKE`.

Tax efficiency baseline `0.35`, scaled by `TaxLevel { INDULGENT, MODEST,
BURDENED, RUINOUS }`. Rulers push tax up when they must, not when they wish.

### 13.2 Relations (`scripts/kingdom_relations.gd`, autoload `Relations`)

Undirected graph of kingdom pairs with
`enum RelationState { AT_WAR, HOSTILE, NEUTRAL, FRIENDLY, ALLIED }`.

Wars carry a casus belli:
`enum CasusBelli { BORDER_DISPUTE, SUCCESSION_CLAIM, ... }`. Opportunism
wars fizzle fast; religious wars grind.

Monthly drift pulls pairs toward neutral; small monthly roll can end a
war in peace. `WorldAI` declares new wars.

### 13.3 Armies & battles (`scripts/army_registry.gd`, `scripts/battle_resolver.gd`)

One standing army per kingdom (`scripts/army.gd`). Fields:
`size, quality, morale, supply, loyalty`. Peace rebuilds, war grinds.
Every month a warring pair rolls for a battle (base chance 22%, +1.5%/month of
war, capped 65%, winter multiplier 35%). Battles mutate both armies and
publish outcomes to `PublicNews`. A broken army ends the war in dictated peace.

### 13.4 Infrastructure (`scripts/infrastructure_manager.gd`)

Kingdoms autonomously start building `road_network / city_walls / granary /
harbour` projects when their treasury allows (`FLUSH` 18%/month, `STABLE`
10%/month, else 2% at peace). Costs in PROJECT_COSTS; construction 1–3 years.
Completion mutates `Province.buildings`, which other systems read
(walls soften war attrition, granaries soften famine, harbours lift silver).

### 13.5 Population (`scripts/population_manager.gd`, autoload `Population`)

Each populated province drifts its head-count monthly. Peace grows by
`BASE_ANNUAL_GROWTH = 0.5%/yr`. Revolt, plague, famine, war each stack
their own monthly loss rates. Raw numbers never shown — map detail reads
`Province.phrase_for()`.

### 13.6 Unrest (`scripts/unrest_manager.gd`, autoload `Unrest`)

Each province has a 0–100 unrest scalar, displayed only as a band.
Covert actions add unrest (rumour +6, plant_idea +5, agitate +10);
ruinous tax adds 5/mo, burdened +2, war +3; decays 2/mo. Crossing into
*seething* or *in revolt* publishes a dispatch.

### 13.7 Random events (`scripts/random_events.gd`)

Monthly per-province rolls:
`P_PLAGUE = 0.4%, P_FAMINE = 0.6%, P_EARTHQUAKE = 0.3%`. Comet yearly 5%.
Plague → sharp unrest + six months of production cut. Famine → softer
unrest + one year production cut. Earthquake → treasury blow + unrest.
Comet → portent + piety shifts. All effects publish through `PublicNews`.

### 13.8 WorldAI (`scripts/world_ai.gd`, autoload `WorldAI`)

Monthly pulse. Per ruler: 3% chance of decree. Per world-pair: 0.5% war
declaration. Per kingdom: treasury-crisis roll. Natural deaths of aged
actors. Assassination attempts on rulers with ambitious heirs.
Coup rolls for plotters with `ambition ≥ 70 && loyalty ≤ 50` in roles
`{HEIR, ADVISOR, GENERAL}` — base 0.25%/month attempt, 12% warning chance,
4-month cooldown. Ruler paranoia multiplies coup odds.

### 13.9 Ambition drift (`scripts/ambition_drift.gd`)

Every month, non-ruler ambition drifts ±1–2 toward 50 modulated by the
state of their kingdom (ruinous tax, war, unrest all push up). Rulers
drift paranoia up under the same stimuli.

### 13.10 Characters (`scripts/character_generator.gd`, autoload `Characters`)

~0.5 minor actors per million souls per month, spawned into random
populated provinces. Roles drawn from `{MERCHANT, PRIEST, PHILOSOPHER}`.
Traits weighted by province conditions (a long-revolting province produces
more paranoid, less loyal merchants).

---

## 14. Mandates (directed objectives)

`scripts/mandate_registry.gd` (autoload `Mandates`). Two flavours shipped:

- **Removal** — three phases: `removal_identify → removal_shake → removal_finish`.
  Offered emergently when a ruler's ambition crosses a threshold.
- **Survival** — `survival_go_cold → survival_outlast`.

The registry handles offer → accept → defer → abandon flow, phase
progression driven by `action_resolved / actor_died / exposure_level /
month_passed` signals, and a small letter flow around each lifecycle
event.

---

## 15. Rival societies

Five named rivals. From `scripts/rival_society.gd` and
`scripts/rival_registry.gd`:

| Society     | Network shape  | Themed methods                                                                   |
|-------------|----------------|-----------------------------------------------------------------------------------|
| Pyre        | CELLULAR       | `accelerate_collapse, fan_unrest, burn_granaries, undermine_legitimacy`           |
| Architects  | HIERARCHICAL   | `consolidate_succession, strengthen_bureaucracy, suppress_dissent, reinforce_orthodoxy` |
| Weavers     | FAMILY         | `arrange_marriage, engineer_heir, break_rival_line, bury_bastard`                 |
| Veil        | DISTRIBUTED    | `shelter_scholar, quietly_copy_library, protect_heretic, suppress_book_burning`   |
| Compact     | DIFFUSE        | (own method set)                                                                  |

Tempos: `SLOW / REACTIVE / GENERATIONAL / STEADY`.

### 15.1 Rival ops are hidden

Operations publish as public news events with hidden keys
(`rival_signature`, `rival_method`) that normal UI never renders. The
player surfaces them only through the five-level fingerprint chain.

### 15.2 Fingerprint investigation (`scripts/fingerprint_library.gd`)

Levels:
```
0 Signal        visible in news automatically
1 Mechanism     deliberate, not natural
2 Actor         local actor/institution implicated
3 Pattern       three+ ops share a hidden hand
4 Fingerprint   hidden hand matched to a society
```

Society confirmation: `0 unknown / 25 glimpsed / 50 provisional /
75 confirmed / 100 catalogued`. Operations the player advances up the
chain are run via the `investigate_anomaly`, `cross_reference_pattern`,
and `match_fingerprint` actions.

### 15.3 Other immortals

`scripts/immortals_registry.gd` (autoload `Immortals`) keeps a roster of
4–5 peers, one per founded society. Each is an `OtherImmortal`
(`scripts/other_immortal.gd`) with `kill_state { ALIVE, POSTHUMOUS,
CONTESTED }` and relationship
`{ unknown, aware, in_contact, truce, cold, war, dead, escaped }`.

An immortal stays `unknown` until their society hits catalogued
confirmation (≥ 85 on `Fingerprints.society_confirmation`). At that
point `Immortals` flips `known_by_player = true` if they are still alive
and fires the reveal letter. Dialogue trees are loaded from
`data/immortals/*_immortal.json` when the player runs `request_contact`
successfully.

---

## 16. Failure states

`scripts/failure_states.gd` (autoload `Failures`). Five recoverable/sticky
states:

- `NETWORK_COLLAPSE` — too many hosts burned. Tier-2 ops blocked for years.
- `RIVAL_DOMINATION` — a rival society hit a strategic objective.
- `IDEOLOGICAL_CAPTURE` — the player's own pattern library has been
  successfully reverse-engineered or co-opted.
- `EXPOSED_STATE` — the global exposure meter has pinned at Exposed.
- `PHYSICAL_DEATH` — terminal in ironman mode.

Each state emits `state_entered(state, context)` and remains active until
its recovery criteria clear.

---

## 17. Religions and ideologies

`scripts/religion.gd` + `scripts/religion_registry.gd` (autoload `Religions`).

Religion/ideology lifecycle:
`EMERGENCE → CONSOLIDATION → DOMINANCE → FRACTURE → DECLINE` (with a
revival path from DECLINE).

Transition thresholds (from `religion_registry.gd`):
- emerge → consolidation: depth ≥ 25
- consolidation → dominance: institution ≥ 60 AND depth ≥ 50
- dominance → fracture: reform pressure ≥ 75
- fracture → resolve: reform ≤ 35
- fracture → decline: institution ≤ 25
- decline → revival: depth ≥ 60
- extinction: depth < 4

Neighbour-province spread: 4%/faith/neighbour/month, baseline 1% presence
per successful spread. The `is_ideology` flag on a Religion reskins the
vocabulary only; mechanics are shared.

---

## 18. Owned entities

`scripts/owned_entity.gd` + `scripts/entity_registry.gd` (autoload `Entities`).
Durable institutions the player runs through proxies (they never appear on
its records).

Kinds: `TRADING_COMPANY, ACADEMY, MONASTERY, GUILD, ESTATE, BANKING_HOUSE`.

Monthly tick (for each entity):

1. Pay yield silver into `Purse` (minus a corruption skim).
2. Bump `Picture` visibility in the relevant kingdoms (home always;
   trading company reach on top; monastery adds a stale-proof baseline).
3. `corruption += CORRUPTION_DRIFT_PER_MONTH = 0.15`, faster in unstable
   kingdoms or with a dead proxy.
4. At `LEAK_THRESHOLD` the entity skims 15% off the top silver;
   at `LOSS_THRESHOLD` the player loses it entirely.

`audit_entity` is the action that resets a slipping entity's proxy.

---

## 19. Dynasties

`scripts/family.gd` + `scripts/family_registry.gd` (autoload `Dynasties`).
Only actors the player explicitly brings into the net appear here; ambient
NPCs run without dynastic tracking.

Monthly `MONTHLY_DECLINE_DRIFT = 1` on neglect. Warning at `DECLINE_WARN = 55`,
dissolves at `DECLINE_BREAK = 85`.

Signals cover succession (`family_succession(family_id, old_head, new_head)`),
child births (with trait inheritance / drift based on generational service),
and need-raising events (`family_need_raised(family_id, kind)`).

---

## 20. Languages

`scripts/language_registry.gd` (autoload `Languages`). Minimal §23 implementation.

- Competence levels on `Actor.languages`: `0 none, 1 basic, 2 functional, 3 fluent`.
- Each kingdom has a native + secondary language list (from
  `data/languages_500bce.json`).
- Actors born/generated in a kingdom are seeded with that language,
  biased by role (scholars/priests pick up scholarly languages, merchants
  and port dwellers pick up trade lingua francas).
- Era transitions (`Eras.era_changed`) trigger evolution ticks that retire
  dead languages and morph vernaculars per `data/language_evolution.json`.

---

## 21. Cover identities

`scripts/identity.gd` (`CoverIdentity`) + `scripts/identity_registry.gd`
(autoload `Identities`).

A cover identity is the face the player wears on one side of the table.
Fields: `id, cover_name, apparent_age, profession, home_region_id,
anchor_actor_ids, legend_score (0..100), burned, opened_day, note`.

UI never shows the raw `legend_score` — only its band via
`legend_band_phrase()`. Once burned, an identity cannot be rehabilitated.

One starter identity is seeded (`ident_starter_trader` — *Demetrios of
Miletos*). Consumption by actions (legend accrual, identity-gated ops,
burn chains) is flagged in the code as Phase-G, not yet wired.

---

## 22. Memoirs and automations

### 22.1 Patterns (`scripts/memoirs.gd`, autoload `Memoirs`)

Every time the player completes a manual action successfully, `Memoirs`
records a `MemoirPattern` (category + profile dict + headline). Profile
stores role, kingdom, trait bands. Over time the pattern ages: stale
patterns are flagged `unverified` — still usable but warned about
(§13.5).

Match similarity:
`score = (role 2.0 + kingdom 0.5 + traits 1.0) / weight_sum`.
Below `MATCH_THRESHOLD = 0.6` the pattern is not offered. When above,
the Compose panel shows an automation hint.

### 22.2 Automations (`scripts/automations.gd`, autoload `Automations`)

Standing orders built on top of Memoirs patterns. An `AutomationRule`
(`scripts/automation_rule.gd`) watches for trigger conditions (e.g. any
newly-cultivated merchant in a given region) and dispatches the matched
pattern. Every automation fire costs exposure like a manual action.

### 22.3 Memoirs view (`scripts/memoirs_view.gd`)

Full-screen overlay with three sections:
1. **Standing orders** — current automation rules.
2. **Known profiles** — pattern catalog.
3. **System reference** — the glossary of qualitative bands
   (Purse, Exposure, Treasury, Tax, Relationship, Kingdom Relations,
   Unrest, Time Dial, Whispers, Inbox, Cover Identities), dynamically
   sourced from the live constants (`Purse.band_entries()`,
   `Exposure.level_entries()`, etc.).

---

## 23. Scripted beats and unlocks

### 23.1 First-session beats (`scripts/first_session_beats.gd`, autoload `Beats`)

Scripted early-game letters with delivery keyed to day counts or simple
triggers. Every sender goes through `OrgRoles.sender_line()`. The beat
sequence introduces the starter coordinator, establishes the single
banking-house relationship, and paces initial onboarding without
flooding the inbox.

### 23.2 Unlocks (`scripts/unlocks.gd`, autoload `Unlocks`)

Four table surfaces are dimmed until their respective milestones fire:

- **Memoirs** — after first successful manual action (creates first pattern).
- **Vault** — after first financial routing decision.
- **Library** — after first completed investigation chain.
- **Roster** — after first OrgMember promoted above operative.

On unlock, `Unlocks.surface_unlocked` fires; `Inbox` drops a one-shot
factotum letter that names the object and its hotkey.

---

## 24. Save and persistence

### 24.1 Per-session saves (`scripts/save_manager.gd`, autoload `SaveManager`)

JSON blobs under `user://saves/`. Save version 2. Slots:
`autosave, autosave_a, autosave_b, quicksave, slot_1, slot_2, slot_3`.

Each subsystem implements `snapshot()` / `restore()`. SaveManager composes
them rather than being a god object. Covered systems include (non-
exhaustive): GameClock, Scheduler, Actors, Org, Inbox, Actions, Exposure,
KingdomEconomy, Relations, Finance, Purse, Picture, Fidelity, Rivals,
Fingerprints, Shadow, Immortals, PublicNews, Mandates, Entities,
Languages, Dynasties, Failures, Base, Memoirs, Automations, Whispers,
Unlocks, WorldAI, Codebook, Identities.

### 24.2 Autosave (`scripts/time_controller.gd`)

Rotating A/B pair keyed to `Prefs.autosave_interval_days` (default 30 game-
days). A crash leaves both files intact; the newer wins.

### 24.3 Ironman (`scripts/preferences.gd`)

`Prefs.ironman = true` gates manual saves. Only autosave + the Archive
slot browser remain. Physical death becomes terminal.

### 24.4 Cross-run persistence (`scripts/world_profile.gd`, autoload `WorldProfile`)

`user://world_profile.json`. Prior runs commit a summary + machine
footprint; new games (if `Prefs.world_persistence_enabled`) pull in
legacy entities, families, rumours, and pre-revealed fingerprints.
Disabling the preference makes every new game a clean slate.

### 24.5 Chronicle (`scripts/chronicle.gd`, autoload `Chronicle`)

A retrospective log. Listens to "these will matter a year from now"
signals (society identification, phase changes, first deaths, war
declarations) and captures a dated line for each. `Ctrl+Shift+K`
dumps it to markdown under `user://chronicles/`.

---

## 25. Preferences and accessibility

`scripts/preferences.gd` (autoload `Prefs`), persisted to
`user://preferences.json`.

- **Time**: `auto_pause_on_priority` (letters with priority flag freeze time).
- **Saves**: `continuous_autosave`, `autosave_interval_days`, `ironman`.
- **Accessibility**: `reduced_motion`, `ui_font_scale`,
  `colorblind_mode` (`off | deuteranopia | protanopia | tritanopia` —
  palette remap via `scripts/ui/colorblind_palette.gd`),
  `focus_ring_strong`.
- **World persistence**: `world_persistence_enabled`.

UI in `scripts/preferences_view.gd`, opened with `Ctrl+,`.

---

## 26. Audio, theming, notifications

- `scripts/audio_director.gd` + `scripts/procedural_audio.gd` — thin audio
  glue with procedural cues (letter opens, seal snaps, chronicle seals).
- `scripts/era_theme.gd` reacts to `Eras.era_changed` and retints the
  table. Surface types: `wax_tablet | vellum | parchment | …`.
- `scripts/notifications.gd` (autoload `Notifications`) tracks unseen counts
  for `ledger`, `dossiers`, `map`. Incremented by signals
  (`KingdomEconomy.tick`, `PublicNews.news_added`, `Relations.relation_changed`),
  cleared on open.

---

## 27. Data files

- `data/actions.json` — 35 action definitions.
- `data/actors_500bce.json` — 25 authored starting actors (including two
  starter actors tagged `"starter": true`).
- `data/world_500bce.json` — 19 kingdoms, 91 provinces.
- `data/eras.json` — 5 era windows (ancient → modern).
- `data/eras_theme.json` — per-era palette / typography / map tint /
  surface tokens.
- `data/religions_500bce.json` — seed pantheons.
- `data/ideologies_500bce.json` — seed ideologies (share the religion data
  model, different UI).
- `data/languages_500bce.json` + `data/language_evolution.json`.
- `data/immortals/*_immortal.json` — dialogue trees for rival immortals,
  one per society (Architects, Compact, Pyre, Weavers; Veil TBD).
- `data/natural_earth_mediterranean.json` + `data/map_cells.json` — map
  geometry source (consumed by `scripts/map_data.gd`).

---

## 28. Entry point and session lifecycle

- Main scene: `scenes/title/title.tscn` (`scripts/title_screen.gd`).
- Title screen: three choices (new game / continue / slot browser),
  styled as parchment with a wood background.
- `scripts/session.gd` (autoload `Session`) carries the pending load
  slot across the title → table scene swap, and flips `Session.in_game`
  so autosave-on-quit doesn't fire from the title screen.
- Once in the table scene, `scripts/first_session_beats.gd` (autoload
  `Beats`) runs the onboarding script; `Inbox.seed` drops the first
  letter from the starter coordinator; every autoload's `_ready()` has
  already run and hooked `EventBus` / `GameClock` as needed.
- The player may then press `Space` to start time, or `1` / `2` for a
  speed.

---

## 29. Design invariants enforced by code

These are rules the code actively protects:

- **No raw numbers in the UI.** Every scalar the player sees is routed
  through a qualitative phrase (`TraitCues`, `Purse.band_entries`,
  `Exposure.level_entries`, `Province.unrest_phrase`,
  `CoverIdentity.legend_band_phrase`, etc.).
- **No ghost narrators.** Every letter sender goes through `OrgRoles.
  sender_line(role, region)`. A self-test (`scripts/dev/grep_self_test.gd`)
  scans for forbidden "Your X" strings and flags regressions.
- **No unknown actors in the UI.** Dossier and Compose pickers filter
  through `Picture.known_actors()`. Cold kingdoms and their inhabitants
  are invisible until the player generates a picture of them.
- **No direct world mutation from the UI.** Every action goes through
  `Actions.issue()` → Scheduler → resolution → `EventBus.letter_delivered`.
- **No god object.** Save/load composes subsystem snapshots. Systems
  communicate through `EventBus`, not direct references.

---

## 30. What's *not* implemented (marked in code as TBD / Phase-G)

Based on comments and `@warning_ignore` markers the codebase explicitly
flags the following as unfinished:

- Cover Identity consumption by actions (legend accrual, identity-gated
  ops, burn chains) — the data model and registry exist, wiring does not.
- Commander trait bonuses in `battle_resolver.gd` — hooks are present,
  commander assignment is not.
- Tax unrest pressure (§32.6) — reserved on `Kingdom.TaxLevel`, not
  modelled yet.
- `Province.buildings` demolition — buildings persist forever; nothing
  demolishes them.
- Additional mandate flavours beyond Removal and Survival — registry
  handles generic phase progression but only those two types are authored.

Everything else listed in this document is live in the current code.
