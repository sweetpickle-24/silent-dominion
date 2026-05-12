extends GutTest

func test_field_access():
	var r := RouteRecord.new()
	r.id = &"test_route"
	r.name = "Test Route"
	r.kind = &"sea"
	r.tier = &"major"
	r.waypoints.append(&"athens")
	r.waypoints.append(&"miletus")
	assert_eq(r.id, &"test_route")
	assert_eq(r.kind, &"sea")
	assert_eq(r.waypoints.size(), 2)

func test_save_load_roundtrip():
	var r := RouteRecord.new()
	r.id = &"roundtrip_route"
	r.name = "Roundtrip"
	r.kind = &"overland"
	r.tier = &"minor"
	r.waypoints.append(&"babylon")
	r.line_thickness = 3.0
	var path := "user://test_route_roundtrip.tres"
	ResourceSaver.save(r, path)
	var loaded: RouteRecord = ResourceLoader.load(path) as RouteRecord
	assert_not_null(loaded)
	assert_eq(loaded.id, &"roundtrip_route")
	assert_eq(loaded.kind, &"overland")
	assert_eq(loaded.line_thickness, 3.0)
	DirAccess.remove_absolute(path)
