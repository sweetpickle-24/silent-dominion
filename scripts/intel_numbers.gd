class_name IntelNumbers
extends RefCounted
## Intelligence-gated numeric display (§15 intelligence fidelity).
##
## The game normally renders only qualitative phrases ("a handsome share",
## "a standing army of real weight"). Where a subsystem wants to surface
## the underlying figure too, it routes through this helper so the number
## the player sees is gated by the kingdom's Picture coverage:
##
##   coverage 0%       → "?"
##   coverage 1-25%    → wide range       ("somewhere between 40 and 120")
##   coverage 26-50%   → rough estimate   ("roughly 80")
##   coverage 51-75%   → narrow estimate  ("about 82")
##   coverage 76-99%   → tight range      ("between 80 and 88")
##   coverage 100%     → exact figure
##
## Coverage is sourced from `Picture.score_for(kingdom_id)` at the call
## site — this module is stateless so it can be used from Resources.

enum Tier { UNKNOWN, WIDE, ROUGH, NARROW, TIGHT, EXACT }

# Half-width of the uncertainty window expressed as a fraction of the
# true value. Applied around the true figure, then rounded to a step
# whose coarseness matches the tier.
const _HALF_WIDTH: Dictionary = {
	Tier.WIDE:   0.50,
	Tier.ROUGH:  0.30,
	Tier.NARROW: 0.12,
	Tier.TIGHT:  0.06,
}


## Tier for a coverage score 0..100.
static func tier_for(coverage: int) -> int:
	if coverage <= 0:   return Tier.UNKNOWN
	if coverage < 26:   return Tier.WIDE
	if coverage < 51:   return Tier.ROUGH
	if coverage < 76:   return Tier.NARROW
	if coverage < 100:  return Tier.TIGHT
	return Tier.EXACT


## Short tier label for diagnostic / tooltip use. Never appears
## embedded in a rendered sentence.
static func tier_label(coverage: int) -> String:
	match tier_for(coverage):
		Tier.UNKNOWN: return "unknown"
		Tier.WIDE:    return "wide range"
		Tier.ROUGH:   return "rough estimate"
		Tier.NARROW:  return "narrow estimate"
		Tier.TIGHT:   return "tight range"
		Tier.EXACT:   return "exact"
	return ""


## Generic unsigned amount. `unit` is an optional word rendered after the
## figure ("silver", "men", "bushels"). Negative values are clamped up
## to zero — nothing in this game shows a negative treasury as -X.
static func amount_display(true_value: float, coverage: int, unit: String = "") -> String:
	var t: int = tier_for(coverage)
	if t == Tier.UNKNOWN:
		return "?" if unit.is_empty() else "? " + unit
	var v: float = maxf(0.0, true_value)
	if t == Tier.EXACT:
		return _join_unit(_with_commas(int(round(v))), unit)
	var lo_i: int
	var hi_i: int
	var pair: Array = _bounded_range(v, t)
	lo_i = int(pair[0])
	hi_i = int(pair[1])
	if t == Tier.NARROW or t == Tier.TIGHT:
		var mid: int = int(round((float(lo_i) + float(hi_i)) * 0.5))
		var prefix: String = "about" if t == Tier.TIGHT else "roughly"
		return "%s %s" % [prefix, _join_unit(_with_commas(mid), unit)]
	var lead: String = "somewhere between" if t == Tier.WIDE else "between"
	return "%s %s and %s" % [lead, _with_commas(lo_i), _join_unit(_with_commas(hi_i), unit)]


## Signed score display (e.g. the actor relationship scale -100..100).
## Below-neutral values come through as "-17", above as "+17", zero as
## "0". Ranges straddle sign cleanly.
static func score_display(true_value: int, coverage: int, lo_bound: int = -100, hi_bound: int = 100) -> String:
	var t: int = tier_for(coverage)
	if t == Tier.UNKNOWN:
		return "?"
	if t == Tier.EXACT:
		return _signed(true_value)
	# Half-width in absolute score units; picked so a full-width span
	# at WIDE still carries readable information.
	var hw_map: Dictionary = {
		Tier.WIDE:   40,
		Tier.ROUGH:  22,
		Tier.NARROW: 12,
		Tier.TIGHT:  6,
	}
	var hw: int = int(hw_map.get(t, 10))
	var step: int = 5 if t == Tier.WIDE else (3 if t == Tier.ROUGH else 2)
	var lo_r: int = int(floor(float(true_value - hw) / float(step))) * step
	var hi_r: int = int(ceil(float(true_value + hw) / float(step))) * step
	lo_r = clampi(lo_r, lo_bound, hi_bound)
	hi_r = clampi(hi_r, lo_bound, hi_bound)
	if lo_r > hi_r:
		lo_r = hi_r
	if t == Tier.NARROW or t == Tier.TIGHT:
		var mid: int = int(round((float(lo_r) + float(hi_r)) * 0.5))
		var prefix: String = "about" if t == Tier.TIGHT else "roughly"
		return "%s %s" % [prefix, _signed(mid)]
	var lead: String = "somewhere between" if t == Tier.WIDE else "between"
	return "%s %s and %s" % [lead, _signed(lo_r), _signed(hi_r)]


## Convenience for Province.population / Army.size — stored internally
## in thousands, rendered to the player in literal men / souls. Pass
## the raw field (e.g. 220 → 220 000 souls).
static func thousands_display(value_k: int, coverage: int, unit: String = "") -> String:
	return amount_display(float(value_k) * 1000.0, coverage, unit)


# --- Internals -------------------------------------------------------------

static func _bounded_range(v: float, t: int) -> Array:
	var hw: float = float(_HALF_WIDTH[t])
	var lo_raw: float = maxf(0.0, v * (1.0 - hw))
	var hi_raw: float = v * (1.0 + hw)
	# Always keep at least a small absolute floor so tiny values
	# still carry a visible window (e.g. 4 → 2..6, not 4..4).
	var min_half: float = maxf(1.0, v * 0.05)
	if (hi_raw - lo_raw) < 2.0 * min_half:
		lo_raw = maxf(0.0, v - min_half)
		hi_raw = v + min_half
	var step: int = _rounding_step(hi_raw, t)
	var lo_i: int = int(floor(lo_raw / float(step))) * step
	var hi_i: int = int(ceil(hi_raw / float(step))) * step
	if lo_i < 0:
		lo_i = 0
	if hi_i <= lo_i:
		hi_i = lo_i + step
	return [lo_i, hi_i]


static func _rounding_step(magnitude: float, t: int) -> int:
	var base: int = 1
	if magnitude >= 100000.0: base = 10000
	elif magnitude >= 10000.0: base = 1000
	elif magnitude >= 1000.0:  base = 100
	elif magnitude >= 100.0:   base = 10
	else:                      base = 1
	match t:
		Tier.WIDE:   return maxi(base * 5, 1)
		Tier.ROUGH:  return maxi(base * 2, 1)
		Tier.NARROW: return maxi(base, 1)
		Tier.TIGHT:  return maxi(int(float(base) * 0.5), 1)
	return 1


static func _with_commas(n: int) -> String:
	var neg: bool = n < 0
	var s: String = str(absi(n))
	var out: String = ""
	var count: int = 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	if neg:
		out = "-" + out
	return out


static func _signed(n: int) -> String:
	if n > 0: return "+%d" % n
	if n < 0: return "%d" % n
	return "0"


static func _join_unit(num: String, unit: String) -> String:
	if unit.is_empty():
		return num
	return "%s %s" % [num, unit]
