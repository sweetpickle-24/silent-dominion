extends Node
## Autoloaded as `HostFlavor`. Unprompted letters from loyal hosts.
##
## The point is texture. When the player leaves the clock running and
## takes no actions for a while, the inbox still breathes — hosts send
## short letters that report on the weather of their city: the new
## tax bench, the war next door, the mood of the court. These letters
## are not actionable. They remind the player that their hosts are
## people living through the world they are only observing.
##
## One candidate host is picked per month, at random, from the current
## roster. At most one flavor letter per month. If the player has no
## hosts, nothing fires.

const FIRE_CHANCE_PER_MONTH: float = 0.5   # when at least one host exists

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	GameClock.month_passed.connect(_on_month_passed)


func _on_month_passed(_y: int, _m: int) -> void:
	if _rng.randf() >= FIRE_CHANCE_PER_MONTH:
		return
	var hosts: Array[Actor] = Actors.hosts()
	if hosts.is_empty():
		return
	var host: Actor = hosts[_rng.randi_range(0, hosts.size() - 1)]
	_send_flavor_letter(host)


func _send_flavor_letter(host: Actor) -> void:
	var body: String = _compose_body(host)
	var subject: String = _compose_subject(host)
	var date: GameDate = GameDate.make(-GameClock.year, GameClock.month, GameClock.day)
	var letter_id: StringName = StringName("hostflavor_%s_%d" % [
		String(host.id), GameClock.absolute_day(),
	])
	var letter: Letter = Letter.create(
		letter_id,
		host.display_name(),
		date,
		subject,
		body,
		&"host"
	)
	EventBus.letter_delivered.emit(letter)


# --- Composition -------------------------------------------------------------
#
# The letter is assembled from the host's situation: city state, at-war
# neighbors, tax level, and the host's own traits. Each branch picks
# one phrase from a bank so repeat letters don't feel copy-pasted.

func _compose_subject(host: Actor) -> String:
	var candidates: Array[String] = [
		"A letter from %s" % _kingdom_name(host.kingdom_id),
		"From your hand in %s" % _kingdom_name(host.kingdom_id),
		"A quiet word",
		"Nothing urgent",
	]
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _compose_body(host: Actor) -> String:
	var lines: Array[String] = []
	var k: Kingdom = WorldData.get_kingdom(host.kingdom_id)

	lines.append(_opening_line(host))

	# City mood — lean on tax level if not MODEST.
	if k != null and k.tax_level != Kingdom.TaxLevel.MODEST:
		lines.append(_tax_line(k))

	# War / peace texture.
	if k != null:
		var at_war: Array[String] = Relations.ids_in_state(k.id, int(Relations.RelationState.AT_WAR))
		if not at_war.is_empty():
			lines.append(_war_line(k, at_war))

	# Treasury condition lens.
	if k != null:
		var cond_line: String = _condition_line(k)
		if not cond_line.is_empty():
			lines.append(cond_line)

	# One trait-colored personal line.
	lines.append(_personal_line(host))

	lines.append("")
	lines.append("Yours as before,")
	lines.append("— %s" % host.display_name())

	return "\n".join(lines)


func _opening_line(_host: Actor) -> String:
	var openings: Array[String] = [
		"I write without cause, which is itself a luxury.",
		"No news of consequence this week, which is its own kind of news.",
		"A short letter, so you can read it quickly and then attend to more pressing things.",
		"The season is turning here.",
		"It is quiet enough this morning that I can write to you.",
	]
	return openings[_rng.randi_range(0, openings.size() - 1)]


func _tax_line(k: Kingdom) -> String:
	match k.tax_level:
		Kingdom.TaxLevel.INDULGENT:
			return "The crown has eased the [url=codebook:tax]tax bench[/url]. Bakers sing about it; lenders do not."
		Kingdom.TaxLevel.BURDENED:
			return "[url=codebook:tax]Taxes[/url] bite harder this season. The market is quieter than it was, and more watchful."
		Kingdom.TaxLevel.RUINOUS:
			return "The [url=codebook:tax]levies[/url] have become openly resented. Every third conversation becomes a complaint about them. Every fourth becomes something more serious."
		_:
			return ""


func _war_line(_k: Kingdom, at_war: Array[String]) -> String:
	var enemy_names: Array[String] = []
	for id in at_war:
		var e: Kingdom = WorldData.get_kingdom(id)
		enemy_names.append(e.kingdom_name if e != null else id)
	var list: String = _join(enemy_names)
	var phrasings: Array[String] = [
		"The war with %s is still spoken of as if it will be over by autumn. It will not be." % list,
		"Columns from %s have not yet arrived but they are expected. The walls are being counted." % list,
		"Men are leaving the city for the front against %s. Their wives take in the shutters." % list,
	]
	return phrasings[_rng.randi_range(0, phrasings.size() - 1)]


func _condition_line(k: Kingdom) -> String:
	match k.treasury_condition:
		Kingdom.TreasuryCondition.BROKE:
			return "The treasury is openly empty. The palace calls it 'a reform of accounts'. Nobody else calls it anything polite."
		Kingdom.TreasuryCondition.INDEBTED:
			return "The palace is borrowing, and some of the lenders have stopped pretending to be discreet about it."
		Kingdom.TreasuryCondition.FLUSH:
			return "The palace is rich this season. That usually means something costly is being planned."
		_:
			return ""


func _personal_line(host: Actor) -> String:
	# Pick one line colored by one trait the host happens to be strong in.
	var candidates: Array[String] = []
	if host.paranoia >= 65:
		candidates.append("I have been burning your letters this month. I recommend you do the same with mine.")
	if host.ambition >= 70:
		candidates.append("I have been thinking of higher things. I will write to you when the thought settles.")
	if host.greed >= 65:
		candidates.append("If there is silver to be routed, let me know. There is always a use for it here.")
	if host.charisma >= 70:
		candidates.append("I had half the right table at dinner this week. Names on request.")
	if host.piety >= 70:
		candidates.append("The priests have been agreeable lately. I do not trust it and you should not either.")
	if host.relationship >= 80:
		candidates.append("I am yours, as you already know. I only repeat it because the winter is long.")

	if candidates.is_empty():
		candidates.append("There is little to report beyond that. I remain where you left me.")

	return candidates[_rng.randi_range(0, candidates.size() - 1)]


# --- Helpers -----------------------------------------------------------------

func _kingdom_name(id: String) -> String:
	var k: Kingdom = WorldData.get_kingdom(id)
	return k.kingdom_name if k != null else id


func _join(names: Array[String]) -> String:
	if names.size() == 1:
		return names[0]
	if names.size() == 2:
		return "%s and %s" % [names[0], names[1]]
	var copy: Array[String] = names.duplicate()
	var last: String = copy.pop_back()
	return "%s, and %s" % [", ".join(copy), last]
