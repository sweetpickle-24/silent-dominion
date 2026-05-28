extends GutTest

func test_diffuse_step_transfers():
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var engine := DiffusionEngine.new(rng)
	var presence: Dictionary = {
		&"a": {&"entity1": 100.0},
		&"b": {},
	}
	var edges: Array = [{"from": &"a", "to": &"b", "weight": 1.0}]
	var transfer_fn := func(_from, _to, _entity, _w, from_mag): return from_mag * 0.05
	var deltas: Dictionary = engine.diffuse_step(presence, edges, transfer_fn)
	assert_true(deltas.has(&"b"), "Target should receive transfer")
	assert_gt(deltas[&"b"][&"entity1"], 0.0, "Transfer should be positive")


func test_apply_deltas():
	var engine := DiffusionEngine.new()
	var presence: Dictionary = {&"a": {&"e1": 50.0}, &"b": {&"e1": 10.0}}
	var deltas: Dictionary = {&"a": {&"e1": -5.0}, &"b": {&"e1": 5.0}}
	engine.apply_deltas(presence, deltas)
	assert_eq(presence[&"a"][&"e1"], 45.0)
	assert_eq(presence[&"b"][&"e1"], 15.0)


func test_apply_deltas_removes_zero():
	var engine := DiffusionEngine.new()
	var presence: Dictionary = {&"a": {&"e1": 0.001}}
	var deltas: Dictionary = {&"a": {&"e1": -0.001}}
	engine.apply_deltas(presence, deltas)
	assert_false(presence[&"a"].has(&"e1"), "Near-zero should be removed")


func test_edge_weights_affect_transfer():
	var engine := DiffusionEngine.new()
	var presence: Dictionary = {&"a": {&"e1": 100.0}, &"b": {}, &"c": {}}
	var edges: Array = [
		{"from": &"a", "to": &"b", "weight": 1.0},
		{"from": &"a", "to": &"c", "weight": 3.0},
	]
	var transfer_fn := func(_from, _to, _entity, w, from_mag): return from_mag * 0.01 * w
	var deltas: Dictionary = engine.diffuse_step(presence, edges, transfer_fn)
	var to_b: float = deltas.get(&"b", {}).get(&"e1", 0.0)
	var to_c: float = deltas.get(&"c", {}).get(&"e1", 0.0)
	assert_gt(to_c, to_b, "Higher weight edge should transfer more")


func test_threshold_crossings():
	var engine := DiffusionEngine.new()
	var prev: Dictionary = {&"a": {&"e1": 3.0}}
	var curr: Dictionary = {&"a": {&"e1": 12.0}}
	var crossings: Array = engine.find_threshold_crossings(curr, 10.0, prev)
	assert_eq(crossings.size(), 1)
	assert_eq(crossings[0]["node_id"], &"a")
	assert_eq(crossings[0]["entity_id"], &"e1")


func test_deterministic_with_seed():
	var rng1 := RandomNumberGenerator.new()
	rng1.seed = 12345
	var engine1 := DiffusionEngine.new(rng1)
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 12345
	var engine2 := DiffusionEngine.new(rng2)
	var presence: Dictionary = {&"a": {&"e1": 100.0}, &"b": {}}
	var edges: Array = [{"from": &"a", "to": &"b", "weight": 1.0}]
	var transfer_fn := func(_from, _to, _entity, _w, from_mag): return from_mag * 0.05
	var d1: Dictionary = engine1.diffuse_step(presence, edges, transfer_fn)
	var d2: Dictionary = engine2.diffuse_step(presence, edges, transfer_fn)
	assert_eq(d1, d2, "Same seed should produce same result")
