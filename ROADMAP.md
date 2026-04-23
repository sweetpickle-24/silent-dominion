# Silent Dominion — Implementation Roadmap

> A phased plan for building Silent Dominion in Godot. The project is a grand-strategy shadow-power sandbox with ~25 interconnected systems. **Ship the smallest playable loop first, then layer systems onto it.** Nothing in the GDD matters until there is a single playable minute.

See `docs/` for the full design specification. This file is about what to build, in what order, and why.

---

## 0. Guiding principles for the build

| Principle | What it means for the schedule |
| --- | --- |
| **Loop first, content later** | The first thing playable must be the full core loop: inbox → action → wait → report. Everything else is iteration on that loop. |
| **Simulation before UI polish** | The table UI (§7) can look placeholder-ugly for months. The simulation must be correct first. UI beautification is a dedicated late phase. |
| **One system, end-to-end, before two** | Do not build half of four systems. Build one system fully integrated (host + action + report) before adding the next. |
| **Data first, always** | Every system begins with its data model. Traits (§24), resources (§32), provinces (§8.2), events (§34). Content and UI consume data; they never own it. |
| **Ironman is the intended experience** | Design every mechanic assuming no reloads. Save-scumming is a crutch for debugging only. See §29. |
| **Cut ruthlessly** | If a Phase 1 feature is slipping, move it to Phase 2. A shipped slice beats a half-finished ambition. |

---

## 1. Tech stack and repository layout

**Engine**: Godot 4.x (already initialised; see `project.godot`).

**Language**: GDScript for game code, C# optional for CPU-intensive simulation inner loops if profiling demands it.

**Why Godot**: open-source, strong 2D tooling for the table-and-map UI, lightweight, fast iteration.

**Proposed top-level directories** (to be created as each system lands):

```
/addons/                -- third-party
/assets/                -- art, fonts, audio (era-themed)
/data/                  -- JSON/CSV content: provinces, traits, religions, events
/docs/                  -- this design documentation
/scenes/                -- Godot scenes (UI screens, table, map, panels)
/scripts/
	/simulation/        -- core simulation tick, kingdom AI, world state
	/organisation/      -- operative/coordinator/lieutenant/entity systems
	/intelligence/      -- two-reality system, reports, fog of knowledge
	/memoirs/           -- pattern library, automation engine
	/ui/                -- table, map, dossier, inbox widgets
	/save/              -- save/load, chronicle generator
/tests/                 -- unit and integration tests
```

---

## 2. Phased schedule

Rough sizing. Exact dates depend on team size. **Assume solo or tiny team.**

| Phase | Goal | Target duration |
| --- | --- | --- |
| **Phase 0 — Foundations** | Engine, data model, core loop prototype | 4–6 weeks |
| **Phase 1 — Vertical Slice** | One city, one host, one full session end-to-end | 8–12 weeks |
| **Phase 2 — Core Organisation** | Full four-layer hierarchy, financial network, two-reality system | 10–14 weeks |
| **Phase 3 — The World** | Full map, provinces, kingdom simulation, autonomous world | 12–16 weeks |
| **Phase 4 — Rivals & Society Layer** | Rival societies, fingerprints, counter-intelligence | 8–10 weeks |
| **Phase 5 — Depth Systems** | Memoirs automation, religion/ideology, owned entities, dynastic loyalty | 10–14 weeks |
| **Phase 6 — Eras & Pivoting** | Era progression, pivot mechanic, multi-century play | 8–10 weeks |
| **Phase 7 — Polish & Onboarding** | UI polish, tutorial by situation, difficulty modes, save architecture | 10–12 weeks |
| **Phase 8 — Advanced / Phase 2 features** | Influence waves, pattern recognition, cultural memory, inter-society diplomacy | post-launch |

Total Phase 0–7: **~70–94 weeks** of focused work.

---

## 3. Phase 0 — Foundations

**Goal**: prove that the core loop is technically possible. No content. Fake data only.

### Deliverables

- [x] Godot project structure set up (directories above).
- [x] `GameClock` autoload: ticks in game-days, emits `day_passed` / `month_passed` / `year_passed` (`scripts/game_clock.gd`).
- [x] `EventBus` autoload: global signal hub for decoupled system communication (`scripts/event_bus.gd`).
- [x] `WorldState` singleton: the root of all simulation data. Serialisable. (`scripts/world_data.gd` + all registries).
- [x] Save/load round-trip working for a trivial WorldState (`scripts/save_manager.gd` + `scripts/stress_test.gd::run_save_roundtrip`).
- [x] One placeholder `Table` scene with: inbox panel, action panel, time controls, day counter (`scenes/table/table.tscn`, `scenes/table/table.gd`).
- [x] One placeholder `Actor` class with trait fields (§24 canonical set) (`scripts/actor.gd`, `scripts/actor_registry.gd`).
- [x] One placeholder `Action` system: player clicks a button, a signal fires, a delay resolves, an "event" appears in the inbox (`scripts/action_runner.gd`, `scripts/inbox_manager.gd`).

### Exit criteria

Player can open the table, click "perform action on dummy actor", and see a dummy report arrive 7 game-days later after advancing time. **Nothing else.**

### Systems referenced

- §7 Interface philosophy (placeholder only)
- §24 Character traits (data model)
- §29 Save architecture (basic round-trip)
- §34 Events (basic delivery)

---

## 4. Phase 1 — Vertical Slice

**Goal**: one city, 500 BCE, one host, one coordinator, one full playable session. The onboarding first-session experience (§28.1) running end-to-end.

### Deliverables

#### 4.1 Host system (§3.1)
- [x] Full host data model: traits, relationship, exposure, resistance.
- [x] Host cultivation over time — relationship score rises with reinforcement actions.
- [x] Host resistance calculation (§24.3) using traits, shown only as qualitative UI cues.
- [x] Death of a host (§14.4): organisation continues, relationship to that individual ends.

#### 4.2 Action palette (§3.4)
- [x] Full action palette implemented: cultivate, plant idea, bribe, amplify paranoia, seed rumour, introduce advisor, etc.
- [x] Each action has: exposure cost, resource cost, time-to-resolve, probabilistic outcome.
- [x] Actions dispatched via operative → coordinator → host chain, with realistic time lag.

#### 4.3 Exposure system (§3.2)
- [x] Exposure meter per host and per operative.
- [x] Exposure accumulates with action frequency, decays with rest.
- [x] High exposure → automatic consequences (host investigated, operative burned).

#### 4.4 Inbox and dossier (§7.4)
- [x] Inbox: era-appropriate letters delivered at realistic lag.
- [x] Dossier per character: trait hints (not numbers), relationship history, last-known state.
- [x] Filtering and searching.

#### 4.5 One city, one province
- [x] Single city scene with district map (§8.5) — palace, temple, market, docks, workshops.
- [x] Coordinator coverage visualised as fog lifting over districts.
- [x] Minimal province around the city: population, one trade route, one resource.

#### 4.6 Minimal two-reality system (§7.6)
- [x] `GroundTruth` (simulation) and `PlayerPicture` (what reports have conveyed) are distinct data structures.
- [x] All UI reads from `PlayerPicture` only.
- [x] Reports are the only channel that mutates `PlayerPicture`.
- [x] Stale data stays stale until a new report arrives.

#### 4.7 First-session flow (§28.1)
- [x] Turn 1 letter on new game start.
- [x] Scripted moments: rival faction courts host, second host opportunity, first financial request.
- [x] The game teaches through situation, not tooltips.

### Exit criteria

A new player can play from new game through the first ~year of in-game time, encounter every Phase 1 system naturally, and end the session with a saved state that reloads correctly.

### Systems referenced

§3, §7, §8.5, §24, §28, §29.

---

## 5. Phase 2 — Core Organisation

**Goal**: the four-layer machine (§14). The player becomes a real operator rather than a single-host handler.

### Deliverables

#### 5.1 Organisation hierarchy (§14.1)
- [x] Operative / coordinator / lieutenant / entity layers as distinct classes with distinct roles.
- [x] Assignment and reassignment mechanics.
- [x] Span-of-control limits: a coordinator can only effectively run N operatives; a lieutenant N coordinators.

#### 5.2 Compartmentalisation (§14.2)
- [x] Burn-down modelling: when an operative is compromised, only their own upward link is at risk, not the full chain.
- [x] Rollback procedures: severing a contaminated cell.

#### 5.3 Financial network (§16)
- [x] Banking houses as entities with currency balances (gold and silver separately, §32.4).
- [x] Transaction routing: every payment has a path, a discretion cost, a latency.
- [x] Hawala-style partial settlements across geography.
- [x] Debt instruments — the player holds IOUs from rulers and institutions.

#### 5.4 Bribing (§17)
- [x] Bribery as a first-class action using greed/loyalty trait stack.
- [x] Silent accept / silent reject / loud reject outcomes with different intelligence footprints.
- [x] Bribes routed through the financial network, not conjured from nothing.

#### 5.5 Internal corruption (§19)
- [x] Coordinator/lieutenant corruption risk driven by greed + loyalty + oversight.
- [x] Audit actions: cross-check books, rotate roles, send counter-intelligence.
- [x] Rival-induced corruption vs. opportunistic corruption distinction (§19 detection).

#### 5.6 Intelligence rechecks (§18)
- [x] Player can trigger a recheck on a source.
- [x] Recheck returns: clean / compromised / ambiguous.
- [x] Double-agent option: keep a compromised source running while feeding false patterns.

#### 5.7 Two-reality system — full (§7.6)
- [x] Confidence fog per report.
- [x] Source cross-referencing UI — three reports, shown as overlapping or contradicting.
- [x] Neutral channels (§34.4) added as a separate read-only stream.

### Exit criteria

Player can build an organisation of 10–20 people across multiple cities, route money between them, get betrayed by a corrupt lieutenant, detect it via a recheck, and recover. Full cycle.

### Systems referenced

§14, §16, §17, §18, §19, §24.

---

## 6. Phase 3 — The World

**Goal**: stop playing in a sandbox and start playing in a living continent.

### Deliverables

#### 6.1 Full map (§8)
- [x] Mediterranean + Mesopotamia + Persia + Gaul + North Africa as the starting region (§8.9).
- [x] Province atomic unit (§8.2) with full attributes: population, resources, climate, terrain, infrastructure.
- [x] Zoom levels: world → region → province → city → district (§7.3 + §8.4).
- [x] Era-appropriate map visuals for the first supported eras (Classical, Late Antique) (`scripts/era_theme.gd`, `data/eras_theme.json`, `scripts/map_renderer.gd` tint hooks, `scripts/map_view.gd` EraTheme registration).

#### 6.2 Province simulation
- [x] Population dynamics (§26): growth, famine, plague, migration, war loss.
- [x] Resource production and consumption (§32): grain, iron, silver, gold, timber, horses, cloth, salt.
- [x] Infrastructure projects (§8.7): roads, ports, walls, granaries — built by kingdoms, observable by the player.
- [x] Climate and terrain effects (§8.3): seasonality of campaigning, trade route viability.

#### 6.3 Kingdom AI (§33, §9.4, §9.6)
- [x] Simplified kingdom AI: tax collection, army maintenance, food distribution, diplomatic actions, factional balance.
- [x] Observable conditions only (§33.2) — no numbers exposed to the player.
- [x] Low-fidelity AI (§9.6) for kingdoms outside the player's coverage — cheap ticks, summary events only.
- [x] Ruler AI driven by traits (§24): ambition, paranoia, piety, etc.

#### 6.4 Autonomous world (§9)
- [x] Battle resolution (§9.1): probabilistic, trait-driven, supply-aware.
- [x] Natural events (§9.2): weather, plague, earthquake, harvest variance.
- [x] Autonomous conflict between kingdoms the player has never touched (§9.3).
- [x] The player as input shaper, not engine (§9.5).

#### 6.5 Diplomacy (§31)
- [x] State-to-state relationship scores with stacking modifiers (§31.1).
- [x] Casus belli and war mechanics (§31.2).
- [x] State-to-institution relationships (§31.3) — treasury dependencies, debt leverage.
- [x] Institution-to-institution relationships (§31.5).

#### 6.6 Military forces as simulation objects (§27)
- [x] Army data model: size, quality, morale, supply, command quality, loyalty direction.
- [x] Recruitment from province population and culture.
- [x] Movement and logistics on the map, visible to operatives with coverage.

#### 6.7 Procedural characters anchored to history (§8.8, §8.11)
- [x] Historical figures with fixed core trait scores placed on the timeline.
- [x] Procedurally generated characters with weighted trait distributions by province, city, family, era.
- [x] Character generation rate scales with population.

#### 6.8 Event system full (§34)
- [x] Event tiers: worldwide, state, factional, local (§34.1).
- [x] Propagation models: geographic radial, route-following, institutional (§34.2).
- [x] Narrator bias per intermediate source (§34.3).
- [x] Three intelligence channels — operative / neutral / official (§34.4).
- [x] Action-result gap (§34.5) and causation invisibility (§34.6).

### Exit criteria

Player can watch a continent's history unfold for 50 game-years without acting and see: dynasties rise and fall, wars start and end, plagues wipe out regions, trade routes shift. The autonomous world is believably alive.

### Systems referenced

§8, §9, §24, §26, §27, §31, §32, §33, §34.

---

## 7. Phase 4 — Rivals and the Society Layer

**Goal**: the player is no longer alone in the shadows.

### Deliverables

#### 7.1 Rival secret societies (§5)
- [x] At least four named societies with distinct agendas and geographic bases (§5 named societies).
- [x] Each society has its own operative network, financial infrastructure, host portfolio.
- [x] Societies act on their own agendas, independent of the player's actions.

#### 7.2 Society fingerprints (§8.12)
- [x] Every society has an operational signature — pattern of targets, methods, timing.
- [x] Fingerprint library built by the player over time from observed events.
- [x] UI to compare suspicious news events against known fingerprints.

#### 7.3 Counter-intelligence (§5, §14.6)
- [x] Detecting rival operatives in the player's theatres.
- [x] Investigation chains: a detected rival operative → who they report to → which coordinator → which lieutenant.
- [x] Counter-operations: turn, neutralise, or feed false intelligence to rival operatives.

#### 7.4 False flag operations (§8.13)
- [x] Player can disguise their operations as rival society fingerprints.
- [x] Rivals can do the same to the player.
- [x] Attribution misfires become a recurring strategic theme.

#### 7.5 Meeting other immortals (§5.5)
- [x] Rare encounters with peers — cold peace, tentative cooperation, open shadow war.
- [x] Dialogue and consequence modelling for these events.

#### 7.6 Shadow-figure system (§10)
- [x] Three awareness levels of the player's existence (§10.1).
- [x] Era-appropriate naming of the player's legend (§10.2).
- [x] Chronicle threat: historians who piece together the pattern (§10.4).
- [x] Hunters: individuals who actively seek the player (§10.5).

### Exit criteria

Player must balance building their machine with defending it against rival societies, identifying false flag operations, and managing their own legend across generations.

### Systems referenced

§5, §8.12, §8.13, §10, §14.6.

---

## 8. Phase 5 — Depth Systems

**Goal**: multi-generation play is no longer a survival exercise — it becomes a compounding one.

### Deliverables

#### 8.1 Memoirs system (§13, §30)
- [x] Pattern library data model: archetypes, religions, ideologies, rivals, automations.
- [x] Memoirs panel UI (§30) — era-themed journal on the table.
- [x] Pattern match quality indicator (§30.2) with four thresholds.
- [x] Automation engine: dispatched operations running without per-action player input.
- [x] Stale pattern detection and warning.
- [x] Regional dispatch (§13.3) for late-game coverage.

#### 8.2 Religion and ideology (§25)
- [x] Religion data model (§25.1): doctrinal rigidity, institutional strength, popular depth, geographic distribution, reform potential, ecumenical openness.
- [x] Religion lifecycle (§25.2): emergence, consolidation, dominance, fracture, decline.
- [x] Ideology as parallel structure (§25.3): Stoicism, Confucianism, later ideologies.
- [x] Manual-engagement requirement for new religions (§13.4) before automation unlocks.

#### 8.3 Owned entities (§20)
- [x] Entity types: trading company, banking house, academy, monastery, guild, noble estate.
- [x] Founding and acquiring entities.
- [x] Proxy-structure beneficial ownership — player never on the paperwork.
- [x] Entity event streams to the player.
- [x] Entity longevity across political upheavals (§20.4).
- [x] Entity-level corruption (§20.5).

#### 8.4 Dynastic loyalty (§21)
- [x] Family tree data model with multi-generational tracking.
- [x] Weighted inheritance based on the player's treatment of the family (§21.2).
- [x] Family needs and loyalty maintenance loop (§21.3).
- [x] Stats, training, underdog development (§21.4).
- [x] Functional lieutenant specialisations mapped to family backgrounds (§21.5).
- [x] Family decline and replacement (§21.6).

#### 8.5 Languages (§23)
- [x] Language profiles per operative.
- [x] Regional language requirements for effective operation.
- [x] Language acquisition paths: tutor, immersion, self-study, family inheritance.
- [x] Language evolution across eras (§23.5).
- [x] Cultural tagging on Memoirs patterns — a Latin merchant pattern does not apply to an Arabic merchant.

#### 8.6 Mandates (§11)
- [x] Directed objectives system — optional player-selectable long-term goals.
- [x] Mandate categories (§11.2): ideological, territorial, institutional, succession, collapse-prevention.
- [x] Emergent mandates (§11.3) — discovered through play rather than offered.

#### 8.7 Failure states (§12)
- [x] Explicit game-ending failure conditions modelled and tested.
- [x] Death in Ironman mode ends that playthrough with a chronicle seal.

### Exit criteria

A player who has run a 200-year session has built a multi-generational machine with dynastic lieutenants, owned entities that survived political upheaval, a deep Memoirs library, and a working identity portfolio.

### Systems referenced

§11, §12, §13, §20, §21, §23, §25, §30.

---

## 9. Phase 6 — Eras and Pivoting

**Goal**: the game supports the full 1000–2000+ year arc and the strategic move between civilisational centres.

### Deliverables

#### 9.1 Era progression (§6.2)
- [x] All supported eras defined: Classical, Late Antique, Early Medieval, High Medieval, Renaissance, Early Modern, Modern.
- [x] Era transitions: visual style changes, infrastructure changes, communication speed changes, language evolution.
- [x] Era-appropriate map art, font, UI chrome, audio palette (`scripts/era_theme.gd` + `data/eras_theme.json` drive palette/typography/surface tokens; `scripts/audio_director.gd` + `scripts/procedural_audio.gd` fold procedural ambients per era).

#### 9.2 Pivot mechanic (§6.3)
- [x] Base-of-operations move (§22) as a strategic act, not a safety cycle.
- [x] Pre-move preparation checklist (§22.2).
- [x] Travel animation and map shift (§22.3).
- [x] Transition window (§22.4) with reduced Memoirs reliability locally.
- [x] Era-appropriate travel speeds (§22.5).

#### 9.3 Hundred generations (§6.5)
- [x] Multi-century persistence stress-tested: save files from year 200 still load cleanly at year 1500. (dev harness: F12 / Shift+F12 / Ctrl+Shift+F12)
- [x] Performance optimisation for long-running simulations — procedural world state compression, low-fidelity AI for untouched regions.

#### 9.4 Weighted character generation across history (§8.11)
- [x] Player's past actions write themselves into the next generation of affected populations.
- [x] Trait distribution shifts over centuries in observable ways.

#### 9.5 City-to-global scale (§6.4)
- [x] Player starts in one city with one host, ends controlling a network across continents. (City/district zoom seeded for Athens and Sparta; coordinator coverage lifts district fog.)
- [x] Growth arc validated by actual long-session playtesting (automated proxy: `StressTest.run_growth_arc(500)` in `scripts/stress_test.gd`, triggered via Ctrl+Shift+G in `scenes/table/table.gd`; writes `user://playtest_arc.json` + `user://chronicles/playtest_arc.md` with per-decade metrics and save-roundtrip assertions at years 50/200/450).

### Exit criteria

A dedicated player can begin a new game in 500 BCE, play through to 1500 CE across multiple real-time sessions, and have the simulation remain coherent, performant, and interesting throughout.

### Systems referenced

§6, §8.11, §22.

---

## 10. Phase 7 — Polish and Onboarding

**Goal**: the game is ready for players who have never heard of it.

### Deliverables

#### 10.1 Table UI polish (§7.1)
- [x] Era-themed table visuals: wax tablets, vellum, parchment, printed pages (`scripts/era_theme.gd` `surface_texture()` kinds, `data/eras_theme.json` era rows; views registered via `EraTheme.register_view` in `scripts/map_view.gd`, `scripts/memoirs_view.gd`, `scripts/library_view.gd`, `scripts/vault_view.gd`, `scripts/roster_view.gd`, `scripts/dossier_view.gd`, `scripts/public_news_view.gd`).
- [x] Typography, animation, lighting — macOS Tahoe-inspired modern reference with period styling (`scripts/era_theme.gd` typography tokens + modulate tints, `scripts/ui/style_tokens.gd` label/panel helpers, map hover/zoom tweens in `scripts/map_view.gd` gated by `Prefs.anim_duration()`).
- [x] Consistent component library: buttons, panels, toggles, dossiers (`scripts/ui/style_tokens.gd` `apply_panel`/`apply_title_label`/`apply_body_label`/`apply_primary_button` helpers consumed by `scripts/preferences_view.gd`, `scripts/public_news_view.gd`, `scripts/dossier_view.gd`).

#### 10.2 Map polish (§7.3)
- [x] Era-appropriate map art per era, with smooth transitions (`scripts/era_theme.gd` `map_tint()` + `theme_changed` signal, consumed by `scripts/map_renderer.gd` and `scripts/map_view.gd`; crossfades handled by the existing modulate tween).
- [x] Zoom animations, hover reveals, proper contrast, readable labels at all zoom levels (`scripts/map_view.gd` zoom + hover tweens, province-label staggered fade; font sizing routed through `EraTheme.typography()`).

#### 10.3 Intelligence layer UI (§7.4, §8.10)
- [x] All map intelligence layers toggleable — political, unrest, prosperity, cover fidelity, religion, rival-society fingerprints, military strength (size × quality via `Armies`), and a dedicated famine layer reading from `PopulationManager`.
- [x] Layer opacity, filtering, and search. (Opacity slider mixes metric over political base; Enter-to-jump search selects and centres a province by name.)

#### 10.4 Time controls (§7.5)
- [x] Pause, play, fast forward, scheduled stop on events.
- [x] Auto-pause on high-priority events (configurable).

#### 10.5 Public news (§7.7)
- [x] News feed as a dedicated table element with era-appropriate styling (`scripts/public_news_view.gd` + `scenes/table/public_news_view.tscn`, registered on the table in `scenes/table/table.gd`; styled via `EraTheme.register_view` + tier badges + narrator badge).
- [x] News calibration against operative reports (used by the two-reality system) (`scripts/public_news.gd` `_apply_calibration()` with Jaccard overlap against recent operative letters; `calibration_score` + `calibration_verdict` persisted in `PublicNews.snapshot()` and surfaced as a three-state band in `scripts/public_news_view.gd`).

#### 10.6 Difficulty modes (§7.8)
- [x] Standard vs. Ironman (§29).
- [x] Optional extra difficulty modifiers — more aggressive rival societies, smaller starting resources (`scripts/difficulty_profile.gd` wraps `Prefs` toggles: `aggressive_rivals` → `scripts/rival_registry.gd` tick frequency + pre-seeded lieutenant, `lean_start` → `scenes/table/table.gd` `_apply_new_game_difficulty` purse multiplier, `hostile_hosts` → `scripts/action_runner.gd` host resist bias, `fast_hunters` → `scripts/shadow_figure.gd` hunter thresholds, `brittle_cover` → `scripts/exposure_manager.gd` cover decay; UI in `scripts/preferences_view.gd`).

#### 10.7 Onboarding by situation (§28)
- [x] Fully scripted first session (§28.1).
- [x] System-unlock sequence driven by organisational milestones (§28.2).
- [x] Memoirs panel as living help system (§28.3).

#### 10.8 Save architecture (§29)
- [x] Continuous autosave.
- [x] Session continuity — quit and resume to exact state.
- [x] Chronicle generation per session. (`Chronicle` autoload records era changes, base moves, religion foundings, host deaths, Machine degraded/eased states, and revealed rival societies. Ctrl+Shift+K writes a markdown chronicle to `user://chronicles/`; a letter confirms the path. Chronicle persists through save/load.)
- [x] Ironman enforcement.
- [x] World persistence: prior playthroughs leave their entities, families, and Machine in the world for subsequent playthroughs (`scripts/world_profile.gd` autoload persists to `user://world_profile.json`; commit hooks in `scripts/failure_states.gd` `trigger_physical_death`; `scripts/chronicle.gd` `chronicle_sealed` signal; legacy import + rumour letter + fingerprint pre-seed wired via `WorldProfile.apply_legacy_imports()` in `scenes/table/table.gd` `_apply_new_game_difficulty`; gated by `Prefs.world_persistence_enabled`).

#### 10.9 Accessibility
- [x] Font scaling.
- [x] Colour-blind safe palettes for all intelligence layers (`scripts/ui/colorblind_palette.gd` Brettel/Viénot-style remap with named overlay keys; `scripts/map_renderer.gd` `_cell_color_for_mode` pipes every overlay through `ColorblindPalette.remap`; `Prefs.colorblind_mode` exposed in `scripts/preferences_view.gd` with live refresh via `Prefs.preferences_changed`).
- [x] Reduced-motion option. (Preference gates fades, scale pulses, indicator pops, seal-break, unfold, pending-tray lift, and the inbox badge loop. Opt-in via Ctrl+,.)
- [x] Keyboard navigation for every UI element (`scenes/table/table.gd` global shortcut map: Space/1/2 time, I/M/N/L/D/O/V/R/C/B/F object shortcuts, Esc/F1/F5/F9/F10/Shift+/ overlays, Ctrl+Shift+K chronicle, Ctrl+Shift+G playtest arc; `scenes/inbox/letter_view.gd` J/K/Up/Down browse without closing; `Prefs.focus_ring_strong` available for stronger focus ring).

#### 10.10 Audio
- [x] Era-specific ambient audio palette (`scripts/audio_director.gd` `set_era()` swaps looping `AudioStreamWAV` generated by `scripts/procedural_audio.gd` `make_ambient()`; re-fires on `Eras.era_changed`).
- [x] Event audio cues — subtle, not intrusive (`scripts/audio_director.gd` `play_cue()` on `EventBus.letter_delivered`, `Org.member_burned`, `EventBus.host_died`, `Mandates.mandate_offered`, `Unlocks.surface_unlocked`, `Chronicle.chronicle_sealed`; `scripts/procedural_audio.gd` `make_cue()` synthesises envelopes; gated by `Prefs.sfx_enabled` / volume).
- [x] Music: period-appropriate, looping, low-attention-demand (procedural drone layer in `scripts/procedural_audio.gd` `make_ambient()` loops via `AudioStreamWAV.LOOP_FORWARD`, seeded per era for distinct tonal colour; volume on a dedicated Music/Ambient bus configured in `scripts/audio_director.gd`, gated by `Prefs.music_enabled` / `Prefs.ambient_enabled`).

### Exit criteria

A new player can install the game, start a new session, and play through the first five hours naturally without a tutorial window ever appearing.

### Systems referenced

§7, §28, §29.

---

## 11. Phase 8 — Advanced / post-launch

**Goal**: depth features that are not required for launch but extend the game's long-term appeal. See §35.

### Candidates

- Influence waves (§35.1) — visualise past actions as ripples still moving.
- Pattern recognition layer (§35.2) — game surfaces historical parallels.
- Minority dissent mechanic (§35.3) — small actors overturning large systems.
- Cultural memory fields (§35.4) — civilisations remember the player's past actions.
- Inter-society diplomacy (§35.5) — formal channels between secret societies; shadow war mechanics.

These are explicitly deferred — do not let them distract from Phases 0–7.

---

## 12. Cross-cutting concerns

### 12.1 Testing strategy
- Unit tests for: trait resistance calculation, bribery outcomes, battle resolution probabilities, event propagation, save/load round-trip.
- Integration tests: full session playthroughs — new game → 10 game-years → save → reload → 10 more game-years → deterministic state.
- Deterministic-seed mode for reproducible simulation bugs.

### 12.2 Performance
- Budget: 60 FPS on modern mid-range hardware.
- Simulation tick target: one game-day in ≤10ms on default fast-forward.
- Low-fidelity AI (§9.6) for kingdoms outside the player's coverage — cheap ticks only.
- Event propagation processed in batched passes, not per-event.
- Procedural world state compression for long-running saves.

### 12.3 Data-driven content
- Provinces, religions, ideologies, historical figures, events: defined in data files, not hardcoded.
- Enables modding post-launch and eases content additions during development.
- JSON or CSV, whichever is faster to iterate on with the chosen editor.

### 12.4 Telemetry for development
- Local-only session logs for debugging: what actions taken, what outcomes delivered, what state mutations occurred.
- No network telemetry in the shipped game unless explicit opt-in.

### 12.5 Documentation
- `docs/` specification maintained in sync with implementation.
- Any design change that affects gameplay is reflected in the relevant doc section before shipping.
- Implementation notes per system in `docs/impl/` (to be created as systems land).

---

## 13. Risk register

| Risk | Likelihood | Impact | Mitigation |
| --- | --- | --- | --- |
| **Scope explosion** | High | Fatal | Ruthless cuts. Phase 8 is the graveyard. Nothing is added to Phase 0–7 without pulling something else out. |
| **Two-reality system is slower than designed** | Medium | High | Profile early in Phase 2. If report-driven state updates can't keep up, batch them per-month not per-day. |
| **Long-running save bloat** | High | Medium | Design save format with compression from day one. Test with synthetic 500-year saves in Phase 3. |
| **AI complexity** | High | High | Start with extremely simple kingdom AI in Phase 3. Improve only after it's shipped. Low-fidelity AI for non-focal regions is non-negotiable. |
| **UI polish consumes all remaining time** | High | High | Phase 7 is fixed duration. Anything not done at end of Phase 7 is cut. No exceptions. |
| **Multi-era art production cost** | High | High | Use art style that can be parameterised: texture overlays, colour shifts, font swaps — not bespoke art per era. |
| **Onboarding fails and no new player gets past hour 1** | Medium | Fatal | Playtest Phase 1 build with external testers. Iterate onboarding in every subsequent phase. |
| **Save-scumming trivialises the game** | Medium | High | Ironman is the intended mode. Standard mode is accessibility, not the real game. Marketing and onboarding make this clear. |

---

## 14. Definition of done per phase

A phase is **done** when:

1. All deliverables above have passing tests or explicit exception notes.
2. The exit criteria scenario has been played through from a fresh save by someone other than the author.
3. The relevant `docs/` sections have been reviewed and updated for any design drift.
4. No P1 bugs are open against the phase's systems.
5. A recorded 30-minute walkthrough of the new functionality exists in the project history.

---

## 15. Next concrete steps

1. **Kick off Phase 0 now.**
2. Create `scripts/simulation/GameClock.gd`, `EventBus.gd`, `WorldState.gd`.
3. Define the canonical `Actor` class with the full §24 trait set.
4. Build the placeholder `Table` scene with inbox and action panel.
5. Implement save/load round-trip for a WorldState containing one actor.
6. Ship that as the first internal milestone. Everything else follows from there.
