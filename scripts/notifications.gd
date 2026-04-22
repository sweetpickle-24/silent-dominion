extends Node
## Autoloaded as `Notifications`. Per-table-object unseen counters.
##
## The inbox and the public news scroll already track their own unread
## state. This autoload extends that idea to the rest of the table —
## ledger, dossiers, map — so the player can tell at a glance which
## objects have new material without opening every one.
##
## Counters increment when relevant signals fire. They reset to zero
## when the corresponding object is marked seen (usually on open).

signal changed

const KEY_LEDGER: StringName   = &"ledger"
const KEY_DOSSIERS: StringName = &"dossiers"
const KEY_MAP: StringName      = &"map"

var _counts: Dictionary = {
	KEY_LEDGER:   0,
	KEY_DOSSIERS: 0,
	KEY_MAP:      0,
}


func _ready() -> void:
	KingdomEconomy.tick.connect(_on_economy_tick)
	EventBus.public_event.connect(_on_public_event)
	Relations.relation_changed.connect(_on_relation_changed)


# --- Public API --------------------------------------------------------------

func count(key: StringName) -> int:
	return int(_counts.get(key, 0))


func has_any(key: StringName) -> bool:
	return count(key) > 0


func mark_seen(key: StringName) -> void:
	if count(key) == 0:
		return
	_counts[key] = 0
	changed.emit()


# --- Signal handlers ---------------------------------------------------------

func _on_economy_tick(_snap: Array) -> void:
	# A fresh monthly pass. Bump the ledger.
	_bump(KEY_LEDGER, 1)


func _on_public_event(event: Dictionary) -> void:
	match event.get("kind", &"misc"):
		&"death", &"assassination", &"succession", &"host_won",
		&"assassination_attempt", &"plot_brewing", &"host_turned":
			_bump(KEY_DOSSIERS, 1)
		&"war_declaration", &"peace_declaration", &"tax_change", &"unrest",
		&"plague", &"famine", &"earthquake", &"recovery":
			_bump(KEY_MAP, 1)


func _on_relation_changed(_a: String, _b: String, _s: int) -> void:
	_bump(KEY_MAP, 1)


# --- Internal ----------------------------------------------------------------

func _bump(key: StringName, by: int) -> void:
	_counts[key] = int(_counts.get(key, 0)) + by
	changed.emit()
