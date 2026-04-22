class_name Army
extends Resource
## A single standing army under a kingdom's crown (§27).
##
## Size is measured in thousands of fighting men, matching the unit
## Province.population uses (220 = ~220k). Nothing in the UI ever shows
## the raw number — callers render `size_phrase()`, `morale_phrase()`,
## etc. Armies are mutated in place by ArmyRegistry each month and by
## battle resolution.

@export var id: String = ""
@export var kingdom_id: String = ""

## Size, quality, morale, supply, loyalty are all 0..N ints.
## Size is expressed in thousands of men.
@export var size: int = 0

## Trained-and-kitted-out quality band. Trends slowly. 0..100.
@export var quality: int = 50

## Current spirit. Moves fast. 0..100.
@export var morale: int = 60

## Provisions + pay state. Drops in war, rises in peace if the crown
## is solvent. 0..100.
@export var supply: int = 80

## Willingness to stay under the crown's commission. Drops when unpaid
## or when the treasury is broke; drops faster in regencies. 0..100.
## Below 30 is mutinous — battles go worse, and WorldAI may surface a
## coup risk later.
@export var loyalty: int = 70

## Optional commander actor id. Empty until the ruler appoints one.
@export var commander_id: StringName = &""

## Seeded ceiling size, stored so we can phrase recovery/"back to
## strength" without losing the pristine figure through drift.
@export var size_ceiling: int = 0


func is_mutinous() -> bool:
	return loyalty < 30


func size_phrase() -> String:
	if size <= 0:
		return "a broken standard, no men left under arms"
	if size < 3:
		return "barely a column's worth of men"
	if size < 8:
		return "a modest field force"
	if size < 20:
		return "a standing army of real weight"
	if size < 50:
		return "a great army, the kind that ends succession disputes"
	return "a host such as only the largest crowns can still raise"


func morale_phrase() -> String:
	if morale >= 80:
		return "spirits high, banners bright"
	if morale >= 60:
		return "the ranks are steady"
	if morale >= 40:
		return "the men march but do not sing"
	if morale >= 20:
		return "the army's mood has turned sullen"
	return "a broken, grumbling camp"


func supply_phrase() -> String:
	if supply >= 80:
		return "the baggage train is full"
	if supply >= 50:
		return "supply is adequate"
	if supply >= 25:
		return "the quartermasters are nervous"
	return "men eating short rations and grumbling about it"


func loyalty_phrase() -> String:
	if loyalty >= 80:
		return "the officers swear freely by the crown"
	if loyalty >= 55:
		return "the commission is honoured, if not loved"
	if loyalty >= 35:
		return "there is talk in the tents, talk that was not there last season"
	return "the army is one bad payday from raising another banner"


func quality_phrase() -> String:
	if quality >= 80:
		return "a well-drilled, well-kitted force"
	if quality >= 55:
		return "steady, experienced regulars"
	if quality >= 35:
		return "a levy army — brave but uneven"
	return "peasant spears and rusted iron"


func to_dict() -> Dictionary:
	return {
		"id":            id,
		"kingdom_id":    kingdom_id,
		"size":          size,
		"quality":       quality,
		"morale":        morale,
		"supply":        supply,
		"loyalty":       loyalty,
		"commander_id":  String(commander_id),
		"size_ceiling":  size_ceiling,
	}


static func from_dict(d: Dictionary) -> Army:
	var a: Army = Army.new()
	a.id           = String(d.get("id", ""))
	a.kingdom_id   = String(d.get("kingdom_id", ""))
	a.size         = int(d.get("size", 0))
	a.quality      = int(d.get("quality", 50))
	a.morale       = int(d.get("morale", 60))
	a.supply       = int(d.get("supply", 80))
	a.loyalty      = int(d.get("loyalty", 70))
	a.commander_id = StringName(String(d.get("commander_id", "")))
	a.size_ceiling = int(d.get("size_ceiling", a.size))
	return a
