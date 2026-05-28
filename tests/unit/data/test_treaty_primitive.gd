extends GutTest

func test_field_access():
	var p := TreatyPrimitive.new()
	p.id = &"prim_share_intel"
	p.category = &"information"
	p.kind = &"share_intelligence"
	p.direction = &"two_way"
	p.description = "Mutual intelligence sharing on third parties"
	assert_eq(p.id, &"prim_share_intel")
	assert_eq(p.category, &"information")
	assert_eq(p.kind, &"share_intelligence")
	assert_eq(p.direction, &"two_way")

func test_parameters_dictionary():
	var p := TreatyPrimitive.new()
	p.category = &"resource"
	p.kind = &"transfer_silver"
	p.parameters = {"type": &"transfer_silver", "amount": 500, "schedule": &"one_time"}
	assert_eq(p.parameters["amount"], 500)
	assert_eq(p.parameters["schedule"], &"one_time")

func test_save_load_roundtrip():
	var p := TreatyPrimitive.new()
	p.id = &"roundtrip_prim"
	p.category = &"restraint"
	p.kind = &"no_host_recruitment"
	p.direction = &"two_way"
	var path := "user://test_treaty_primitive_roundtrip.tres"
	ResourceSaver.save(p, path)
	var loaded: TreatyPrimitive = ResourceLoader.load(path) as TreatyPrimitive
	assert_not_null(loaded)
	assert_eq(loaded.id, &"roundtrip_prim")
	assert_eq(loaded.category, &"restraint")
	DirAccess.remove_absolute(path)
