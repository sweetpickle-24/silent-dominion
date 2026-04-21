# 12. Failure States

There is no game over screen. But there are states of degradation that functionally end a playthrough's momentum and require the player to rebuild from near-zero.

| **Failure state** | **What causes it** | **Recovery path** |
| --- | --- | --- |
| **Network collapse** | Too many hosts burned in quick succession; exposure maxed | Go completely dark for 20–50 years; rebuild with a single low-profile proxy |
| **Rival domination** | A rival society achieves their objective while you were occupied elsewhere | Identify and disrupt their achievement before it locks in; may require temporary cooperation with a third society |
| **Ideological capture** | The dominant idea of an era becomes actively hostile to shadow manipulation | Wait for the cycle to turn; invest in the movement that will eventually challenge it |
| **The Exposed state** | Exposure reaches 86–100; multiple factions are actively hunting your footprint | Betray every active host simultaneously to erase your trail; accept decades of impotence |
| **Physical death** | Exposure is maximum AND the player is in a region with active witch trials, inquisition, or a ruler who has identified them personally | There is no recovery. This is the only true game over. |

## Design intent

- Every failure state except physical death has a **recovery path.**
- Recovery paths are costly in time and reduced ambition, but they preserve the playthrough.
- Ironman mode ([§29](./29-save-architecture.md)) makes these consequences permanent and non-reloadable.
