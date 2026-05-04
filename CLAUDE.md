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

## When uncertain

If a code change requires interpreting design intent and the vault is ambiguous or silent, **ask Vladyslav** rather than inferring. Inferring design from incomplete notes is how locked decisions get accidentally violated.