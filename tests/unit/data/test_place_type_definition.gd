extends GutTest


func test_field_access():
	var def := PlaceTypeDefinition.new()
	def.id = &"city"
	def.display_name = "City"
	def.is_settlement = true
	assert_eq(def.id, &"city")
	assert_eq(def.display_name, "City")
	assert_true(def.is_settlement)


func test_site_type():
	var def := PlaceTypeDefinition.new()
	def.id = &"mine"
	def.display_name = "Mine"
	def.is_settlement = false
	assert_false(def.is_settlement)


func test_save_load_roundtrip():
	var def := PlaceTypeDefinition.new()
	def.id = &"test_roundtrip"
	def.display_name = "Test Type"
	def.is_settlement = true

	var path: String = "user://test_place_type_roundtrip.tres"
	ResourceSaver.save(def, path)
	var loaded: PlaceTypeDefinition = ResourceLoader.load(path) as PlaceTypeDefinition

	assert_not_null(loaded, "Loaded resource should not be null")
	assert_eq(loaded.id, &"test_roundtrip")
	assert_eq(loaded.display_name, "Test Type")
	assert_true(loaded.is_settlement)

	DirAccess.remove_absolute(path)
