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

- [ ] Godot project structure set up (directories above).
- [ ] `GameClock` autoload: ticks in game-days, emits `day_tick` / `month_tick` / `year_tick`.
- [ ] `EventBus` autoload: global signal hub for decoupled system communication.
- [ ] `WorldState` singleton: the root of all simulation data. Serialisable.
- [ ] Save/load round-trip working for a trivial WorldState (one dummy actor, one dummy kingdom).
- [ ] One placeholder `Table` scene with: inbox panel, action panel, time controls, day counter.
- [ ] One placeholder `Actor` class with trait fields (§24 canonical set).
- [ ] One placeholder `Action` system: player clicks a button, a signal fires, a delay resolves, an "event" appears in the inbox.

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
- [ ] Full host data model: traits, relationship, exposure, resistance.
- [ ] Host cultivation over time — relationship score rises with reinforcement actions.
- [ ] Host resistance calculation (§24.3) using traits, shown only as qualitative UI cues.
- [ ] Death of a host (§14.4): organisation continues, relationship to that individual ends.

#### 4.2 Action palette (§3.4)
- [ ] Full action palette implemented: cultivate, plant idea, bribe, amplify paranoia, seed rumour, introduce advisor, etc.
- [ ] Each action has: exposure cost, resource cost, time-to-resolve, probabilistic outcome.
- [ ] Actions dispatched via operative → coordinator → host chain, with realistic time lag.

#### 4.3 Exposure system (§3.2)
- [ ] Exposure meter per host and per operative.
- [ ] Exposure accumulates with action frequency, decays with rest.
- [ ] High exposure → automatic consequences (host investigated, operative burned).

#### 4.4 Inbox and dossier (§7.4)
- [ ] Inbox: era-appropriate letters delivered at realistic lag.
- [ ] Dossier per character: trait hints (not numbers), relationship history, last-known state.
- [ ] Filtering and searching.

#### 4.5 One city, one province
- [ ] Single city scene with district map (§8.5) — palace, temple, market, docks, workshops.
- [ ] Coordinator coverage visualised as fog lifting over districts.
- [ ] Minimal province around the city: population, one trade route, one resource.

#### 4.6 Minimal two-reality system (§7.6)
- [ ] `GroundTruth` (simulation) and `PlayerPicture` (what reports have conveyed) are distinct data structures.
- [ ] All UI reads from `PlayerPicture` only.
- [ ] Reports are the only channel that mutates `PlayerPicture`.
- [ ] Stale data stays stale until a new report arrives.

#### 4.7 First-session flow (§28.1)
- [ ] Turn 1 letter on new game start.
- [ ] Scripted moments: rival faction courts host, second host opportunity, first financial request.
- [ ] The game teaches through situation, not tooltips.

### Exit criteria

A new player can play from new game through the first ~year of in-game time, encounter every Phase 1 system naturally, and end the session with a saved state that reloads correctly.

### Systems referenced

§3, §7, §8.5, §24, §28, §29.

---

## 5. Phase 2 — Core Organisation

**Goal**: the four-layer machine (§14). The player becomes a real operator rather than a single-host handler.

### Deliverables

#### 5.1 Organisation hierarchy (§14.1)
- [ ] Operative / coordinator / lieutenant / entity layers as distinct classes with distinct roles.
- [ ] Assignment and reassignment mechanics.
- [ ] Span-of-control limits: a coordinator can only effectively run N operatives; a lieutenant N coordinators.

#### 5.2 Compartmentalisation (§14.2)
- [ ] Burn-down modelling: when an operative is compromised, only their own upward link is at risk, not the full chain.
- [ ] Rollback procedures: severing a contaminated cell.

#### 5.3 Financial network (§16)
- [ ] Banking houses as entities with currency balances (gold and silver separately, §32.4).
- [ ] Transaction routing: every payment has a path, a discretion cost, a latency.
- [ ] Hawala-style partial settlements across geography.
- [ ] Debt instruments — the player holds IOUs from rulers and institutions.

#### 5.4 Bribing (§17)
- [ ] Bribery as a first-class action using greed/loyalty trait stack.
- [ ] Silent accept / silent reject / loud reject outcomes with different intelligence footprints.
- [ ] Bribes routed through the financial network, not conjured from nothing.

#### 5.5 Internal corruption (§19)
- [ ] Coordinator/lieutenant corruption risk driven by greed + loyalty + oversight.
- [ ] Audit actions: cross-check books, rotate roles, send counter-intelligence.
- [ ] Rival-induced corruption vs. opportunistic corruption distinction (§19 detection).

#### 5.6 Intelligence rechecks (§18)
- [ ] Player can trigger a recheck on a source.
- [ ] Recheck returns: clean / compromised / ambiguous.
- [ ] Double-agent option: keep a compromised source running while feeding false patterns.

#### 5.7 Two-reality system — full (§7.6)
- [ ] Confidence fog per report.
- [ ] Source cross-referencing UI — three reports, shown as overlapping or contradicting.
- [ ] Neutral channels (§34.4) added as a separate read-only stream.

### Exit criteria

Player can build an organisation of 10–20 people across multiple cities, route money between them, get betrayed by a corrupt lieutenant, detect it via a recheck, and recover. Full cycle.

### Systems referenced

§14, §16, §17, §18, §19, §24.

---

## 6. Phase 3 — The World

**Goal**: stop playing in a sandbox and start playing in a living continent.

### Deliverables

#### 6.1 Full map (§8)
- [ ] Mediterranean + Mesopotamia + Persia + Gaul + North Africa as the starting region (§8.9).
- [ ] Province atomic unit (§8.2) with full attributes: population, resources, climate, terrain, infrastructure.
- [ ] Zoom levels: world → region → province → city → district (§7.3 + §8.4).
- [ ] Era-appropriate map visuals for the first supported eras (Classical, Late Antique).

#### 6.2 Province simulation
- [ ] Population dynamics (§26): growth, famine, plague, migration, war loss.
- [ ] Resource production and consumption (§32): grain, iron, silver, gold, timber, horses, cloth, salt.
- [ ] Infrastructure projects (§8.7): roads, ports, walls, granaries — built by kingdoms, observable by the player.
- [ ] Climate and terrain effects (§8.3): seasonality of campaigning, trade route viability.

#### 6.3 Kingdom AI (§33, §9.4, §9.6)
- [ ] Simplified kingdom AI: tax collection, army maintenance, food distribution, diplomatic actions, factional balance.
- [ ] Observable conditions only (§33.2) — no numbers exposed to the player.
- [ ] Low-fidelity AI (§9.6) for kingdoms outside the player's coverage — cheap ticks, summary events only.
- [ ] Ruler AI driven by traits (§24): ambition, paranoia, piety, etc.

#### 6.4 Autonomous world (§9)
- [ ] Battle resolution (§9.1): probabilistic, trait-driven, supply-aware.
- [ ] Natural events (§9.2): weather, plague, earthquake, harvest variance.
- [ ] Autonomous conflict between kingdoms the player has never touched (§9.3).
- [ ] The player as input shaper, not engine (§9.5).

#### 6.5 Diplomacy (§31)
- [ ] State-to-state relationship scores with stacking modifiers (§31.1).
- [ ] Casus belli and war mechanics (§31.2).
- [ ] State-to-institution relationships (§31.3) — treasury dependencies, debt leverage.
- [ ] Institution-to-institution relationships (§31.5).

#### 6.6 Military forces as simulation objects (§27)
- [ ] Army data model: size, quality, morale, supply, command quality, loyalty direction.
- [ ] Recruitment from province population and culture.
- [ ] Movement and logistics on the map, visible to operatives with coverage.

#### 6.7 Procedural characters anchored to history (§8.8, §8.11)
- [ ] Historical figures with fixed core trait scores placed on the timeline.
- [ ] Procedurally generated characters with weighted trait distributions by province, city, family, era.
- [ ] Character generation rate scales with population.

#### 6.8 Event system full (§34)
- [ ] Event tiers: worldwide, state, factional, local (§34.1).
- [ ] Propagation models: geographic radial, route-following, institutional (§34.2).
- [ ] Narrator bias per intermediate source (§34.3).
- [ ] Three intelligence channels — operative / neutral / official (§34.4).
- [ ] Action-result gap (§34.5) and causation invisibility (§34.6).

### Exit criteria

Player can watch a continent's history unfold for 50 game-years without acting and see: dynasties rise and fall, wars start and end, plagues wipe out regions, trade routes shift. The autonomous world is believably alive.

### Systems referenced

§8, §9, §24, §26, §27, §31, §32, §33, §34.

---

## 7. Phase 4 — Rivals and the Society Layer

**Goal**: the player is no longer alone in the shadows.

### Deliverables

#### 7.1 Rival secret societies (§5)
- [ ] At least four named societies with distinct agendas and geographic bases (§5 named societies).
- [ ] Each society has its own operative network, financial infrastructure, host portfolio.
- [ ] Societies act on their own agendas, independent of the player's actions.

#### 7.2 Society fingerprints (§8.12)
- [ ] Every society has an operational signature — pattern of targets, methods, timing.
- [ ] Fingerprint library built by the player over time from observed events.
- [ ] UI to compare suspicious news events against known fingerprints.

#### 7.3 Counter-intelligence (§5, §14.6)
- [ ] Detecting rival operatives in the player's theatres.
- [ ] Investigation chains: a detected rival operative → who they report to → which coordinator → which lieutenant.
- [ ] Counter-operations: turn, neutralise, or feed false intelligence to rival operatives.

#### 7.4 False flag operations (§8.13)
- [ ] Player can disguise their operations as rival society fingerprints.
- [ ] Rivals can do the same to the player.
- [ ] Attribution misfires become a recurring strategic theme.

#### 7.5 Meeting other immortals (§5.5)
- [ ] Rare encounters with peers — cold peace, tentative cooperation, open shadow war.
- [ ] Dialogue and consequence modelling for these events.

#### 7.6 Shadow-figure system (§10)
- [ ] Three awareness levels of the player's existence (§10.1).
- [ ] Era-appropriate naming of the player's legend (§10.2).
- [ ] Chronicle threat: historians who piece together the pattern (§10.4).
- [ ] Hunters: individuals who actively seek the player (§10.5).

### Exit criteria

Player must balance building their machine with defending it against rival societies, identifying false flag operations, and managing their own legend across generations.

### Systems referenced

§5, §8.12, §8.13, §10, §14.6.

---

## 8. Phase 5 — Depth Systems

**Goal**: multi-generation play is no longer a survival exercise — it becomes a compounding one.

### Deliverables

#### 8.1 Memoirs system (§13, §30)
- [ ] Pattern library data model: archetypes, religions, ideologies, rivals, automations.
- [ ] Memoirs panel UI (§30) — era-themed journal on the table.
- [ ] Pattern match quality indicator (§30.2) with four thresholds.
- [ ] Automation engine: dispatched operations running without per-action player input.
- [ ] Stale pattern detection and warning.
- [ ] Regional dispatch (§13.3) for late-game coverage.

#### 8.2 Religion and ideology (§25)
- [ ] Religion data model (§25.1): doctrinal rigidity, institutional strength, popular depth, geographic distribution, reform potential, ecumenical openness.
- [ ] Religion lifecycle (§25.2): emergence, consolidation, dominance, fracture, decline.
- [ ] Ideology as parallel structure (§25.3): Stoicism, Confucianism, later ideologies.
- [ ] Manual-engagement requirement for new religions (§13.4) before automation unlocks.

#### 8.3 Owned entities (§20)
- [ ] Entity types: trading company, banking house, academy, monastery, guild, noble estate.
- [ ] Founding and acquiring entities.
- [ ] Proxy-structure beneficial ownership — player never on the paperwork.
- [ ] Entity event streams to the player.
- [ ] Entity longevity across political upheavals (§20.4).
- [ ] Entity-level corruption (§20.5).

#### 8.4 Dynastic loyalty (§21)
- [ ] Family tree data model with multi-generational tracking.
- [ ] Weighted inheritance based on the player's treatment of the family (§21.2).
- [ ] Family needs and loyalty maintenance loop (§21.3).
- [ ] Stats, training, underdog development (§21.4).
- [ ] Functional lieutenant specialisations mapped to family backgrounds (§21.5).
- [ ] Family decline and replacement (§21.6).

#### 8.5 Languages (§23)
- [ ] Language profiles per operative.
- [ ] Regional language requirements for effective operation.
- [ ] Language acquisition paths: tutor, immersion, self-study, family inheritance.
- [ ] Language evolution across eras (§23.5).
- [ ] Cultural tagging on Memoirs patterns — a Latin merchant pattern does not apply to an Arabic merchant.

#### 8.6 Mandates (§11)
- [ ] Directed objectives system — optional player-selectable long-term goals.
- [ ] Mandate categories (§11.2): ideological, territorial, institutional, succession, collapse-prevention.
- [ ] Emergent mandates (§11.3) — discovered through play rather than offered.

#### 8.7 Failure states (§12)
- [ ] Explicit game-ending failure conditions modelled and tested.
- [ ] Death in Ironman mode ends that playthrough with a chronicle seal.

### Exit criteria

A player who has run a 200-year session has built a multi-generational machine with dynastic lieutenants, owned entities that survived political upheaval, a deep Memoirs library, and a working identity portfolio.

### Systems referenced

§11, §12, §13, §20, §21, §23, §25, §30.

---

## 9. Phase 6 — Eras and Pivoting

**Goal**: the game supports the full 1000–2000+ year arc and the strategic move between civilisational centres.

### Deliverables

#### 9.1 Era progression (§6.2)
- [ ] All supported eras defined: Classical, Late Antique, Early Medieval, High Medieval, Renaissance, Early Modern, Modern.
- [ ] Era transitions: visual style changes, infrastructure changes, communication speed changes, language evolution.
- [ ] Era-appropriate map art, font, UI chrome, audio palette.

#### 9.2 Pivot mechanic (§6.3)
- [ ] Base-of-operations move (§22) as a strategic act, not a safety cycle.
- [ ] Pre-move preparation checklist (§22.2).
- [ ] Travel animation and map shift (§22.3).
- [ ] Transition window (§22.4) with reduced Memoirs reliability locally.
- [ ] Era-appropriate travel speeds (§22.5).

#### 9.3 Hundred generations (§6.5)
- [ ] Multi-century persistence stress-tested: save files from year 200 still load cleanly at year 1500.
- [ ] Performance optimisation for long-running simulations — procedural world state compression, low-fidelity AI for untouched regions.

#### 9.4 Weighted character generation across history (§8.11)
- [ ] Player's past actions write themselves into the next generation of affected populations.
- [ ] Trait distribution shifts over centuries in observable ways.

#### 9.5 City-to-global scale (§6.4)
- [ ] Player starts in one city with one host, ends controlling a network across continents.
- [ ] Growth arc validated by actual long-session playtesting.

### Exit criteria

A dedicated player can begin a new game in 500 BCE, play through to 1500 CE across multiple real-time sessions, and have the simulation remain coherent, performant, and interesting throughout.

### Systems referenced

§6, §8.11, §22.

---

## 10. Phase 7 — Polish and Onboarding

**Goal**: the game is ready for players who have never heard of it.

### Deliverables

#### 10.1 Table UI polish (§7.1)
- [ ] Era-themed table visuals: wax tablets, vellum, parchment, printed pages.
- [ ] Typography, animation, lighting — macOS Tahoe-inspired modern reference with period styling.
- [ ] Consistent component library: buttons, panels, toggles, dossiers.

#### 10.2 Map polish (§7.3)
- [ ] Era-appropriate map art per era, with smooth transitions.
- [ ] Zoom animations, hover reveals, proper contrast, readable labels at all zoom levels.

#### 10.3 Intelligence layer UI (§7.4, §8.10)
- [ ] All map intelligence layers toggleable — military, economic, famine, political, religious, rival fingerprints.
- [ ] Layer opacity, filtering, and search.

#### 10.4 Time controls (§7.5)
- [ ] Pause, play, fast forward, scheduled stop on events.
- [ ] Auto-pause on high-priority events (configurable).

#### 10.5 Public news (§7.7)
- [ ] News feed as a dedicated table element with era-appropriate styling.
- [ ] News calibration against operative reports (used by the two-reality system).

#### 10.6 Difficulty modes (§7.8)
- [ ] Standard vs. Ironman (§29).
- [ ] Optional extra difficulty modifiers — more aggressive rival societies, smaller starting resources.

#### 10.7 Onboarding by situation (§28)
- [ ] Fully scripted first session (§28.1).
- [ ] System-unlock sequence driven by organisational milestones (§28.2).
- [ ] Memoirs panel as living help system (§28.3).

#### 10.8 Save architecture (§29)
- [ ] Continuous autosave.
- [ ] Session continuity — quit and resume to exact state.
- [ ] Chronicle generation per session.
- [ ] Ironman enforcement.
- [ ] World persistence: prior playthroughs leave their entities, families, and Machine in the world for subsequent playthroughs.

#### 10.9 Accessibility
- [ ] Font scaling.
- [ ] Colour-blind safe palettes for all intelligence layers.
- [ ] Reduced-motion option.
- [ ] Keyboard navigation for every UI element.

#### 10.10 Audio
- [ ] Era-specific ambient audio palette.
- [ ] Event audio cues — subtle, not intrusive.
- [ ] Music: period-appropriate, looping, low-attention-demand.

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
