extends Node
## Autoloaded as `AudioDirector`. Full implementation lives in Bucket C.
## This minimal boot file exists so that `project.godot` autoload order
## can include it without breaking parse; the real wiring comes shortly.

signal cue_played(tag: StringName)

# Buses
var _master_bus: int = 0
var _music_bus: int = 0
var _sfx_bus: int = 0
var _ambient_bus: int = 0

# Players
var _ambient_player: AudioStreamPlayer = null

# Tag -> AudioStreamWAV cache
var _cues: Dictionary = {}

# Event subscriptions installed?
var _wired: bool = false


func _ready() -> void:
	DevLogger.write("AudioDirector: ready")
	_ensure_buses()
	_ensure_players()
	_wire_events.call_deferred()
	_install_pref_listener()
	_apply_volumes()


# --- Public API --------------------------------------------------------------

func play_cue(tag: StringName, _ctx: Dictionary = {}) -> void:
	if Prefs != null and not _sfx_on():
		return
	var stream: AudioStream = _cue_stream(tag)
	if stream == null:
		return
	var one_shot: AudioStreamPlayer = AudioStreamPlayer.new()
	one_shot.bus = _bus_name(_sfx_bus)
	one_shot.stream = stream
	add_child(one_shot)
	one_shot.finished.connect(one_shot.queue_free)
	one_shot.play()
	cue_played.emit(tag)


func set_era(_id: StringName) -> void:
	_refresh_ambient()


# --- Internals ---------------------------------------------------------------

func _ensure_buses() -> void:
	_master_bus = AudioServer.get_bus_index("Master")
	_music_bus = _ensure_bus("Music")
	_sfx_bus = _ensure_bus("SFX")
	_ambient_bus = _ensure_bus("Ambient")


func _ensure_bus(name: String) -> int:
	var idx: int = AudioServer.get_bus_index(name)
	if idx != -1:
		return idx
	AudioServer.add_bus()
	idx = AudioServer.bus_count - 1
	AudioServer.set_bus_name(idx, name)
	AudioServer.set_bus_send(idx, "Master")
	return idx


func _bus_name(idx: int) -> String:
	if idx < 0:
		return "Master"
	return AudioServer.get_bus_name(idx)


func _ensure_players() -> void:
	if _ambient_player != null:
		return
	_ambient_player = AudioStreamPlayer.new()
	_ambient_player.bus = _bus_name(_ambient_bus)
	_ambient_player.autoplay = false
	add_child(_ambient_player)


func _wire_events() -> void:
	if _wired:
		return
	_wired = true
	if Engine.has_singleton("EventBus"):
		pass
	var tree: SceneTree = get_tree()
	var root: Node = tree.root if tree != null else null
	if root == null:
		return
	var bus: Node = root.get_node_or_null("EventBus")
	if bus != null and bus.has_signal("letter_delivered"):
		bus.letter_delivered.connect(func(_l): play_cue(&"letter_arrived"))
	var org: Node = root.get_node_or_null("Org")
	if org != null and org.has_signal("member_burned"):
		org.member_burned.connect(func(_m): play_cue(&"operative_burned"))
	var mandates: Node = root.get_node_or_null("Mandates")
	if mandates != null and mandates.has_signal("mandate_offered"):
		mandates.mandate_offered.connect(func(_m): play_cue(&"mandate_offered"))
	var eras: Node = root.get_node_or_null("Eras")
	if eras != null and eras.has_signal("era_changed"):
		eras.era_changed.connect(func(_p, _n): play_cue(&"era_transition"); _refresh_ambient())
	var unlocks: Node = root.get_node_or_null("Unlocks")
	if unlocks != null and unlocks.has_signal("surface_unlocked"):
		unlocks.surface_unlocked.connect(func(_id): play_cue(&"unlock_surfaced"))
	var chronicle: Node = root.get_node_or_null("Chronicle")
	if chronicle != null and chronicle.has_signal("chronicle_sealed"):
		chronicle.chronicle_sealed.connect(func(): play_cue(&"chronicle_seal"))
	_refresh_ambient()


func _install_pref_listener() -> void:
	if Prefs != null and Prefs.has_signal("preferences_changed"):
		Prefs.preferences_changed.connect(_apply_volumes)


func _apply_volumes() -> void:
	var music_v: float = 0.4
	var sfx_v: float = 0.6
	var ambient_v: float = 0.5
	if Prefs != null:
		music_v = Prefs.music_volume
		sfx_v = Prefs.sfx_volume
		ambient_v = Prefs.ambient_volume
	AudioServer.set_bus_volume_db(_master_bus, linear_to_db(1.0))
	AudioServer.set_bus_volume_db(_music_bus, linear_to_db(music_v))
	AudioServer.set_bus_volume_db(_sfx_bus, linear_to_db(sfx_v))
	AudioServer.set_bus_volume_db(_ambient_bus, linear_to_db(ambient_v))
	_refresh_ambient()


func _sfx_on() -> bool:
	if Prefs == null:
		return true
	return Prefs.sfx_enabled


func _ambient_on() -> bool:
	if Prefs == null:
		return true
	return Prefs.ambient_enabled


func _cue_stream(tag: StringName) -> AudioStream:
	if _cues.has(tag):
		return _cues[tag]
	var stream: AudioStreamWAV = ProceduralAudio.make_cue(tag)
	if stream == null:
		return null
	_cues[tag] = stream
	return stream


func _refresh_ambient() -> void:
	if _ambient_player == null:
		return
	if not _ambient_on():
		_ambient_player.stop()
		return
	var era_id: StringName = &""
	var eras: Node = get_tree().root.get_node_or_null("Eras")
	if eras != null and eras.has_method("current_id"):
		era_id = eras.current_id()
	var stream: AudioStream = ProceduralAudio.make_ambient(era_id)
	if stream == null:
		_ambient_player.stop()
		return
	if _ambient_player.stream == stream and _ambient_player.playing:
		return
	_ambient_player.stream = stream
	_ambient_player.play()
