extends Node
## Autoloaded as `Session`. Carries intent across scene transitions.
##
## Scene changes blow away the scene tree but autoloads persist. When
## the title scene wants to hand off a specific load intent to the
## table scene (which hasn't been instantiated yet), it parks the
## intent here and the table picks it up on _ready.

var pending_load_slot: String = ""


func consume_pending_load() -> String:
	var s: String = pending_load_slot
	pending_load_slot = ""
	return s


## Convenience: find the newest existing save across all known slots,
## by saved_at timestamp (ISO string sorts lexicographically for our
## purposes). Returns "" if none exist.
func newest_slot() -> String:
	var candidates: Array[String] = ["quicksave", "slot_1", "slot_2", "slot_3"]
	var best_slot: String = ""
	var best_stamp: String = ""
	for s in candidates:
		var info: Dictionary = SaveManager.slot_info(s)
		if info.is_empty():
			continue
		var stamp: String = String(info.get("saved_at", ""))
		if stamp > best_stamp:
			best_stamp = stamp
			best_slot = s
	return best_slot


func any_save_exists() -> bool:
	return newest_slot() != ""
