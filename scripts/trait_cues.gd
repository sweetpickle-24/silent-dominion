class_name TraitCues
extends RefCounted
## Qualitative phrase library for the §24 canonical trait set.
##
## Per §24.3 and §7.6 the player must NEVER see a raw trait number. The
## Dossier UI converts every 0-100 value into a short in-world phrase, and
## only shows traits that are genuinely notable (below 30 or above 70).
##
## Keys are the same StringNames the Actor resource exports.

# value < LOW_THRESHOLD  -> low cue
# value > HIGH_THRESHOLD -> high cue
# otherwise              -> nothing (trait is unremarkable)
const LOW_THRESHOLD: int  = 30
const HIGH_THRESHOLD: int = 70

const _CUES: Dictionary = {
	&"ambition": {
		"low":  "content in their present station",
		"high": "burns for a higher seat than they hold",
	},
	&"paranoia": {
		"low":  "trusts more easily than the times warrant",
		"high": "sees plots in every quiet corner",
	},
	&"loyalty": {
		"low":  "their fealty has a known price",
		"high": "unshakeable in their allegiance",
	},
	&"piety": {
		"low":  "keeps the gods at arm's length",
		"high": "devout to a degree that brooks no compromise",
	},
	&"intellect": {
		"low":  "slow to see what others see at once",
		"high": "of a quick and subtle mind",
	},
	&"greed": {
		"low":  "silver and gold move them little",
		"high": "has an appetite that will be hard to satisfy",
	},
	&"ruthlessness": {
		"low":  "stays their hand where another would not",
		"high": "would spill blood without a second breath",
	},
	&"curiosity": {
		"low":  "incurious; no appetite for the new",
		"high": "asks questions that are not always welcome",
	},
	&"resilience": {
		"low":  "breaks early under strain",
		"high": "absorbs every blow and still stands",
	},
	&"charisma": {
		"low":  "leaves no warmth in a room",
		"high": "men follow where they lead, and gladly",
	},
}


## Return a short in-world phrase for a given trait value, or empty string
## if the value is not notable (30-70 inclusive).
static func phrase_for(trait_key: StringName, value: int) -> String:
	if not _CUES.has(trait_key):
		return ""
	if value < LOW_THRESHOLD:
		return String(_CUES[trait_key]["low"])
	if value > HIGH_THRESHOLD:
		return String(_CUES[trait_key]["high"])
	return ""


## Collect every notable trait for an Actor as an array of phrases,
## ordered by how extreme the value is (most extreme first).
static func notable_phrases(actor: Actor) -> Array[String]:
	var scored: Array = []
	for k in Actor.TRAIT_KEYS:
		var v: int = actor.get_trait(k)
		var phrase: String = phrase_for(k, v)
		if phrase.is_empty():
			continue
		var distance: int = abs(v - 50)
		scored.append({ "phrase": phrase, "distance": distance })

	scored.sort_custom(func(a, b): return int(a["distance"]) > int(b["distance"]))

	var out: Array[String] = []
	for entry in scored:
		out.append(String(entry["phrase"]))
	return out


static func role_title(role: Actor.Role) -> String:
	match role:
		Actor.Role.RULER:       return "Ruler"
		Actor.Role.HEIR:        return "Heir"
		Actor.Role.GENERAL:     return "General"
		Actor.Role.PRIEST:      return "Priest"
		Actor.Role.MERCHANT:    return "Merchant"
		Actor.Role.ADVISOR:     return "Advisor"
		Actor.Role.PHILOSOPHER: return "Philosopher"
		Actor.Role.AGENT:       return "Agent"
		_:                      return "Commoner"
