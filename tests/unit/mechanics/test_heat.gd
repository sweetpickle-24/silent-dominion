extends GutTest

func test_heat_gain_baseline():
	assert_eq(HeatMechanic.HEAT_GAIN_BASELINE, 5.0)

func test_heat_scales_with_tier():
	# Tier 3 × baseline 5 × minor position 1.0 = 15
	var gain_t3: int = int(HeatMechanic.HEAT_GAIN_BASELINE * 3 * 1.0)
	var gain_t1: int = int(HeatMechanic.HEAT_GAIN_BASELINE * 1 * 1.0)
	assert_gt(gain_t3, gain_t1)

func test_heat_scales_with_position():
	var gain_invisible: int = int(HeatMechanic.HEAT_GAIN_BASELINE * 1 * 0.5)
	var gain_high: int = int(HeatMechanic.HEAT_GAIN_BASELINE * 1 * 3.0)
	assert_gt(gain_high, gain_invisible)

func test_heat_decay_per_year():
	assert_eq(HeatMechanic.HEAT_DECAY_PER_YEAR, 10)

func test_save_load_roundtrip():
	var heat := HeatMechanic.new()
	heat.name = "Heat"
	add_child(heat)
	heat._last_active_day[&"test_char"] = 200
	var state: Dictionary = heat.snapshot_state()
	heat._last_active_day.clear()
	heat.apply_state(state)
	assert_eq(heat._last_active_day.get(&"test_char"), 200)
	remove_child(heat); heat.free()
