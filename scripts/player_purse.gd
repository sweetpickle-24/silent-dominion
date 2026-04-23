extends Node
## Autoloaded as `Purse`. The player's silver on hand.
##
## The player never sees the raw figure (§7.6). They see a qualitative
## band — "lean", "comfortable", "deep", etc. — on the small weight
## token that sits beside the exposure indicator on the table.
##
## Internally the number is real. Action issuance deducts silver_cost;
## if the purse is too thin, the action is refused. Monthly income is
## computed as a small base stipend plus a bonus for every mercantile
## host in your stable (§5: a merchant host routes some of their own
## coin your way).

signal value_changed(value: int)
signal band_changed(band: StringName)

const STARTING_SILVER: int = 320

# Monthly income inputs. Kept deliberately modest so the player feels
# forced to route money carefully, not drown in it.
const BASE_MONTHLY_STIPEND: int = 12
const MERCHANT_HOST_INCOME:  int = 18
const GENERIC_HOST_INCOME:   int = 4

const BANDS: Dictionary = {
	&"bone_dry":    "Bone dry",
	&"thin":        "Thin",
	&"lean":        "Lean",
	&"comfortable": "Comfortable",
	&"deep":        "Deep",
	&"bottomless":  "Bottomless",
}

var silver: int = STARTING_SILVER
var _current_band: StringName = &""


func _ready() -> void:
	_current_band = _band_for(silver)
	GameClock.month_passed.connect(_on_month_passed)


# --- Public API --------------------------------------------------------------

func can_afford(amount: int) -> bool:
	return silver >= amount


func spend(amount: int) -> bool:
	if amount <= 0:
		return true
	if silver < amount:
		return false
	_set_silver(silver - amount)
	return true


func add(amount: int) -> void:
	if amount == 0:
		return
	_set_silver(silver + amount)


func band() -> StringName:
	return _current_band


func band_name() -> String:
	return String(BANDS.get(_current_band, "Thin"))


func band_blurb() -> String:
	return band_blurb_for(_current_band)


static func band_blurb_for(band_id: StringName) -> String:
	match band_id:
		&"bone_dry":    return "The purse is empty. No silver leaves it until silver enters it."
		&"thin":        return "There is silver, but not much. A single expensive move will strip the bottom."
		&"lean":        return "Enough for careful work. Not enough for noise."
		&"comfortable": return "Enough to live many seasons and still pay a paymaster."
		&"deep":        return "You could fund a small war, quietly."
		&"bottomless":  return "Silver is no longer the constraint."
		_:              return ""


## Ordered list of all bands for the §30.1 system reference.
## Each entry is { id, label, blurb }. Drawn live from BANDS so the
## glossary never goes out of step with the indicator.
static func band_entries() -> Array:
	var order: Array = [&"bone_dry", &"thin", &"lean", &"comfortable", &"deep", &"bottomless"]
	var out: Array = []
	for id in order:
		out.append({
			"id":    id,
			"label": String(BANDS.get(id, String(id))),
			"blurb": band_blurb_for(id),
		})
	return out


# --- Monthly tick ------------------------------------------------------------

func _on_month_passed(_y: int, _m: int) -> void:
	var income: int = BASE_MONTHLY_STIPEND
	for h in Actors.hosts():
		if h.role == Actor.Role.MERCHANT:
			income += MERCHANT_HOST_INCOME
		else:
			income += GENERIC_HOST_INCOME
	if income > 0:
		add(income)


# --- Internal ----------------------------------------------------------------

func _set_silver(new_value: int) -> void:
	var clamped: int = maxi(new_value, 0)
	if clamped == silver:
		return
	silver = clamped
	value_changed.emit(silver)
	var new_band: StringName = _band_for(silver)
	if new_band != _current_band:
		_current_band = new_band
		band_changed.emit(_current_band)


func _band_for(v: int) -> StringName:
	if v <= 0:     return &"bone_dry"
	if v < 80:     return &"thin"
	if v < 250:    return &"lean"
	if v < 800:    return &"comfortable"
	if v < 2500:   return &"deep"
	return &"bottomless"


# --- Save/load hooks ---------------------------------------------------------

func snapshot() -> Dictionary:
	return { "silver": silver }


func restore(d: Dictionary) -> void:
	_set_silver(int(d.get("silver", STARTING_SILVER)))
