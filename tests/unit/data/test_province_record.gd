extends GutTest

func test_field_access():
	var p := ProvinceRecord.new()
	p.id = &"test_province"
	p.name = "Test Province"
	p.cultural_sphere = &"greek"
	p.terrain = TerrainValues.MOUNTAINS
	p.climate = ClimateValues.MEDITERRANEAN
	p.center_lat = 38.0
	p.center_lon = 23.7
	p.neighbors.append(&"neighbor_1")
	assert_eq(p.id, &"test_province")
	assert_eq(p.cultural_sphere, &"greek")
	assert_eq(p.neighbors.size(), 1)

func test_is_adjacent_to():
	var p := ProvinceRecord.new()
	p.neighbors.append(&"boeotia")
	p.neighbors.append(&"corinthia")
	assert_true(p.is_adjacent_to(&"boeotia"))
	assert_false(p.is_adjacent_to(&"persis"))

func test_shares_cultural_sphere():
	var a := ProvinceRecord.new()
	a.cultural_sphere = &"greek"
	var b := ProvinceRecord.new()
	b.cultural_sphere = &"greek"
	var c := ProvinceRecord.new()
	c.cultural_sphere = &"persian"
	assert_true(a.shares_cultural_sphere_with(b))
	assert_false(a.shares_cultural_sphere_with(c))
	assert_false(a.shares_cultural_sphere_with(null))

func test_save_load_roundtrip():
	var p := ProvinceRecord.new()
	p.id = &"roundtrip_prov"
	p.name = "Roundtrip"
	p.cultural_sphere = &"latin"
	p.terrain = &"hills"
	p.center_lat = 41.9
	p.center_lon = 12.5
	p.neighbors.append(&"etruria")
	var path := "user://test_province_roundtrip.tres"
	ResourceSaver.save(p, path)
	var loaded: ProvinceRecord = ResourceLoader.load(path) as ProvinceRecord
	assert_not_null(loaded)
	assert_eq(loaded.id, &"roundtrip_prov")
	assert_eq(loaded.cultural_sphere, &"latin")
	assert_eq(loaded.neighbors.size(), 1)
	DirAccess.remove_absolute(path)
