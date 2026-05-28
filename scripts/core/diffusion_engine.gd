# Shared diffusion engine used by ReligionIdeology and Languages mechanics.
# Walks a graph per period, computes weighted transfers between nodes,
# applies deltas. The transfer-rate function is caller-specific.
class_name DiffusionEngine
extends RefCounted

var _rng: RandomNumberGenerator


func _init(rng: RandomNumberGenerator = null) -> void:
	_rng = rng if rng != null else RandomNumberGenerator.new()


# Run one diffusion step across the graph.
# presence: Dictionary[node_id -> Dictionary[entity_id -> float magnitude]]
# edges: Array of {from: StringName, to: StringName, weight: float}
# transfer_fn: Callable(from_node, to_node, entity_id, edge_weight, from_magnitude) -> float delta
# Returns: Dictionary[node_id -> Dictionary[entity_id -> float delta]] of changes to apply.
func diffuse_step(
	presence: Dictionary,
	edges: Array,
	transfer_fn: Callable,
) -> Dictionary:
	var deltas: Dictionary = {}  # node_id -> {entity_id -> float}
	for edge: Dictionary in edges:
		var from_id: StringName = edge["from"]
		var to_id: StringName = edge["to"]
		var edge_weight: float = edge.get("weight", 1.0)
		var from_entities: Dictionary = presence.get(from_id, {})
		for entity_id: StringName in from_entities.keys():
			var from_mag: float = from_entities[entity_id]
			if from_mag <= 0.0:
				continue
			var transfer: float = transfer_fn.call(from_id, to_id, entity_id, edge_weight, from_mag)
			if transfer <= 0.0:
				continue
			# Clamp transfer to not exceed source
			transfer = minf(transfer, from_mag * 0.1)  # max 10% of source per edge per step
			# Apply to deltas
			_add_delta(deltas, to_id, entity_id, transfer)
			_add_delta(deltas, from_id, entity_id, -transfer * 0.1)  # source loses a fraction (not all — spread, not migration)
	return deltas


# Apply computed deltas to the presence map in-place.
func apply_deltas(presence: Dictionary, deltas: Dictionary) -> void:
	for node_id: StringName in deltas.keys():
		if not presence.has(node_id):
			presence[node_id] = {}
		var node_deltas: Dictionary = deltas[node_id]
		for entity_id: StringName in node_deltas.keys():
			var current: float = presence[node_id].get(entity_id, 0.0)
			var new_val: float = maxf(current + node_deltas[entity_id], 0.0)
			if new_val > 0.001:
				presence[node_id][entity_id] = new_val
			else:
				presence[node_id].erase(entity_id)


# Check threshold crossings. Returns array of {node_id, entity_id, value}
# for entries that crossed above the threshold.
func find_threshold_crossings(
	presence: Dictionary,
	threshold: float,
	previous_presence: Dictionary = {},
) -> Array:
	var crossings: Array = []
	for node_id: StringName in presence.keys():
		var entities: Dictionary = presence[node_id]
		for entity_id: StringName in entities.keys():
			var current: float = entities[entity_id]
			var previous: float = 0.0
			if previous_presence.has(node_id):
				previous = previous_presence[node_id].get(entity_id, 0.0)
			if current >= threshold and previous < threshold:
				crossings.append({"node_id": node_id, "entity_id": entity_id, "value": current})
	return crossings


func _add_delta(deltas: Dictionary, node_id: StringName, entity_id: StringName, amount: float) -> void:
	if not deltas.has(node_id):
		deltas[node_id] = {}
	var current: float = deltas[node_id].get(entity_id, 0.0)
	deltas[node_id][entity_id] = current + amount
