extends Node
## Autoloaded as `Fingerprints`. The player's cumulative knowledge of
## rival secret societies, per §8.12. Separate from `Rivals` on
## purpose: `Rivals` holds ground truth; `Fingerprints` holds only
## what the player has learned. UI reads from here.
##
## The investigation chain (§8.12) has five levels:
##   0 — Signal:     the anomaly is visible in news (automatic).
##   1 — Mechanism:  the event was deliberate, not natural.
##   2 — Actor:      a specific local actor or institution is implicated.
##   3 — Pattern:    three or more related ops share a hidden hand.
##   4 — Fingerprint: the hidden hand is matched to a known society.
##
## An `op` is a Dictionary in Rivals.op_log. We key investigation
## state by op_id (String).

signal op_level_changed(op_id: String, level: int)
signal society_identified(society_id: StringName, confirmation: int)

const LEVEL_SIGNAL: int     = 0
const LEVEL_MECHANISM: int  = 1
const LEVEL_ACTOR: int      = 2
const LEVEL_PATTERN: int    = 3
const LEVEL_FINGERPRINT: int = 4

# op_id (String) -> level (int 0..4)
var op_levels: Dictionary = {}

# society_id (StringName) -> confirmation score 0..100.
# 0   unknown
# 25  glimpsed (one Level 2 match)
# 50  provisional (multiple Level 2 + one Level 3)
# 75  confirmed (Level 4 match attempted once, succeeded)
# 100 catalogued (seen across multiple kingdoms or eras)
var society_confirmation: Dictionary = {}


func _ready() -> void:
	DevLogger.write("Fingerprints: ready")
	pass


# --- Public API: levels ---------------------------------------------------

func level_for(op_id: String) -> int:
	return int(op_levels.get(op_id, LEVEL_SIGNAL))


func set_level(op_id: String, level: int) -> void:
	if op_id.is_empty():
		return
	var clamped: int = clampi(level, LEVEL_SIGNAL, LEVEL_FINGERPRINT)
	var prev: int = level_for(op_id)
	if clamped <= prev:
		return
	op_levels[op_id] = clamped
	op_level_changed.emit(op_id, clamped)


## Advance the most recent un-levelled op in a kingdom by one step.
## Returns the op the investigation was applied to, or an empty dict
## if nothing plausible was available. Used by `investigate_anomaly`.
func advance_one_in(kingdom_id: String, min_level: int = LEVEL_SIGNAL) -> Dictionary:
	var ops: Array = Rivals.recent_ops_in(kingdom_id, 900)
	# Prefer ops already at min_level but below 2 — we are walking
	# Mechanism → Actor first, Pattern is a separate action.
	ops.reverse()  # most recent first
	for op in ops:
		var id: String = String(op.get("op_id", ""))
		if id.is_empty():
			continue
		var cur: int = level_for(id)
		if cur >= LEVEL_ACTOR:
			continue
		if cur < min_level:
			continue
		set_level(id, cur + 1)
		return op
	# Fall back: try from level 0.
	for op in ops:
		var id: String = String(op.get("op_id", ""))
		if id.is_empty():
			continue
		var cur: int = level_for(id)
		if cur >= LEVEL_ACTOR:
			continue
		set_level(id, cur + 1)
		return op
	return {}


## Try to lift multiple Level 2 ops in the kingdom to Level 3 by
## cross-referencing them. Requires at least three Level-2 ops
## sharing a signature. Returns the society id if a pattern emerged,
## else &"".
func cross_reference(kingdom_id: String) -> StringName:
	var ops: Array = Rivals.recent_ops_in(kingdom_id, 1080)
	var by_sig: Dictionary = {}  # String sig -> Array[op]
	for op in ops:
		if level_for(String(op.get("op_id", ""))) < LEVEL_ACTOR:
			continue
		var sig: String = String(op.get("rival_signature", ""))
		if sig.is_empty():
			continue
		if not by_sig.has(sig):
			by_sig[sig] = []
		(by_sig[sig] as Array).append(op)
	var best_sig: String = ""
	var best_n: int = 0
	for sig in by_sig:
		var n: int = (by_sig[sig] as Array).size()
		if n > best_n:
			best_n = n
			best_sig = String(sig)
	if best_n < 3 or best_sig.is_empty():
		return &""
	for op in by_sig[best_sig]:
		set_level(String(op.get("op_id", "")), LEVEL_PATTERN)
	var sid: StringName = StringName(best_sig)
	bump_confirmation(sid, 15)
	return sid


## Commit a Level 4 identification on the player's best-pattern
## society in the kingdom. Fails quietly if nothing has reached
## Level 3 yet. Returns the society id on success.
func match_fingerprint(kingdom_id: String) -> StringName:
	var ops: Array = Rivals.recent_ops_in(kingdom_id, 1440)
	var candidates: Dictionary = {}  # sig -> count at level>=3
	for op in ops:
		if level_for(String(op.get("op_id", ""))) < LEVEL_PATTERN:
			continue
		var sig: String = String(op.get("rival_signature", ""))
		candidates[sig] = int(candidates.get(sig, 0)) + 1
	var best_sig: String = ""
	var best_n: int = 0
	for sig in candidates:
		if int(candidates[sig]) > best_n:
			best_n = int(candidates[sig])
			best_sig = String(sig)
	if best_sig.is_empty():
		return &""
	for op in ops:
		if String(op.get("rival_signature", "")) != best_sig:
			continue
		if level_for(String(op.get("op_id", ""))) >= LEVEL_PATTERN:
			set_level(String(op.get("op_id", "")), LEVEL_FINGERPRINT)
	var sid: StringName = StringName(best_sig)
	bump_confirmation(sid, 40)
	return sid


# --- Public API: society confirmation -------------------------------------

func confirmation_for(society_id: StringName) -> int:
	return int(society_confirmation.get(society_id, 0))


func bump_confirmation(society_id: StringName, delta: int) -> void:
	var prev: int = confirmation_for(society_id)
	var next: int = clampi(prev + delta, 0, 100)
	if next == prev:
		return
	society_confirmation[society_id] = next
	society_identified.emit(society_id, next)


## Whether the player is allowed to render the society's name on a
## given op. Mirrors the investigation-level gate: below Level 4 the
## op is attributed vaguely ("an unrecognised hand"). At Level 4 we
## render the actual name.
func label_for_op(op: Dictionary) -> String:
	var level: int = level_for(String(op.get("op_id", "")))
	match level:
		LEVEL_SIGNAL:     return "noise"
		LEVEL_MECHANISM:  return "deliberate act"
		LEVEL_ACTOR:      return "local actor implicated"
		LEVEL_PATTERN:    return "unrecognised organisation"
		LEVEL_FINGERPRINT:
			var sid: StringName = StringName(String(op.get("rival_signature", "")))
			var soc: RivalSociety = Rivals.get_society(sid)
			return soc.display_name if soc != null else "known hand"
		_: return ""


# --- Society index (for UI listings) --------------------------------------

func confirmed_societies() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for sid in society_confirmation:
		var soc: RivalSociety = Rivals.get_society(sid)
		if soc == null:
			continue
		out.append({
			"id":            sid,
			"display_name":  soc.display_name,
			"confirmation":  confirmation_for(sid),
			"philosophy":    soc.philosophy,
		})
	out.sort_custom(func(a, b): return int(a.confirmation) > int(b.confirmation))
	return out


# --- Save / load ----------------------------------------------------------

func snapshot() -> Dictionary:
	var conf_out: Dictionary = {}
	for k in society_confirmation:
		conf_out[String(k)] = int(society_confirmation[k])
	return {
		"op_levels":            op_levels.duplicate(true),
		"society_confirmation": conf_out,
	}


func restore(d: Dictionary) -> void:
	op_levels.clear()
	society_confirmation.clear()
	var ol: Variant = d.get("op_levels", {})
	if ol is Dictionary:
		for k in ol:
			op_levels[String(k)] = int(ol[k])
	var sc: Variant = d.get("society_confirmation", {})
	if sc is Dictionary:
		for k in sc:
			society_confirmation[StringName(String(k))] = int(sc[k])
