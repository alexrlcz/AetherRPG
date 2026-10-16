extends "res://tests/combat_test.gd"
## Headless lock-on and attack-direction checks on the real player and enemy
## scenes (reuses the combat test's arena and helpers).
##   godot --headless --path . -s res://tests/lock_on_test.gd
## Exit code 0 = every check passed.


func _initialize() -> void:
	await process_frame
	await test_lock_and_cycle()
	await test_locked_facing_and_movement()
	await test_attack_direction()
	await test_target_death()
	await test_lock_breaks()
	await test_directional_locomotion()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_lock_and_cycle() -> void:
	print("1. Lock nearest, cycle by distance, range limit")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	var near := spawn_enemy(Vector3(0, 0, -3), true)
	var mid := spawn_enemy(Vector3(5, 0, 3), true)
	var far := spawn_enemy(Vector3(-8, 0, 4), true)
	var out_of_range := spawn_enemy(Vector3(13, 0, -12), true)  # 17.7 m
	await ticks(3)
	var lock := player.lock_on
	check(not lock.is_locked(), "starts unlocked")
	lock.toggle()
	check(lock.target == near, "lock picks the nearest enemy")
	var marker := lock.get_node("LockMarker") as Node3D
	check(marker.visible, "lock marker shown")
	lock.cycle()
	check(lock.target == mid, "Tab -> next nearest")
	lock.cycle()
	check(lock.target == far, "Tab -> farthest in range")
	lock.cycle()
	check(lock.target == near, "Tab wraps back to the nearest")
	var seen_out := false
	for i in 4:
		lock.cycle()
		seen_out = seen_out or lock.target == out_of_range
	check(not seen_out, "enemy beyond lock range is never picked")
	lock.toggle()
	check(not lock.is_locked() and not marker.visible, "middle mouse again releases")
	lock.cycle()
	check(lock.target == near, "Tab with no lock locks the nearest")
	await clear_arena()


func test_locked_facing_and_movement() -> void:
	print("2. Locked: faces the target and strafes")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	var enemy := spawn_enemy(Vector3(4, 0, 0), true)
	await ticks(3)
	player.lock_on.toggle()
	await ticks(40)
	check(_facing_dot(player, enemy) > 0.98, "turns to face the target (dot %.3f)" % _facing_dot(player, enemy))
	check(player.is_strafing, "reports strafing for the animator")
	Input.action_press("move_forward")
	var start := player.global_position
	var min_dot := 1.0
	for i in 40:
		await physics_frame
		if i > 10:
			min_dot = minf(min_dot, _facing_dot(player, enemy))
	Input.action_release("move_forward")
	var moved := player.global_position - start
	check(moved.length() > 1.0, "moves while locked (%.2f m)" % moved.length())
	check(min_dot > 0.97, "keeps facing the target while moving (min dot %.3f)" % min_dot)
	await clear_arena()


func test_attack_direction() -> void:
	print("3. Attack direction: facing / cursor / lock")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(3)
	# Model faces +X; the "cursor" (aim_override) points -Z.
	_face(player, Vector3.RIGHT)
	await ticks(2)
	player.request_attack(false)
	await _wait_strike(player)
	var dir := _forward(player)
	check(dir.dot(Vector3.RIGHT) > 0.98, "no aim, no lock: attacks where the model faces (%s)" % dir)
	await _wait_idle(player)

	_face(player, Vector3.RIGHT)
	Input.action_press("aim")
	await ticks(1)
	player.request_attack(false)
	await _wait_strike(player)
	dir = _forward(player)
	check(dir.dot(Vector3.FORWARD) > 0.95, "holding aim: attacks toward the cursor (%s)" % dir)
	await _wait_idle(player)

	# Locked on a target behind; aim held too -> the lock wins.
	var enemy := spawn_enemy(Vector3(0, 0, 4), true)
	await ticks(3)
	_face(player, Vector3.RIGHT)
	player.lock_on.toggle()
	player.request_attack(false)
	await _wait_strike(player)
	check(_facing_dot(player, enemy) > 0.95, "locked: attacks toward the target, over the cursor (dot %.3f)" % _facing_dot(player, enemy))
	Input.action_release("aim")
	await clear_arena()


func test_target_death() -> void:
	print("4. Target death moves the lock")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	var first := spawn_enemy(Vector3(0, 0, -3), true)
	var second := spawn_enemy(Vector3(0, 0, 6), true)
	await ticks(3)
	player.lock_on.toggle()
	first.health.take_damage(10000)
	await ticks(2)
	check(player.lock_on.target == second, "lock jumps to the next-nearest enemy")
	second.health.take_damage(10000)
	await ticks(2)
	check(not player.lock_on.is_locked(), "lock releases when no enemy is left")
	player.lock_on.cycle()
	check(not player.lock_on.is_locked(), "dead enemies can't be locked")
	await clear_arena()


func test_lock_breaks() -> void:
	print("5. Lock breaks on distance, sight and player death")
	await make_arena([[Vector3(0, 1.5, -5), Vector3(6, 3, 0.4)]])  # wall at z = -5
	var player := spawn_player(Vector3.ZERO)
	var enemy := spawn_enemy(Vector3(3, 0, 0), true)
	var hidden := spawn_enemy(Vector3(0, 0, -7), true)
	await ticks(3)
	check(not player.lock_on.get_candidates().has(hidden), "enemy behind a wall can't be locked")
	player.lock_on.toggle()
	enemy.global_position = Vector3(21, 0, 0)
	await ticks(2)
	check(not player.lock_on.is_locked(), "lock breaks beyond break range")

	enemy.global_position = Vector3(3, 0, 0)
	await ticks(2)
	player.lock_on.toggle()
	# Behind the wall; held there (an idle enemy walks back home).
	for i in 30:
		enemy.global_position = Vector3(1, 0, -7)
		await physics_frame
	check(player.lock_on.target == enemy, "lock survives a brief loss of sight")
	for i in 45:
		enemy.global_position = Vector3(1, 0, -7)
		await physics_frame
	check(not player.lock_on.is_locked(), "lock breaks after %.1f s out of sight" % player.lock_on.lose_sight_time)

	enemy.global_position = Vector3(3, 0, 0)
	await ticks(2)
	player.lock_on.toggle()
	player.health.take_damage(100000)
	await ticks(2)
	check(not player.lock_on.is_locked(), "player death releases the lock")
	await clear_arena()


func test_directional_locomotion() -> void:
	print("6. Locked-on movement plays strafe / backward clips at reduced speed")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	# Target straight up the screen, so WASD moves at 0 / 90 / 180 degrees
	# off the facing (the iso camera is rotated against the world axes).
	var up_screen := -camera_rig.camera.global_basis.z
	up_screen.y = 0.0
	var enemy := spawn_enemy(up_screen.normalized() * 9.0, true)
	await ticks(3)
	player.lock_on.toggle()
	await ticks(20)
	var ap: AnimationPlayer = player.get_node("Visual/Model/AnimationPlayer")
	for action in ["move_forward", "move_left", "move_right", "move_back"]:
		Input.action_press(action)
		await ticks(45)
		var v := Vector3(player.velocity.x, 0, player.velocity.z)
		var forward := -player.global_basis.z
		var angle := rad_to_deg(atan2(v.dot(player.global_basis.x), v.dot(forward)))
		var anim := ap.current_animation
		var expected := ""
		if absf(angle) < 55.0:
			expected = "Jog_Fwd"
		elif absf(angle) < 115.0:
			expected = "MX/Strafe_R" if angle > 0.0 else "MX/Strafe_L"
		elif absf(angle) < 160.0:
			expected = "MX/Jog_Bwd_R" if angle > 0.0 else "MX/Jog_Bwd_L"
		else:
			expected = "MX/Jog_Bwd"
		check(anim == expected, "%s: moving %.0f° off facing plays %s (got %s)" % [action, angle, expected, anim])
		if absf(angle) > 60.0:
			check(v.length() < player.move_speed * 0.7,
				"%s: slower than full speed (%.2f m/s)" % [action, v.length()])
		Input.action_release(action)
		await ticks(20)
	check(_facing_dot(player, enemy) > 0.95, "kept facing the target throughout")
	player.lock_on.release()
	Input.action_press("move_back")
	await ticks(45)
	check(ap.current_animation == "Jog_Fwd", "unlocked: moving plays the forward cycle (%s)" % ap.current_animation)
	check(player.velocity.length() > player.move_speed * 0.9, "unlocked: full speed")
	Input.action_release("move_back")
	await clear_arena()


# --- Helpers -----------------------------------------------------------------

func _face(player: PlayerController, dir: Vector3) -> void:
	player.facing_direction = dir
	player.rotation.y = atan2(-dir.x, -dir.z)


func _forward(player: PlayerController) -> Vector3:
	var f := -player.global_basis.z
	f.y = 0.0
	return f.normalized()


func _facing_dot(player: PlayerController, enemy: Node3D) -> float:
	var to := enemy.global_position - player.global_position
	to.y = 0.0
	return _forward(player).dot(to.normalized())


func _wait_strike(player: PlayerController) -> void:
	await wait_until(func() -> bool:
		return player.melee.phase == MeleeAttackComponent.Phase.STRIKE, 120)


func _wait_idle(player: PlayerController) -> void:
	await wait_until(func() -> bool: return not player.melee.is_busy(), 200)
	await ticks(2)
