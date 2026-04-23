extends RefCounted
class_name StressTest
## Headless fast-forward harness for §6.5 "hundred generations" testing.
##
## Pumps GameClock._advance_one_day() in a tight loop, which cascades
## through every subsystem listening to day/month/year signals. No
## rendering happens during the run — the engine frame doesn't turn
## over — so 200 in-game years take seconds on a modern machine.
##
## Side effects mirror real play: actors die, kingdoms feud, memoirs
## grow, letters queue in the inbox. After the run, call
## SaveManager.save_to_slot() to verify the round-trip.
##
## Typical invocation (from a hotkey, dev console, or _ready):
##     StressTest.run_years(200)
##     StressTest.run_years(500, 50)   # 500 yrs, sim-health every 50

const DAYS_PER_YEAR: int = 360  # must match GameClock.DAYS_PER_YEAR


## Fast-forward the simulation by `years`. Every `report_every_years`
## completed years, logs a sim-health line. Clock state afterwards is
## reset to whatever speed was running before, unset to PAUSED.
static func run_years(years: int, report_every_years: int = 50) -> Dictionary:
	if years <= 0:
		return {}

	var previous_speed: int = int(GameClock.speed)
	GameClock.set_speed(GameClock.Speed.PAUSED)  # disengage real-time pump

	# Silence continuous autosave during the harness — writing a
	# multi-megabyte JSON every 30 sim-days would dominate the timing
	# we're trying to measure. Restored at the end.
	var autosave_was_on: bool = false
	if Prefs != null:
		autosave_was_on = Prefs.continuous_autosave
		Prefs.continuous_autosave = false

	var start_year: int = GameClock.year
	var start_ticks_ms: int = Time.get_ticks_msec()

	var total_days: int = years * DAYS_PER_YEAR
	var reported_at_year: int = start_year

	_sim_health("stress_start y=%d" % start_year)

	for i in total_days:
		GameClock._advance_one_day()
		# Periodic report: compare whole-year deltas so we fire once
		# per threshold crossed, not once per day after it.
		if GameClock.year - reported_at_year >= report_every_years:
			reported_at_year = GameClock.year
			_sim_health("stress_y=%d elapsed_ms=%d" % [
				GameClock.year, Time.get_ticks_msec() - start_ticks_ms,
			])

	var elapsed_ms: int = Time.get_ticks_msec() - start_ticks_ms
	_sim_health("stress_end y=%d total_ms=%d ms_per_year=%d" % [
		GameClock.year, elapsed_ms, int(float(elapsed_ms) / float(years)),
	])

	if Prefs != null:
		Prefs.continuous_autosave = autosave_was_on
	GameClock.set_speed(previous_speed)
	return {
		"start_year":  start_year,
		"end_year":    GameClock.year,
		"elapsed_ms":  elapsed_ms,
		"ms_per_year": int(float(elapsed_ms) / float(years)),
	}


## Round-trip self-test for long-run saves. Fast-forwards, saves,
## reloads, and logs sim-health at each step. Used from a dev hotkey
## to validate §9.3 persistence claim (year 200 → year 1500 round
## trips cleanly).
## §9.5 long-session playtest proxy. Runs a fresh campaign forward,
## snapshotting per-decade metrics, round-tripping the save at 50 /
## 200 / 450 year marks, and dumping the resulting arc to disk for
## post-mortem inspection.
##
## Output:
##   user://playtest_arc.json            — machine-readable metrics
##   user://chronicles/playtest_arc.md   — human digest
static func run_growth_arc(max_years: int = 500) -> Dictionary:
	var previous_speed: int = int(GameClock.speed)
	GameClock.set_speed(GameClock.Speed.PAUSED)

	var autosave_was_on: bool = false
	if Prefs != null:
		autosave_was_on = Prefs.continuous_autosave
		Prefs.continuous_autosave = false

	var samples: Array = []
	var assertions: Array = []
	var roundtrip_at: Array[int] = [50, 200, 450]
	var start_year: int = GameClock.year
	var start_ticks_ms: int = Time.get_ticks_msec()
	var last_decade_ms: int = start_ticks_ms

	# Compute budget per decade: keep sample honest even on slow CI.
	const DECADE_BUDGET_MS: int = 20000

	var total_decades: int = max_years / 10
	for decade_idx in total_decades:
		for _i in range(10 * DAYS_PER_YEAR):
			GameClock._advance_one_day()

		var now_ms: int = Time.get_ticks_msec()
		var decade_ms: int = now_ms - last_decade_ms
		last_decade_ms = now_ms

		samples.append(_decade_sample(decade_idx + 1, decade_ms))

		# Budget watchdog: simulation never hangs.
		if decade_ms > DECADE_BUDGET_MS:
			assertions.append({
				"ok":      false,
				"kind":    "decade_budget",
				"decade":  decade_idx + 1,
				"elapsed_ms": decade_ms,
			})

		# Growth assertion at year 50 unless lean_start explicitly
		# blunts the opening.
		if decade_idx + 1 == 5:
			var coverage: int = _coverage_count()
			var lean: bool = false
			if DifficultyProfile != null:
				lean = DifficultyProfile.current().lean_start
			assertions.append({
				"ok":       lean or coverage > 0,
				"kind":     "coverage_y50",
				"coverage": coverage,
				"lean":     lean,
			})

		# Round-trip checks at 50 / 200 / 450.
		var at_year: int = 10 * (decade_idx + 1)
		if roundtrip_at.has(at_year):
			assertions.append(_roundtrip_check(at_year))

	if Prefs != null:
		Prefs.continuous_autosave = autosave_was_on
	GameClock.set_speed(previous_speed)

	var out: Dictionary = {
		"start_year":  start_year,
		"end_year":    GameClock.year,
		"elapsed_ms":  Time.get_ticks_msec() - start_ticks_ms,
		"samples":     samples,
		"assertions":  assertions,
	}
	_persist_arc(out)
	return out


static func _decade_sample(decade: int, elapsed_ms: int) -> Dictionary:
	var operatives: int = 0
	var coordinators: int = 0
	var lieutenants: int = 0
	if Org != null:
		if Org.has_method("operatives_count"):
			operatives = Org.operatives_count()
		elif "members" in Org:
			var mv: Variant = Org.get("members")
			if mv is Dictionary:
				operatives = (mv as Dictionary).size()
			elif mv is Array:
				operatives = (mv as Array).size()
	var entities: int = 0
	if Entities != null and "entities" in Entities:
		entities = (Entities.entities as Dictionary).size()
	var patterns: int = 0
	if Memoirs != null and "patterns" in Memoirs:
		patterns = (Memoirs.patterns as Dictionary).size()
	var exposure: float = 0.0
	if Exposure != null and "value" in Exposure:
		exposure = float(Exposure.value)
	var era_id: StringName = &""
	if Eras != null and Eras.has_method("current_id"):
		era_id = Eras.current_id()
	var famines: int = 0
	if Population != null and Population.has_method("famine_provinces"):
		famines = (Population.famine_provinces() as Array).size()
	var wars: int = 0
	if Relations != null and Relations.has_method("active_wars"):
		wars = (Relations.active_wars() as Array).size()
	var news_delivered: int = 0
	if PublicNews != null and "events" in PublicNews:
		news_delivered = (PublicNews.events as Array).size()
	var chronicle_size: int = 0
	if Chronicle != null and "_entries" in Chronicle:
		chronicle_size = (Chronicle._entries as Array).size()
	return {
		"decade":         decade,
		"year":           GameClock.year,
		"elapsed_ms":     elapsed_ms,
		"operatives":     operatives,
		"coordinators":   coordinators,
		"lieutenants":    lieutenants,
		"entities":       entities,
		"coverage_kingdoms": _coverage_count(),
		"patterns":       patterns,
		"exposure":       exposure,
		"era":            String(era_id),
		"famines":        famines,
		"active_wars":    wars,
		"news_events":    news_delivered,
		"chronicle_size": chronicle_size,
	}


static func _coverage_count() -> int:
	if Org == null:
		return 0
	if Org.has_method("kingdoms_with_coverage"):
		return (Org.kingdoms_with_coverage() as Array).size()
	if "coverage" in Org and Org.coverage is Dictionary:
		return (Org.coverage as Dictionary).size()
	return 0


static func _roundtrip_check(at_year: int) -> Dictionary:
	var slot: String = "playtest_arc_y%d" % at_year
	var ok_save: bool = SaveManager.save_to_slot(slot)
	var before: Dictionary = SaveManager._collect_state() if ok_save else {}
	var ok_load: bool = ok_save and SaveManager.load_from_slot(slot)
	var after: Dictionary = SaveManager._collect_state() if ok_load else {}
	var keys_match: bool = before.keys() == after.keys()
	return {
		"ok":         ok_save and ok_load and keys_match,
		"kind":       "save_roundtrip",
		"year":       at_year,
		"keys_match": keys_match,
	}


static func _persist_arc(arc: Dictionary) -> void:
	var dir: String = "user://chronicles"
	if not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)

	var jf: FileAccess = FileAccess.open("user://playtest_arc.json", FileAccess.WRITE)
	if jf != null:
		jf.store_string(JSON.stringify(arc, "\t"))
		jf.close()

	var md: FileAccess = FileAccess.open("%s/playtest_arc.md" % dir, FileAccess.WRITE)
	if md == null:
		return
	md.store_line("# Playtest arc — %d decades" % (int(arc.get("end_year", 0)) - int(arc.get("start_year", 0))))
	md.store_line("")
	md.store_line("| decade | year | era | operatives | entities | patterns | news | coverage | exposure | wars | famines | ms |")
	md.store_line("|--------|------|-----|-----------|----------|----------|------|----------|----------|------|---------|----|")
	for s_any in arc.get("samples", []):
		var s: Dictionary = s_any
		md.store_line("| %d | %d | %s | %d | %d | %d | %d | %d | %.1f | %d | %d | %d |" % [
			int(s.get("decade", 0)),
			int(s.get("year", 0)),
			String(s.get("era", "")),
			int(s.get("operatives", 0)),
			int(s.get("entities", 0)),
			int(s.get("patterns", 0)),
			int(s.get("news_events", 0)),
			int(s.get("coverage_kingdoms", 0)),
			float(s.get("exposure", 0.0)),
			int(s.get("active_wars", 0)),
			int(s.get("famines", 0)),
			int(s.get("elapsed_ms", 0)),
		])
	md.store_line("")
	md.store_line("## Assertions")
	md.store_line("")
	for a_any in arc.get("assertions", []):
		var a: Dictionary = a_any
		md.store_line("- **%s** %s" % [
			"PASS" if bool(a.get("ok", false)) else "FAIL",
			JSON.stringify(a),
		])
	md.close()


static func run_save_roundtrip(first_leg_years: int, second_leg_years: int) -> void:
	run_years(first_leg_years)
	SaveManager.save_to_slot("stress")
	_sim_health("after_save")
	var ok: bool = SaveManager.load_from_slot("stress")
	if not ok:
		push_error("[StressTest] Reload from slot 'stress' failed")
		return
	_sim_health("after_reload")
	run_years(second_leg_years)


# --- Private -----------------------------------------------------------------

static func _sim_health(tag: String) -> void:
	# SaveManager owns the canonical sim-health printer; delegate so
	# the log format stays in one place.
	if SaveManager != null:
		SaveManager.print_sim_health(tag)
	else:
		print("[StressTest] %s" % tag)
