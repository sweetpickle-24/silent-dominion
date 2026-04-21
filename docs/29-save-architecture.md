# 29. Save Architecture

The save system is a **design decision with significant gameplay implications.** A game where the player can freely reload any failed operation undermines the two-reality system, the corruption system, the intelligence recheck system, and every other mechanic that depends on consequences being real.

**The save architecture must reinforce the game's design principles rather than allowing them to be bypassed.**

## 29.1 The two save modes

| **Mode** | **Save behaviour** | **Design intent** |
| --- | --- | --- |
| **Standard** | Autosaves every game-month. Player can save manually at any time. Player can reload to any prior save. | Accessible for new players and those who want to explore without permanent consequences. The game's systems are still present but their teeth are optional. |
| **Ironman** | Autosaves every game-day. No manual saves. No reload. The session cannot be rewound. | **The intended experience for the full game design.** Every action has permanent consequences. The intelligence and corruption systems function as designed because misfires cannot be undone. Death is final. |

## 29.2 Session continuity

Silent Dominion is designed for sessions of variable length — from an hour of reading reports and making small decisions to a multi-hour stretch through a major historical period.

The save system accommodates this through **continuous autosaving** rather than save points. The player can quit at any moment and return to exactly where they left the table.

### Rules

- The **table state** — every document, every map annotation, every open dossier — is saved as part of the session state.
- **Operations in progress** are saved mid-execution — a bribe that was dispatched but not yet resolved continues resolving when the player returns.
- The player's **Memoirs library, identity portfolio, financial network state, and organisation structure** are all part of the persistent save.
- A **chronicle entry** is generated at the end of each session summarising the period just played — written in the voice of a future historian describing what occurred.

## 29.3 Death and session end in Ironman mode

In Ironman mode, the player's death is the **end of that playthrough.** The chronicle is sealed. A final entry describes how the immortal's long existence ended — who found them, in what circumstances, what the world looked like at the moment of their death.

The player can then begin a **new playthrough, in the same world if they choose**, as a new immortal entering a world already shaped by the previous player's centuries of activity. The prior playthrough's Machine, entities, and families persist as part of the new world's starting state.
