extends Node
## Autoloaded as `Immortals`. The roster of other immortals per §5.5.
##
## The registry is kept deliberately small (4-5 peers), seeded at
## campaign start — one per named society, with at most one
## posthumous to exercise both paths. The player learns of an
## immortal only when their society reaches catalogued confirmation;
## until then, the relationship remains &"unknown" and nothing
## renders to UI.
##
## State transitions are driven from two places:
##   - `Fingerprints.society_identified` monthly: at >= 85 we flip
##     `known_by_player` on the matching immortal (if alive) and
##     fire the reveal letter.
##   - Player actions (`request_contact`, `propose_truce`,
##     `attempt_kill_immortal`) mutate `relationship` directly.

@warning_ignore("unused_signal") signal immortal_revealed(immortal_id: StringName)
@warning_ignore("unused_signal") signal relationship_changed(immortal_id: StringName, relationship: StringName)
@warning_ignore("unused_signal") signal immortal_killed(immortal_id: StringName)
@warning_ignore("unused_signal") signal immortal_escaped(immortal_id: StringName)

# id (StringName) -> OtherImmortal
var _immortals: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _seeded: bool = false


func _ready() -> void:
	_rng.randomize()
	if WorldData.is_loaded():
		_maybe_seed()
	else:
		WorldData.world_loaded.connect(_maybe_seed, CONNECT_ONE_SHOT)
	Fingerprints.society_identified.connect(_on_society_identified)


func _maybe_seed() -> void:
	if _seeded:
		return
	if not _immortals.is_empty():
		_seeded = true
		return
	_seed_defaults()
	_seeded = true


# --- Public API -----------------------------------------------------------

func all_immortals() -> Array[OtherImmortal]:
	var out: Array[OtherImmortal] = []
	for v in _immortals.values():
		out.append(v)
	return out


func get_by_id(id: StringName) -> OtherImmortal:
	return _immortals.get(id, null) as OtherImmortal


func get_by_society(society_id: StringName) -> OtherImmortal:
	for o in _immortals.values():
		if (o as OtherImmortal).society_id == society_id:
			return o
	return null


func known_immortals() -> Array[OtherImmortal]:
	var out: Array[OtherImmortal] = []
	for o in _immortals.values():
		if (o as OtherImmortal).known_by_player:
			out.append(o)
	return out


## Best candidate for player-initiated contact: a known, alive
## immortal whose society has some foothold in `kingdom_id` (or any
## known immortal otherwise). Returns null if none qualify.
func best_contact_target(kingdom_id: String) -> OtherImmortal:
	var best: OtherImmortal = null
	var best_score: int = -1
	for o in _immortals.values():
		var im: OtherImmortal = o
		if not im.known_by_player:
			continue
		if not im.is_alive():
			continue
		if im.relationship == &"dead" or im.relationship == &"escaped":
			continue
		var soc: RivalSociety = Rivals.get_society(im.society_id)
		var fh: int = 0
		if soc != null:
			fh = soc.foothold_in(kingdom_id)
		var score: int = im.openness + fh
		if score > best_score:
			best_score = score
			best = im
	return best


func set_relationship(id: StringName, rel: StringName) -> void:
	var im: OtherImmortal = get_by_id(id)
	if im == null:
		return
	if im.relationship == rel:
		return
	im.relationship = rel
	relationship_changed.emit(id, rel)


## Mark an immortal as killed. Flips the society's founder state to
## posthumous, which has ripple effects handled in Rivals (tempo halves,
## no new operatives seeded). Fires letter via the caller.
func kill_immortal(id: StringName) -> bool:
	var im: OtherImmortal = get_by_id(id)
	if im == null:
		return false
	im.kill_state = OtherImmortal.KillState.POSTHUMOUS
	im.relationship = &"dead"
	relationship_changed.emit(id, &"dead")
	immortal_killed.emit(id)
	# Tempo / operative-seeding halt is derived at tick time from
	# `kill_state`. Nothing else to push here.
	return true


## Mark an immortal as escaped after a failed kill. They are now the
## most dangerous threat in the game per §5.5.
func escape_immortal(id: StringName) -> bool:
	var im: OtherImmortal = get_by_id(id)
	if im == null:
		return false
	im.relationship = &"escaped"
	relationship_changed.emit(id, &"escaped")
	immortal_escaped.emit(id)
	return true


# --- Event hooks ----------------------------------------------------------

## When a society hits catalogued confirmation, the founder (if alive)
## notices us in return. We reveal them to the UI and drop a letter.
func _on_society_identified(society_id: StringName, confirmation: int) -> void:
	if confirmation < 85:
		return
	var im: OtherImmortal = get_by_society(society_id)
	if im == null or not im.is_alive():
		return
	if im.known_by_player:
		return
	im.known_by_player = true
	im.relationship = &"aware"
	immortal_revealed.emit(im.id)
	relationship_changed.emit(im.id, &"aware")
	_send_reveal_letter(im)


func _send_reveal_letter(im: OtherImmortal) -> void:
	var soc: RivalSociety = Rivals.get_society(im.society_id)
	var soc_name: String = soc.display_name if soc != null else "the society in question"
	var date: GameDate = GameDate.make(-GameClock.year, GameClock.month, GameClock.day)
	var subject: String = "You are not the only one"
	var body: String = (
		"Friend,\n\n"
		+ "The library's work on %s has gone deep enough that someone on their "
		+ "side has, in turn, done the same work on you. A letter was left with "
		+ "one of our intermediaries last week. Unsigned. Not threatening. Not quite "
		+ "friendly either.\n\n"
		+ "The sense of it is this: there is a person behind that society who "
		+ "has lived about as long as you have. They know what you are because "
		+ "they are that thing themselves. They describe themselves only as [b]%s[/b].\n\n"
		+ "They are not asking for anything. They are making sure you know that "
		+ "they know. What you choose to do with that is, as all such choices are, yours."
	) % [soc_name, im.epithet]
	var letter: Letter = Letter.create(
		"immortal_reveal_%s" % String(im.id),
		"An intermediary",
		date, subject, body, &"intel",
	)
	EventBus.letter_delivered.emit(letter)


# --- Seeding --------------------------------------------------------------

func _seed_defaults() -> void:
	# Architects → active, very open. Their whole project is order —
	# a truce with a peer is legible to their philosophy.
	_add(_make(
		&"architects_immortal",
		&"architects",
		"the First Architect",
		"Old, patient, convinced order is worth any cost.",
		80, 30,
	))
	# Pyre → active, very hostile. Purification cannot coexist with
	# a rival who does not burn.
	_add(_make(
		&"pyre_immortal",
		&"pyre",
		"the Ember",
		"A burner. Believes mercy is evidence of rot.",
		20, 85,
	))
	# Weavers → active, conditional openness. Commerce-minded; will
	# trade neutrality for reach.
	_add(_make(
		&"weavers_immortal",
		&"weavers",
		"the Loom-Keeper",
		"Mercantile, patient. Prefers arrangements to vendettas.",
		65, 40,
	))
	# Veil → posthumous. Their founder is a legend; the society runs
	# on inherited doctrine alone.
	_add(_make_posthumous(
		&"veil_immortal",
		&"veil",
		"the Silent Gardener",
		"Founder long dead. Their society is mortal succession now.",
	))
	# Compact → active, cold-moral. Will neither kill nor sanction the
	# player without reason but refuses truce on principle.
	_add(_make(
		&"compact_immortal",
		&"compact",
		"the Elder Signatory",
		"Moralist. Refuses both war and alliance. Watches.",
		45, 20,
	))


func _make(id: StringName, sid: StringName, epithet: String, disposition: String,
		openness: int, hostility: int) -> OtherImmortal:
	var o: OtherImmortal = OtherImmortal.new()
	o.id = id
	o.society_id = sid
	o.epithet = epithet
	o.disposition = disposition
	o.kill_state = OtherImmortal.KillState.ALIVE
	o.relationship = &"unknown"
	o.openness = openness
	o.hostility = hostility
	return o


func _make_posthumous(id: StringName, sid: StringName, epithet: String, disposition: String) -> OtherImmortal:
	var o: OtherImmortal = OtherImmortal.new()
	o.id = id
	o.society_id = sid
	o.epithet = epithet
	o.disposition = disposition
	o.kill_state = OtherImmortal.KillState.POSTHUMOUS
	o.relationship = &"unknown"
	o.openness = 0
	o.hostility = 0
	return o


func _add(o: OtherImmortal) -> void:
	_immortals[o.id] = o


# --- Save / load ----------------------------------------------------------

func snapshot() -> Dictionary:
	var arr: Array[Dictionary] = []
	for v in _immortals.values():
		arr.append((v as OtherImmortal).to_dict())
	return {
		"immortals": arr,
	}


func restore(d: Dictionary) -> void:
	_immortals.clear()
	var arr: Variant = d.get("immortals", [])
	if arr is Array:
		for e in arr:
			if e is Dictionary:
				var im: OtherImmortal = OtherImmortal.from_dict(e)
				_immortals[im.id] = im
	_seeded = true
	if _immortals.is_empty():
		_seed_defaults()
