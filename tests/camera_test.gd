extends "res://tests/combat_test.gd"
## Headless camera checks: the overview-to-third-person zoom blend, wheel
## zoom, middle-mouse orbit, input that follows the rotated camera, mouse aim
## through the perspective camera, and the wall cutout (reuses the combat
## test's arena and helpers).
##   godot --headless --path . -s res://tests/camera_test.gd
## Exit code 0 = every check passed.


func _initialize() -> void:
	await process_frame
	await test_zoom_blend()
	await test_wheel_zoom()
	await test_orbit()
	await test_input_follows_camera()
	await test_mouse_aim()
	await test_wall_cutout()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_zoom_blend() -> void:
	print("1. Zoom blends the isometric overview into a third-person view")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	var rig := camera_rig
	rig.set_zoom(0.0, true)
	check(is_equal_approx(rig.get_pitch_degrees(), rig.overview_pitch_degrees)
		and is_equal_approx(rig.camera.fov, rig.overview_fov), "zoom 0: isometric pitch, narrow fov")
	check(absf(_view_height(rig) - rig.max_view_height) < 0.01,
		"zoom 0: shows %.1f m at the target" % _view_height(rig))
	check(rig.camera.projection == Camera3D.PROJECTION_PERSPECTIVE, "always perspective")
	rig.set_zoom(rig.overview_zoom_end, true)
	check(absf(_view_height(rig) - rig.min_view_height) < 0.01 and rig.get_close_blend() == 0.0,
		"end of the overview: %.1f m, still isometric" % _view_height(rig))
	rig.set_zoom(1.0, true)
	await ticks(2)
	check(is_equal_approx(rig.get_pitch_degrees(), rig.close_pitch_degrees)
		and is_equal_approx(rig.camera.fov, rig.close_fov), "zoom 1: flat pitch, wide fov")
	var look := player.global_position + Vector3.UP * rig.close_look_height
	var cam := rig.camera.global_position
	check(absf(cam.distance_to(look) - rig.close_distance) < 0.05,
		"zoom 1: camera %.2f m from the chest" % cam.distance_to(look))
	var to_player := (look - cam).normalized()
	check(to_player.dot(-rig.camera.global_basis.z) > 0.999, "zoom 1: looks at the character")
	# Continuous and monotonic: no jump anywhere along the wheel's range.
	var last_distance := INF
	var last_pitch := INF
	var smooth := true
	for i in 101:
		rig.set_zoom(i / 100.0, true)
		var d := rig.get_distance()
		var p := rig.get_pitch_degrees()
		if d > last_distance or p > last_pitch + 0.0001 or (i > 0 and last_distance - d > 0.25 * last_distance):
			smooth = false
		if rig.camera.global_position.y < 0.5:
			smooth = false
		last_distance = d
		last_pitch = p
	check(smooth, "distance and pitch fall smoothly, camera stays above the floor")
	await clear_arena()


func test_wheel_zoom() -> void:
	print("2. The mouse wheel steps the zoom and it glides there")
	await make_arena()
	spawn_player(Vector3.ZERO)
	var rig := camera_rig
	rig.set_zoom(0.3, true)
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	await ticks(1)
	check(is_equal_approx(rig.get_zoom_goal(), 0.3 + rig.zoom_step), "wheel up zooms in one step")
	check(rig.zoom < rig.get_zoom_goal(), "glides rather than jumps")
	await ticks(60)
	check(is_equal_approx(rig.zoom, rig.get_zoom_goal()), "reaches the new zoom")
	for i in 20:
		_wheel(MOUSE_BUTTON_WHEEL_UP)
	await ticks(1)
	check(rig.get_zoom_goal() == 1.0, "clamped at the closest view")
	for i in 20:
		_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	await ticks(1)
	check(rig.get_zoom_goal() == 0.0, "clamped at the furthest view")
	await clear_arena()


func test_orbit() -> void:
	print("3. Middle-mouse drag orbits the camera around the target")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	var rig := camera_rig
	await ticks(2)
	var start_yaw := rig.yaw_degrees
	_motion(Vector2(100, 0))
	await ticks(1)
	check(rig.yaw_degrees == start_yaw, "moving the mouse alone doesn't rotate")
	_button(MOUSE_BUTTON_MIDDLE, true)
	_motion(Vector2(100, 0))
	await ticks(1)
	var turned := rig.yaw_degrees - start_yaw
	check(absf(turned + 100.0 * rig.rotate_sensitivity) < 0.01, "dragging turns the yaw (%.1f°)" % turned)
	var flat_distance := flat(rig.camera.global_position - player.global_position).length()
	_motion(Vector2(-300, 0))
	await ticks(1)
	check(absf(flat(rig.camera.global_position - player.global_position).length() - flat_distance) < 0.05,
		"orbits at a constant distance")
	_button(MOUSE_BUTTON_MIDDLE, false)
	var released_yaw := rig.yaw_degrees
	_motion(Vector2(100, 0))
	await ticks(1)
	check(rig.yaw_degrees == released_yaw, "releasing stops the rotation")
	check(not player.lock_on.is_locked(), "middle mouse no longer locks on")
	await clear_arena()


func test_input_follows_camera() -> void:
	print("4. WASD follows the rotated camera")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	var rig := camera_rig
	for yaw: float in [45.0, 160.0, -100.0]:
		rig.set_yaw(yaw)
		rig.set_zoom(1.0 if yaw < 0.0 else 0.3, true)
		await ticks(1)
		var forward := flat(-rig.camera.global_basis.z).normalized()
		var start := player.global_position
		Input.action_press("move_forward")
		await ticks(30)
		Input.action_release("move_forward")
		var moved := flat(player.global_position - start)
		check(moved.length() > 1.0 and moved.normalized().dot(forward) > 0.98,
			"yaw %d°: W moves away from the camera (dot %.3f)" % [yaw, moved.normalized().dot(forward)])
		await ticks(30)
	await clear_arena()


func test_mouse_aim() -> void:
	print("5. Mouse aim picks the right ground point through the perspective camera")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	var rig := camera_rig
	var ok := true
	for setting: Array in [[0.0, 45.0], [0.3, 120.0], [0.75, -30.0], [1.0, 200.0]]:
		rig.set_zoom(setting[0], true)
		rig.set_yaw(setting[1])
		await ticks(2)
		for dir: Vector3 in [Vector3.RIGHT, Vector3.FORWARD, Vector3(-1, 0, 1).normalized()]:
			var ground := player.global_position + dir * 3.0
			if rig.camera.is_position_behind(ground):
				continue  # Behind a close third-person camera: off screen.
			var screen := rig.camera.unproject_position(ground)
			var aim := player.get_aim_direction_at(screen)
			if aim.dot(dir) < 0.999:
				ok = false
				print("     zoom %.2f yaw %d: aim %s for %s" % [setting[0], setting[1], aim, dir])
	check(ok, "the cursor's ground point gives the aim direction at every zoom and yaw")
	await clear_arena()


func test_wall_cutout() -> void:
	print("6. Walls are full height and cut away on the camera side of the player")
	var built := DungeonBuilder.new().build(Dungeon01Layout.create(), "Dungeon01")
	root.add_child(built)
	await process_frame
	var mesh := built.get_node("NavigationRegion3D/Walls/Mesh") as MeshInstance3D
	var mat := mesh.get_active_material(0) as ShaderMaterial if mesh else null
	check(mat != null and mat.shader == DungeonBuilder.WALL_SHADER, "walls use the cutout shader")
	check(built.find_child("LowMesh", true, false) == null, "no low walls left")
	var aabb := mesh.get_aabb() if mesh else AABB()
	check(is_equal_approx(aabb.size.y, DungeonBuilder.WALL_HEIGHT), "walls %.1f m tall" % aabb.size.y)
	built.queue_free()
	await process_frame
	await make_arena()
	var player := spawn_player(Vector3(2, 0, 1))
	var rig := camera_rig
	rig.set_zoom(0.3, true)
	await ticks(2)
	# The headless renderer is a dummy: read the values the rig last sent.
	check(rig.cutout_target.is_equal_approx(player.global_position + Vector3.UP * rig.cutout_target_height),
		"cutout aimed at the player (%s)" % rig.cutout_target)
	check(rig.cutout_camera.is_equal_approx(rig.camera.global_position), "cutout starts at the camera")
	check(is_equal_approx(rig.cutout_radius, rig.overview_cutout_radius),
		"overview hole radius %.1f m" % rig.cutout_radius)
	check(is_equal_approx(rig.cutout_front_width, rig.overview_front_width),
		"overview: walls on the camera side cut %.0f m to either side" % rig.cutout_front_width)
	rig.set_zoom(1.0, true)
	await ticks(2)
	check(is_equal_approx(rig.cutout_radius, rig.close_cutout_radius),
		"close-up hole radius %.1f m" % rig.cutout_radius)
	check(is_equal_approx(rig.cutout_front_width, rig.close_front_width),
		"close-up: only what stands between camera and player (%.1f m)" % rig.cutout_front_width)
	var names := RenderingServer.global_shader_parameter_get_list()
	check(names.has(&"cutout_camera") and names.has(&"cutout_target") and names.has(&"cutout_radius")
		and names.has(&"cutout_front_width") and names.has(&"cutout_stub_height"),
		"shader globals registered (project.godot)")
	await clear_arena()


## Visible height (m) at the look point for the camera's current fov/distance.
func _view_height(rig: IsoCameraRig) -> float:
	return 2.0 * rig.get_distance() * tan(deg_to_rad(rig.camera.fov) * 0.5)


func _wheel(button: MouseButton) -> void:
	_button(button, true)
	_button(button, false)


func _button(button: MouseButton, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()


func _motion(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = relative
	event.screen_relative = relative
	Input.parse_input_event(event)
	Input.flush_buffered_events()
