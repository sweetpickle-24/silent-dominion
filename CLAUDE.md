# Claude Code — Silent Dominion Protocol

You are working on Silent Dominion, a Godot game. This file auto-loads every session. Read it fully before doing anything.

## Two folders, two roles

**Code workspace (this folder):** `/Users/vladyslav/Documents/GitHub/silentdominion/`
- You edit, commit, and push here.
- Godot opens this folder. Anything you change here, Godot sees.

**Design vault (READ-ONLY):** `/Users/vladyslav/Desktop/silent-dominion/`
- Obsidian vault. Single source of truth for game design.
- You may READ any file in this folder for context.
- You may NEVER create, edit, rename, move, or delete anything in this folder.
- If a design file needs to change, surface the suggestion in chat. Vladyslav edits the vault manually in Obsidian.

## Startup protocol (every session)

1. Read `/Users/vladyslav/Desktop/silent-dominion/_claude/INSTRUCTIONS.md` — the master design protocol.
2. Read `/Users/vladyslav/Desktop/silent-dominion/_claude/game-overview.md` — pitch, pillars, current scope.
3. Read `/Users/vladyslav/Desktop/silent-dominion/_claude/design-principles.md` — the rules used to evaluate design choices.
4. If Vladyslav mentions a specific system, mechanic, or content piece, read the relevant file in the vault's `design/` or `content/` folder BEFORE writing or changing code.
5. Briefly acknowledge what you loaded (one or two sentences) and wait for instruction.

## Working principles

- **Ground code in the vault.** Before implementing a system, read the corresponding design note. Don't infer design intent from code or general knowledge — the vault is authoritative.
- **Locked decisions are locked.** If a code change would contradict a `decisions/` entry marked `status: locked` or a principle in `design-principles.md`, flag it before proceeding. Do not silently override.
- **Push back when warranted.** You are a collaborator, not a yes-machine. If a request contradicts vault state or the GDD (`silent_dominion_gdd_v18.docx.md`), say so.
- **Distinguish draft from locked.** If a vault note is `status: draft`, treat it as exploratory — implementations may need adjustment as the design firms up. Flag the uncertainty.
- **Ask before structural changes.** Renaming directories, restructuring scenes, or large refactors require explicit confirmation.
- **Be honest about gaps.** If the vault doesn't cover a system you'd need to implement, say so and ask. Don't invent design.

## Git discipline

- Use feature branches for non-trivial changes. Don't push directly to `main` unless asked.
- Commit messages should be specific. When implementing a locked decision, reference it: `Implements decision: 2026-04-12-combat-stamina-system`.
- Never run `git reset --hard`, force-push, or delete branches without explicit confirmation.
- Pull before starting a session. Confirm clean working tree before large changes.

## Godot-specific notes

- `.tscn` and `.tres` files are text but have UID references and structural quirks. Edit them programmatically only when necessary; prefer changes in `.gd` scripts where possible.
- `project.godot` is sensitive. Don't edit unless asked.
- If a change touches scenes or resources, mention it explicitly so Vladyslav can check Godot reloaded cleanly.

## Flag-first protocol for locked-decision contradictions

When implementation hits a friction point with a locked decision, the protocol is: **flag first, implement after approval.** This section exists because Steps 2 and 3 of the Phase 1 rebuild produced three deviations that were implemented before being flagged. The pattern that worked (and is now required) emerged in Step 3's later checkpoints.

### What counts as a contradiction

A non-exhaustive list:

- The locked decision specifies a **code shape** (constants, classes, method signatures, file paths, autoload names) that the language or framework rejects at parse time or runtime.
- The locked decision specifies an **API surface** (parameter names, return types, behaviour) that an implementation alternative would change.
- The locked decision specifies a **file or folder structure** that hits a tooling or engine constraint.
- The locked decision specifies a **behavioural rule** (e.g. "no cross-mechanic state access", "signals for local UI only") that an implementation expedient would violate.

### When to flag

Before any code is written or edited. The flagging happens **in chat**, not in commit messages, not in code comments, not in deviation records. If Claude Code is mid-implementation and hits a contradiction it didn't see coming, it **stops, reports, and waits** — even if the implementation is "almost done."

### How to flag

Every flag includes four pieces:

1. **The actual error message or constraint**, verbatim where possible (copy-paste the Godot output, the GDScript parse error, the runtime exception).
2. **The locked decision being contradicted** — filename and section (e.g. "B4 `b4-event-bus-implementation.md` line ~80, `const DELIVERY_MODE`").
3. **At least two alternative approaches** that don't contradict the locked decision. If none exist, an explicit statement that none were found and what was searched.
4. **An explicit ask for approval** before proceeding with any alternative.

### What not to do

These are the failure modes that have occurred:

- **"Implement the workaround, then document it as a deviation."** This was the Step 2 EventBase pattern (`const` changed to methods, deviation record written after). The deviation record is fine; the implement-first sequencing is not.
- **"Change a locked API surface to make implementation easier."** This was the Step 3 Checkpoint A `WorldView.snapshot(time_keeper, world_registry)` parameter change. Locked API surfaces are part of the contract — changing them requires approval, not convenience.
- **"Edit `project.godot` or other config files without approval."** Even if the change seems mechanical (autoload reorder, plugin enable), config edits propagate. The `.claude/settings.json` ask-list covers `project.godot`, `CLAUDE.md`, and `.claude/settings.json` itself.

### The pattern that works

1. Hit a friction point (parse error, runtime error, locked-spec contradiction).
2. **Stop. Don't implement.**
3. Report in chat with the four pieces from "How to flag" above.
4. Wait for explicit approval ("yes, do option B" or "let's revert and try X").
5. Implement the approved approach.
6. If the approved approach deviates from a locked decision, note the deviation in the commit message body. Vladyslav records it formally in the vault.

### Settings-file integrity

The `.claude/settings.json` `ask` patterns for `project.godot`, `CLAUDE.md`, and `.claude/settings.json` itself should be verified before each step. Path patterns must use glob syntax (`**/project.godot`) to match regardless of working directory. If a pattern isn't triggering when expected, flag it as a separate issue.

## When uncertain

If a code change requires interpreting design intent and the vault is ambiguous or silent, **ask Vladyslav** rather than inferring. Inferring design from incomplete notes is how locked decisions get accidentally violated.