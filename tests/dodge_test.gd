extends "res://tests/combat_test.gd"
## Headless dodge-roll checks on the real player and enemy scenes (reuses the
## combat test's arena and helpers).
##   godot --headless --path . -s res://tests/dodge_test.gd
## Exit code 0 = every check passed.


func _initialize() -> void:
	await process_frame
	await test_roll_distance_and_direction()
	await test_roll_without_input()
	await test_cooldown_and_buffer()
	await test_invulnerability()
	await test_attack_interplay()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_roll_distance_and_direction() -> void:
	print("1. Rolls the WASD direction for the configured distance")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(3)
	var dodge := player.dodge
	var right := flat(camera_rig.camera.global_basis.x).normalized()
	var start := player.global_position
	Input.action_press("move_right")
	player.request_dodge()
	await physics_frame
	check(dodge.is_rolling(), "roll starts from a standstill")
	check(_action(player) == &"Roll", "plays the Roll animation (%s)" % _action(player))
	check(_forward(player).dot(right) > 0.99, "turns to face the roll direction at once")
	Input.action_release("move_right")  # Committed: releasing changes nothing.
	await wait_until(func() -> bool: return not dodge.is_rolling(), 120)
	var moved := flat(player.global_position - start)
	check(absf(moved.length() - dodge.distance) < 0.1,
		"covers %.2f m (distance %.2f m)" % [moved.length(), dodge.distance])
	check(moved.normalized().dot(right) > 0.99, "along the held direction")
	await wait_until(func() -> bool: return not dodge.is_dodging(), 60)
	check(flat(player.velocity).length() < 0.5, "ends at rest")
	await ticks(30)
	check(_action(player) == &"", "locomotion resumes after the roll")
	await clear_arena()


func test_roll_without_input() -> void:
	print("2. With no direction held, rolls toward the cursor")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	player.aim_override = Vector3.LEFT
	await ticks(3)
	var start := player.global_position
	player.request_dodge()
	await physics_frame
	check(player.dodge.is_rolling(), "roll starts")
	await wait_until(func() -> bool: return not player.dodge.is_rolling(), 120)
	var moved := flat(player.global_position - start)
	check(moved.normalized().dot(Vector3.LEFT) > 0.99, "rolled toward the cursor (%s)" % moved)
	await clear_arena()


func test_cooldown_and_buffer() -> void:
	print("3. Cooldown between rolls; an early press is buffered")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(3)
	var dodge := player.dodge
	player.request_dodge()
	await physics_frame
	var started_at := Engine.get_physics_frames()
	await wait_until(func() -> bool: return not dodge.is_dodging(), 120)
	check(not dodge.is_ready(), "not ready straight after a roll (cooldown)")
	player.request_dodge()
	await wait_until(func() -> bool: return dodge.is_dodging(), 60)
	var gap := float(Engine.get_physics_frames() - started_at) / Engine.physics_ticks_per_second
	check(dodge.is_rolling(), "buffered press rolls once the cooldown is over")
	check(gap >= dodge.cooldown - 0.02, "second roll waited for the cooldown (%.2f s)" % gap)
	await clear_arena()


func test_invulnerability() -> void:
	print("4. I-frames ignore hits; the rest of the roll does not")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	player.health.max_health = 1000
	player.health.current_health = 1000
	player.dodge.distance = 0.0  # Roll in place: only the i-frames can avoid the hit.
	var enemy := spawn_enemy(Vector3(0, 0, -1.4), false)
	await ticks(3)
	var evaded := [0]
	player.get_node("Hurtbox").evaded.connect(func(_e: HitEvent) -> void: evaded[0] += 1)
	enemy.call("_start_attack")
	var windup: float = enemy.melee.current.windup
	await wait_until(func() -> bool:
		return enemy.melee.phase == MeleeAttackComponent.Phase.WINDUP \
			and enemy.melee.phase_time >= windup - 0.08, 200)
	player.request_dodge()
	var hp := player.health.current_health
	await wait_until(func() -> bool: return not enemy.melee.is_busy(), 200)
	check(player.health.current_health == hp, "enemy swing during the i-frames does no damage")
	check(evaded[0] > 0, "the hurtbox reported the evaded hit")
	check(not player.reaction.is_reacting(), "no stagger from an evaded hit")
	await wait_until(func() -> bool: return player.dodge.is_ready(), 120)

	player.request_dodge()
	await wait_until(func() -> bool:
		return player.dodge.is_dodging() and not player.get_node("Hurtbox").invulnerable, 60)
	check(player.dodge.is_dodging(), "late in the roll the character is vulnerable again")
	player.get_node("Hurtbox").receive_hit(10, null)
	check(player.health.current_health == hp - 10, "a hit after the i-frames lands")
	await wait_until(func() -> bool: return not player.dodge.is_dodging(), 60)
	check(not player.get_node("Hurtbox").invulnerable, "invulnerability cleared after the roll")
	await clear_arena()


func test_attack_interplay() -> void:
	print("5. Rolls cut attack recovery, not the swing; attacks buffer through rolls")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(3)
	var dodge := player.dodge
	player.request_attack(false)
	await wait_until(func() -> bool:
		return player.melee.phase == MeleeAttackComponent.Phase.WINDUP, 30)
	player.request_dodge()
	await physics_frame
	check(not dodge.is_dodging(), "no roll during the wind-up")
	await wait_until(func() -> bool:
		return player.melee.phase == MeleeAttackComponent.Phase.STRIKE, 60)
	player.request_dodge()
	await physics_frame
	check(not dodge.is_dodging() and player.melee.phase == MeleeAttackComponent.Phase.STRIKE,
		"no roll during the strike")
	await wait_until(func() -> bool: return dodge.is_dodging(), 30)
	check(dodge.is_rolling(), "buffered roll cuts into the recovery")
	check(not player.melee.is_busy(), "the attack ended")

	await wait_until(func() -> bool: return dodge.is_ready(), 120)
	player.request_dodge()
	await ticks(3)
	player.request_attack(false)
	var attacked_mid_roll := false
	while dodge.is_rolling():
		attacked_mid_roll = attacked_mid_roll or player.melee.is_busy()
		await physics_frame
	check(not attacked_mid_roll, "no attack during the roll")
	await ticks(2)
	check(player.melee.is_busy(), "attack pressed mid-roll starts as the roll ends")
	check(not dodge.is_dodging(), "the attack cut the get-up recovery short")
	await clear_arena()


func _action(player: PlayerController) -> StringName:
	return (player.get_node("Animator") as CharacterAnimator).current_action()


func _forward(player: PlayerController) -> Vector3:
	return flat(-player.global_basis.z).normalized()
