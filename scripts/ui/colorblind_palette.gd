class_name ColorblindPalette
extends RefCounted
## Static utility. §10.9 accessibility: remap arbitrary `Color`s
## into a palette friendly to deuteranopia / protanopia / tritanopia,
## using a lightweight Brettel/Viénot-style approximation. Also
## exposes a small set of named overlay colours the map renderer
## can use directly instead of hand-mixing hex values.
##
## Off-mode is the identity — existing colour work is untouched.

const MODE_OFF: StringName         = &"off"
const MODE_DEUTERANOPIA: StringName = &"deuteranopia"
const MODE_PROTANOPIA: StringName   = &"protanopia"
const MODE_TRITANOPIA: StringName   = &"tritanopia"


static func mode() -> StringName:
	if Prefs == null:
		return MODE_OFF
	if not ("colorblind_mode" in Prefs):
		return MODE_OFF
	return StringName(String(Prefs.colorblind_mode))


static func enabled() -> bool:
	return mode() != MODE_OFF


## Pass-through remap. The caller can always call this; off-mode
## returns the input unmodified, so it is cheap to sprinkle through
## render code without gating each call site.
##
## Named `remap_color` (not `remap`) to avoid shadowing GDScript's
## built-in `remap(value, istart, istop, ostart, ostop)` scalar lerp.
static func remap_color(c: Color, m: StringName = &"") -> Color:
	var use: StringName = m if m != &"" else mode()
	if use == MODE_OFF:
		return c
	return _simulate(c, use)


## Named overlay colours. Chosen so adjacent categories stay
## distinguishable in every supported mode. Callers pass a symbolic
## key instead of a hex; the palette picks the variant that works
## for the active mode.
static func named(kind: StringName) -> Color:
	var base: Color = _base_named(kind)
	return remap_color(base, mode())


# --- Internals -------------------------------------------------------------

static func _base_named(kind: StringName) -> Color:
	match String(kind):
		"unrest":       return Color(0.86, 0.26, 0.22)
		"prosperity":   return Color(0.23, 0.55, 0.38)
		"fidelity":     return Color(0.27, 0.55, 0.80)
		"famine_low":   return Color(0.94, 0.82, 0.38)
		"famine_mid":   return Color(0.90, 0.58, 0.26)
		"famine_high":  return Color(0.74, 0.22, 0.18)
		"religion_a":   return Color(0.58, 0.34, 0.78)
		"religion_b":   return Color(0.40, 0.60, 0.72)
		"religion_c":   return Color(0.72, 0.48, 0.30)
		"religion_d":   return Color(0.46, 0.66, 0.44)
		"religion_e":   return Color(0.84, 0.50, 0.66)
		"rival_a":      return Color(0.85, 0.34, 0.20)
		"rival_b":      return Color(0.24, 0.55, 0.72)
		"rival_c":      return Color(0.68, 0.30, 0.60)
		"rival_d":      return Color(0.36, 0.56, 0.30)
		"political_a":  return Color(0.28, 0.45, 0.70)
		"political_b":  return Color(0.78, 0.44, 0.22)
		"political_c":  return Color(0.55, 0.27, 0.58)
		"political_d":  return Color(0.30, 0.55, 0.48)
		"coverage":     return Color(0.96, 0.76, 0.26)
		_:              return Color(0.60, 0.60, 0.60)


## Lightweight simulation. Converts to a pseudo-LMS space, zeroes
## the confused channel per mode, blends back. Not photometrically
## accurate but visibly separates the troublesome category pairs
## (red vs green, blue vs yellow) which is all we need for a map
## overlay.
static func _simulate(c: Color, m: StringName) -> Color:
	var r: float = c.r
	var g: float = c.g
	var b: float = c.b
	var nr: float = r
	var ng: float = g
	var nb: float = b
	match String(m):
		"deuteranopia":
			ng = 0.625 * r + 0.375 * b
			nb = 0.30 * r + 0.70 * b
		"protanopia":
			nr = 0.567 * g + 0.433 * b
			ng = 0.558 * r + 0.442 * b
		"tritanopia":
			nb = 0.30 * r + 0.70 * g
			ng = 0.50 * r + 0.50 * g
	# Preserve overall luminosity so "dark" stays dark.
	var lum_src: float = 0.299 * r + 0.587 * g + 0.114 * b
	var lum_dst: float = 0.299 * nr + 0.587 * ng + 0.114 * nb
	var lum_correction: float = 0.0
	if lum_dst > 0.001:
		lum_correction = lum_src - lum_dst
	return Color(
		clampf(nr + lum_correction, 0.0, 1.0),
		clampf(ng + lum_correction, 0.0, 1.0),
		clampf(nb + lum_correction, 0.0, 1.0),
		c.a
	)
