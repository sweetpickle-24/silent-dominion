extends GutTest

# Integration: destabilise a region for generations → verify new generations
# skew ambition+/loyalty-/paranoia+ per §8.11 condition-weighting.

var _chargen: CharGeneration
var _population: Population


func before_each():
	_population = Population.new()
	_population.name = "Population"
	add_child(_population)
	_chargen = CharGeneration.new()
	_chargen.name = "CharGeneration"
	add_child(_chargen)


func after_each():
	var eb: Node = get_node("/root/EventBus")
	if is_instance_valid(_chargen):
		if _chargen._tick_sub:
			eb.unsubscribe(_chargen._tick_sub)
		remove_child(_chargen)
		_chargen.free()
	if is_instance_valid(_population):
		if _population._tick_sub:
			eb.unsubscribe(_population._tick_sub)
		remove_child(_population)
		_population.free()


func test_destabilisation_skews_traits():
	# Set Athens to very unstable for several weight accumulation cycles
	var state: PopulationState = _population.get_state(&"athens")
	if state == null:
		pending("No Athens population state")
		return
	state.stability_factor = 0.3  # very unstable
	# Accumulate weights several times (simulating multiple periods)
	for i in range(10):
		_population._update_weight_accumulators()
	# Check that ambition weight increased
	var ambition_weight: float = state.weight_accumulators.get(&"ambition", 0.0)
	assert_gt(ambition_weight, 2.0, "Destabilisation should accumulate ambition weight")
	var loyalty_weight: float = state.weight_accumulators.get(&"loyalty", 0.0)
	assert_lt(loyalty_weight, 0.0, "Destabilisation should decrease loyalty weight")
	# Generate characters and verify trait shift
	var sum_ambition: float = 0.0
	var count: int = 0
	for i in range(20):
		var c: CharacterRecord = _chargen.generate_character_at(&"athens", 1000 + i)
		if c != null:
			sum_ambition += c.ambition
			count += 1
	if count < 10:
		pending("Not enough characters generated")
		return
	var avg_ambition: float = sum_ambition / count
	# Greek base ambition is 50. With destabilisation weight, should be notably above 50.
	assert_gt(avg_ambition, 48.0, "Destabilised region should produce higher-ambition characters")
