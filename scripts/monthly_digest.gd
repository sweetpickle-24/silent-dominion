extends Node
## Autoloaded as `Digest`. Composes a short letter at the end of each
## in-game month summarizing what happened while the player was turning
## the speed dial.
##
## The letter is written from a neutral factotum — not the player,
## not a host, not a ruler. It is a private brief, not a dispatch.
## It exists so the player can leave the clock running and still have
## one tangible artifact per month to anchor memory against.
##
## Collection strategy:
##   - Subscribe to the system signals that matter.
##   - Accumulate small integers and short strings in-memory.
##   - On month_passed, compose one letter and wipe the buffers.
##
## Nothing here mutates world state. It only reads and reports.

# Counters that accumulate over the month.
var _deaths: int        = 0
var _assassinations: int = 0
var _successions: int   = 0
var _decrees: int       = 0
var _treasury_crises: int = 0
var _wars: int          = 0
var _hosts_won: int     = 0
var _action_wins: int   = 0
var _action_losses: int = 0

# Band transitions observed this month. Only the last one of each
# matters for the letter body; earlier flickers are ignored.
var _purse_band_to: StringName = &""
var _exposure_level_to: int    = -1

# Suppress the very first digest after boot so the player doesn't
# get "nothing happened" before they have even pressed play.
var _first_tick_consumed: bool = false


func _ready() -> void:
	EventBus.public_event.connect(_on_public_event)
	EventBus.action_resolved.connect(_on_action_resolved)
	Purse.band_changed.connect(_on_purse_band_changed)
	Exposure.level_changed.connect(_on_exposure_level_changed)
	GameClock.month_passed.connect(_on_month_passed)


# --- Signal handlers ---------------------------------------------------------

func _on_public_event(event: Dictionary) -> void:
	match event.get("kind", &"misc"):
		&"death":                 _deaths += 1
		&"assassination":         _assassinations += 1; _deaths += 1
		&"succession":            _successions += 1
		&"ruler_decree":          _decrees += 1
		&"treasury_crisis":       _treasury_crises += 1
		&"war_declaration":       _wars += 1
		&"host_won":              _hosts_won += 1


func _on_action_resolved(_action_id: StringName, result: Dictionary) -> void:
	if bool(result.get("success", false)):
		_action_wins += 1
	else:
		_action_losses += 1


func _on_purse_band_changed(band: StringName) -> void:
	_purse_band_to = band


func _on_exposure_level_changed(level: int) -> void:
	_exposure_level_to = level


# --- Monthly dispatch --------------------------------------------------------

func _on_month_passed(y: int, m: int) -> void:
	if not _first_tick_consumed:
		_first_tick_consumed = true
		_reset_buffers()
		return

	var body: String = _compose_body()
	var date: GameDate = GameDate.make(-y, m, 1)  # first of the new month
	var letter_id: StringName = StringName("digest_%d_%d" % [y, m])
	var subject: String = "The month past, in brief"
	var letter: Letter = Letter.create(
		letter_id,
		"Your factotum",
		date,
		subject,
		body
	)
	EventBus.letter_delivered.emit(letter)
	_reset_buffers()


func _compose_body() -> String:
	var lines: Array[String] = []
	lines.append("The month has turned. I set down what is worth setting down:")
	lines.append("")

	var anything: bool = false

	if _deaths > 0:
		anything = true
		if _assassinations > 0:
			lines.append("— %d death%s in places of consequence, of which %d by quieter means than age." % [
				_deaths, _plural(_deaths), _assassinations,
			])
		else:
			lines.append("— %d death%s in places of consequence, all of them unremarkable." % [
				_deaths, _plural(_deaths),
			])

	if _successions > 0:
		anything = true
		lines.append("— %d throne%s changed hands. Every chancery is rewriting its salutations." % [
			_successions, _plural(_successions),
		])

	if _decrees > 0:
		anything = true
		lines.append("— %d decree%s issued from the various crowns. Most will be forgotten by next festival; one or two may not." % [
			_decrees, _plural(_decrees),
		])

	if _treasury_crises > 0:
		anything = true
		lines.append("— %d treasur%s in publicly acknowledged trouble. The usual noises; the usual lenders." % [
			_treasury_crises, "y" if _treasury_crises == 1 else "ies",
		])

	if _wars > 0:
		anything = true
		lines.append("— %d war%s declared. The armies are slow; the letters asking for money are not." % [
			_wars, _plural(_wars),
		])

	if _hosts_won > 0:
		anything = true
		lines.append("— %d new hand%s is now yours, and knows it." % [
			_hosts_won, "" if _hosts_won == 1 else "s",
		])

	if _action_wins > 0 or _action_losses > 0:
		anything = true
		if _action_wins > 0 and _action_losses > 0:
			lines.append("— Of your own instruments, %d landed, %d did not." % [_action_wins, _action_losses])
		elif _action_wins > 0:
			lines.append("— Of your own instruments, %d landed cleanly." % _action_wins)
		else:
			lines.append("— Of your own instruments, %d miscarried. I await your next." % _action_losses)

	if _purse_band_to != &"":
		anything = true
		lines.append("— The purse now sits at \"%s\"." % Purse.band_name())

	if _exposure_level_to >= 0:
		anything = true
		lines.append("— The world's appetite for our name is now at \"%s\"." % Exposure.level_name())

	if not anything:
		lines.append("— Nothing of weight. Grain at market, priests at altar, soldiers on walls. The world is where you left it.")

	lines.append("")
	lines.append("Until the next turning,")
	lines.append("— Your factotum")
	return "\n".join(lines)


func _plural(n: int) -> String:
	return "" if n == 1 else "s"


func _reset_buffers() -> void:
	_deaths = 0
	_assassinations = 0
	_successions = 0
	_decrees = 0
	_treasury_crises = 0
	_wars = 0
	_hosts_won = 0
	_action_wins = 0
	_action_losses = 0
	_purse_band_to = &""
	_exposure_level_to = -1
