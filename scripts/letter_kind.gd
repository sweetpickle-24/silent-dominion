class_name LetterKind
extends Resource
## Static-only helper: maps a Letter.kind StringName to a badge
## color and a short label phrase. Used by the inbox and memoirs
## views to render a small colored wax dot next to each letter so
## the player can skim correspondence at a glance.

# Kind -> Color (wax dot). Stable across light/dark so the color
# alone communicates the kind even without the label.
const COLOR_INTEL: Color   = Color(0.28, 0.32, 0.62, 1.0)   # ink-blue
const COLOR_ACTION: Color  = Color(0.55, 0.08, 0.08, 1.0)   # wine
const COLOR_HOST: Color    = Color(0.18, 0.34, 0.22, 1.0)   # forest
const COLOR_DIGEST: Color  = Color(0.54, 0.36, 0.10, 1.0)   # mustard
const COLOR_NEWS: Color    = Color(0.22, 0.14, 0.06, 1.0)   # ink
const COLOR_INTRO: Color   = Color(0.44, 0.44, 0.44, 1.0)   # slate
const COLOR_MISC: Color    = Color(0.55, 0.42, 0.28, 0.8)   # parchment edge


static func color_for(kind: StringName) -> Color:
	match kind:
		&"intel":  return COLOR_INTEL
		&"action": return COLOR_ACTION
		&"host":   return COLOR_HOST
		&"digest": return COLOR_DIGEST
		&"news":   return COLOR_NEWS
		&"intro":  return COLOR_INTRO
		_:         return COLOR_MISC


static func label_for(kind: StringName) -> String:
	match kind:
		&"intel":  return "INTEL"
		&"action": return "ACTION"
		&"host":   return "HOST"
		&"digest": return "DIGEST"
		&"news":   return "NEWS"
		&"intro":  return "INTRO"
		_:         return ""
