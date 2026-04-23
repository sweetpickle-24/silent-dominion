class_name Era
extends Resource
## A single historical era (§6.2).
##
## Eras aren't bounded by hard calendar cuts in the fiction, but the
## simulation needs a hard cutover for things like infrastructure
## tick rates, language evolution gates, communications speed, and
## rival-society tempo. An era is the coarse bucket that holds those
## cutovers together.
##
## `year_start` is the BCE-negative / CE-positive year the era
## first becomes current. The world starts in the era whose window
## covers GameClock.year on game start and advances as soon as a
## later era's window opens.

@export var id: StringName = &""
@export var display_name: String = ""
@export var blurb: String = ""

## Start year in the BCE-negative / CE-positive convention. So
## 500 BCE is -500, 1200 CE is 1200.
@export var year_start: int = -500

## End year (exclusive) with the same convention. The game clock
## moving *past* this number triggers transition to the next era.
@export var year_end: int = 200

## Multiplier on travel time and dispatch delay. 1.0 is ancient
## baseline; later eras shorten gradually. Used by the scheduler
## and action_runner when they query EraManager.
@export_range(0.2, 2.0) var communication_multiplier: float = 1.0

## Per-month visibility decay multiplier on operations. Modernity
## makes cover harder to hold — late-era ops rot faster.
@export_range(0.8, 2.0) var visibility_decay_multiplier: float = 1.0

## Cosmetic hint for the Table chrome — which material the UI
## should lean on for this era. The actual textures ship later;
## the string is enough to drive a theme swap.
@export var table_chrome: StringName = &"wax_tablet"


func covers(year: int) -> bool:
	return year >= year_start and year < year_end


static func from_dict(d: Dictionary) -> Era:
	var e: Era = Era.new()
	e.id = StringName(String(d.get("id", "")))
	e.display_name = String(d.get("display_name", ""))
	e.blurb = String(d.get("blurb", ""))
	e.year_start = int(d.get("year_start", -500))
	e.year_end = int(d.get("year_end", 200))
	e.communication_multiplier = float(d.get("communication_multiplier", 1.0))
	e.visibility_decay_multiplier = float(d.get("visibility_decay_multiplier", 1.0))
	e.table_chrome = StringName(String(d.get("table_chrome", "wax_tablet")))
	return e


func to_dict() -> Dictionary:
	return {
		"id":                           String(id),
		"display_name":                 display_name,
		"blurb":                        blurb,
		"year_start":                   year_start,
		"year_end":                     year_end,
		"communication_multiplier":     communication_multiplier,
		"visibility_decay_multiplier":  visibility_decay_multiplier,
		"table_chrome":                 String(table_chrome),
	}
