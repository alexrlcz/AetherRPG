extends SceneTree
## Saves the first dungeon (Dungeon01Layout: the Dungeon Scrawl map plus its
## props) as a scene with a baked navmesh, using the runtime DungeonBuilder.
##
## Run:  godot --headless --path . -s res://tools/build_dungeon.gd
## Re-run after editing the .ds map or Dungeon01Layout's prop table. Hand edits
## to the generated scene are overwritten: change the layout or the builder
## instead.

const OUTPUT := "res://scenes/world/dungeon_01.tscn"
const NAVMESH_OUTPUT := "res://resources/navigation/dungeon_01_navmesh.tres"


func _initialize() -> void:
	var layout := Dungeon01Layout.create()
	if layout == null:
		quit(1)
		return
	var root := DungeonBuilder.new().build(layout, "Dungeon01")
	get_root().add_child(root)
	await process_frame
	var nav := DungeonBuilder.bake_navigation(root, false)
	var polys := nav.navigation_mesh.get_polygon_count()
	if polys == 0:
		push_error("build_dungeon: navmesh bake produced no polygons")
		quit(1)
		return
	ResourceSaver.save(nav.navigation_mesh, NAVMESH_OUTPUT)
	nav.navigation_mesh = load(NAVMESH_OUTPUT)
	for marker in root.get_node("Markers").get_children():
		print("build_dungeon: marker %s at %s" % [marker.name, marker.position])

	_set_owner_recursive(root, root)
	# Keep the scene's UID: other scenes (main.tscn) reference it by UID.
	var uid := ResourceLoader.get_resource_uid(OUTPUT) if ResourceLoader.exists(OUTPUT) \
		else ResourceUID.INVALID_ID
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err == OK:
		err = ResourceSaver.save(packed, OUTPUT)
	if err == OK and uid != ResourceUID.INVALID_ID:
		err = ResourceSaver.set_uid(OUTPUT, uid)
	print("build_dungeon: %s (%d navmesh polygons) -> %s" % [error_string(err), polys, OUTPUT])
	quit(0 if err == OK else 1)


func _set_owner_recursive(node: Node, owner_node: Node) -> void:
	for child in node.get_children():
		child.owner = owner_node
		# Instanced scenes keep their own internals.
		if child.scene_file_path.is_empty():
			_set_owner_recursive(child, owner_node)
