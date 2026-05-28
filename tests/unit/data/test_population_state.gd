extends GutTest

func test_field_access():
	var ps := PopulationState.new()
	ps.place_id = &"athens"
	ps.total = 100000
	ps.birth_rate_per_1000 = 38.0
	ps.death_rate_per_1000 = 34.0
	assert_eq(ps.total, 100000)
	assert_eq(ps.birth_rate_per_1000, 38.0)

func test_period_delta_positive_growth():
	var ps := PopulationState.new()
	ps.total = 100000
	ps.birth_rate_per_1000 = 40.0
	ps.death_rate_per_1000 = 30.0
	ps.food_surplus_factor = 1.0
	ps.prosperity_factor = 1.0
	ps.stability_factor = 1.0
	ps.shock_factor = 1.0
	var delta: int = ps.period_delta()
	assert_gt(delta, 0, "Births > deaths should produce positive growth")

func test_period_delta_negative_with_scarcity():
	var ps := PopulationState.new()
	ps.total = 100000
	ps.birth_rate_per_1000 = 38.0
	ps.death_rate_per_1000 = 34.0
	ps.food_surplus_factor = 0.5  # scarcity — births halved, deaths increase
	ps.prosperity_factor = 0.8
	ps.stability_factor = 1.0
	ps.shock_factor = 1.0
	var delta: int = ps.period_delta()
	assert_lt(delta, 0, "Scarcity should shrink population")

func test_period_delta_shock_kills():
	var ps := PopulationState.new()
	ps.total = 100000
	ps.birth_rate_per_1000 = 38.0
	ps.death_rate_per_1000 = 34.0
	ps.food_surplus_factor = 1.0
	ps.prosperity_factor = 1.0
	ps.stability_factor = 1.0
	ps.shock_factor = 0.3  # plague/famine
	var delta: int = ps.period_delta()
	assert_lt(delta, 0, "Severe shock should overwhelm natural growth")

func test_save_load_roundtrip():
	var ps := PopulationState.new()
	ps.place_id = &"test_place"
	ps.total = 50000
	ps.weight_accumulators = {&"ambition": 1.5}
	var path := "user://test_population_state_roundtrip.tres"
	ResourceSaver.save(ps, path)
	var loaded: PopulationState = ResourceLoader.load(path) as PopulationState
	assert_not_null(loaded)
	assert_eq(loaded.total, 50000)
	DirAccess.remove_absolute(path)
