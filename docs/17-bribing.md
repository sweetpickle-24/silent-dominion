# 17. Bribing — Purchased Loyalty

Bribery is one of the most versatile tools in the player's action palette and one of the most dangerous if handled poorly.

It is **never** a simple 'pay X gold, get Y outcome' transaction. Every bribe is a relationship event with a susceptibility calculation, a structural decision, a financial footprint, and a failure mode that can be worse than not trying.

## 17.1 Susceptibility assessment

Before any bribe is attempted, the system evaluates the target's **susceptibility profile** derived from their current traits and circumstances. Susceptibility is not a single number — it is specific to the type of offer being made.

> A target may be highly susceptible to career advancement offers but completely resistant to direct payment.

The [Memoirs system](./13-memoirs/README.md) stores bribery profiles so repeat approaches to similar character types can be automated.

### Susceptibility by profile

| **Target profile** | **Susceptibility** | **Best approach** |
| --- | --- | --- |
| **High greed + financial pressure** | High to direct payment | Straightforward offer. Time it to a moment of maximum financial stress for best results. |
| **High ambition + low current status** | High to career advancement | Offer introductions, patronage, or promotion rather than money. Framing as opportunity rather than purchase. |
| **High principle + stable position** | Low to direct payment, possible to information trade | Cannot be bought but may trade favours. Offer something they want — intelligence, access, a rival discredited. |
| **High paranoia** | Negative — offer increases suspicion | Do not attempt direct bribery. An offer reads as a trap. Work through a trusted intermediary they already respect. |
| **Loyal to a specific patron** | Low unless patron relationship is strained | Destabilise the patron relationship first. Make the loyalty feel unrewarded. Then the susceptibility rises. |

## 17.2 Offer types

The player selects the **structure of the offer**, which determines the ongoing relationship it creates and the risks it carries.

- **One-time payment** — buys a single action. Both parties want to forget it happened. Low ongoing risk but zero ongoing value. The target owes nothing after.
- **Ongoing retainer** — creates a dependent. The target now needs the payments to continue and has something to lose if the relationship ends. More valuable over time but more dangerous — a dependent who decides to leverage what they know is a serious threat.
- **Career favour** — advancement, protection, introductions. No direct money changes hands. Harder to prove, lower exposure. The target may not even frame it as a bribe.
- **Information trade** — give the target something they want — intelligence about a rival, advance warning of a threat, a secret they can use. Creates mutual vulnerability. Both parties now hold leverage over each other.
- **Gift and social favour** — lowest direct exposure. Embedded in normal social relationships. Slowest to produce results but leaves the smallest trail.

## 17.3 Transaction structure and financial routing

Once an offer type is selected, the player chooses how the payment moves. This decision is made through the [financial network system](./16-financial-networks.md) — the same routing options apply.

- **Direct payments** are cheapest in capacity but highest in exposure.
- **Multi-hop routing** is most discreet but slow and expensive.
- The discretion level of the transaction is a key input into the failure mode calculation.

## 17.4 Failure modes

A bribe does not simply succeed or fail. The outcome is drawn from a probability table that reflects susceptibility, offer quality, and transaction discretion. The player sees a rough risk assessment before committing but **never exact probabilities.**

| **Outcome** | **What happens** | **Consequence** |
| --- | --- | --- |
| **Clean success** | Target accepts, says nothing, delivers | Ideal. No footprint beyond the financial transaction. |
| **Messy success** | Target accepts but mentions the approach to someone | Operation succeeds but a rumour enters circulation. Someone knows a bribe was offered in this context. |
| **Silent failure** | Target declines, says nothing | Safe. The attempt cost resources but produced no new risk. |
| **Loud failure** | Target declines and reports it or uses it as leverage | The worst outcome. Creates information about the player's network. The target now knows someone tried to buy them and has a rough sense of the player's interests. |
| **Counter-leveraged** | Target accepts the information about the approach and sells it to a rival society | A rival now knows the player's target, their offer type, and the approximate financial routing used. |

## 17.5 Dependents and retainer management

Every active retainer relationship is a **dependent** in the organisation's ledger. Dependents are managed through the coordinator layer — payments are routed, requests are handled, the relationship is maintained.

A dependent who stops receiving payments becomes a **liability**: they feel abandoned, they may become resentful, and they hold knowledge of the organisation that they are no longer incentivised to protect.

- The coordinator layer **flags dependents at risk** — payments overdue, circumstances changed, patron relationship shifting.
- A dependent who turns does not simply stop working — they become an **active threat** who may report, expose, or sell what they know.
- Dependents can be cleanly retired by **gradually reducing their role**, making the relationship feel naturally concluded rather than cut.
- The longer a dependent has been active, the more they know and the more dangerous they are if they turn.
