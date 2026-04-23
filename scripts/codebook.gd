extends Node
## §D1 — Codebook autoload.
##
## Holds the player's active ciphers and the contacts keyed to them.
## A cipher is a named rotation/codeword pair shared with a specific
## contact; any letter stamped with `cipher_id` can only be read by
## the player if that cipher is in `known_ciphers`.
##
## At campaign start we seed exactly one cipher — `cipher_starter_coord`
## — shared with the starter coordinator. All other letters (beats,
## digests, action reports) remain plaintext until the player opens
## a new ciphered channel.

signal ciphers_changed
signal contacts_changed

# cipher_id -> { display: String, opened_day: int, contact_actor_id: StringName }
var ciphers: Dictionary = {}

# actor_id (StringName) -> cipher_id (StringName)
var contact_cipher: Dictionary = {}

const STARTER_CIPHER: StringName    = &"cipher_starter_coord"
const STARTER_CONTACT: StringName   = &"starter_coordinator_athens"


func _ready() -> void:
	DevLogger.write("Codebook: ready")
	if WorldData != null and not WorldData.is_loaded():
		WorldData.world_loaded.connect(_seed_starter_cipher, CONNECT_ONE_SHOT)
	else:
		call_deferred("_seed_starter_cipher")


func _seed_starter_cipher() -> void:
	if ciphers.has(STARTER_CIPHER):
		return
	ciphers[STARTER_CIPHER] = {
		"display":          "Athenian-Chalkidic rotation",
		"opened_day":       GameClock.absolute_day(),
		"contact_actor_id": STARTER_CONTACT,
	}
	contact_cipher[STARTER_CONTACT] = STARTER_CIPHER
	ciphers_changed.emit()
	contacts_changed.emit()


func knows_cipher(id: StringName) -> bool:
	return ciphers.has(id)


func known_ciphers() -> Array[StringName]:
	var out: Array[StringName] = []
	for k in ciphers.keys():
		out.append(k)
	return out


func cipher_display(id: StringName) -> String:
	var d = ciphers.get(id, null)
	if d == null:
		return String(id)
	return String(d.get("display", String(id)))


## All actors the player has an open cipher channel with.
func contacts() -> Array[Actor]:
	var out: Array[Actor] = []
	for aid in contact_cipher.keys():
		var a: Actor = Actors.get_actor(StringName(aid))
		if a != null:
			out.append(a)
	return out


func cipher_for_contact(actor_id: StringName) -> StringName:
	return StringName(contact_cipher.get(actor_id, &""))


## Open a new cipher channel with an actor. Used by the Codebook
## view when the player commits to sealing a correspondence under a
## new cipher. Idempotent.
func open_cipher_with(actor_id: StringName, display: String = "") -> StringName:
	if contact_cipher.has(actor_id):
		return StringName(contact_cipher[actor_id])
	var new_id: StringName = StringName("cipher_%s_%d" % [String(actor_id), Time.get_ticks_msec()])
	var label: String = display
	if label.is_empty():
		var a: Actor = Actors.get_actor(actor_id)
		label = "Cipher with %s" % (a.display_name() if a != null else String(actor_id))
	ciphers[new_id] = {
		"display":          label,
		"opened_day":       GameClock.absolute_day(),
		"contact_actor_id": actor_id,
	}
	contact_cipher[actor_id] = new_id
	ciphers_changed.emit()
	contacts_changed.emit()
	return new_id


# --- Save / load -----------------------------------------------------------

func snapshot() -> Dictionary:
	return {
		"ciphers":        ciphers.duplicate(true),
		"contact_cipher": contact_cipher.duplicate(true),
	}


func restore(data: Dictionary) -> void:
	ciphers = {}
	contact_cipher = {}
	var raw_c: Variant = data.get("ciphers", {})
	if raw_c is Dictionary:
		for k in (raw_c as Dictionary).keys():
			ciphers[StringName(String(k))] = raw_c[k]
	var raw_cc: Variant = data.get("contact_cipher", {})
	if raw_cc is Dictionary:
		for k in (raw_cc as Dictionary).keys():
			contact_cipher[StringName(String(k))] = StringName(String(raw_cc[k]))
	ciphers_changed.emit()
	contacts_changed.emit()
