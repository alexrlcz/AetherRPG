extends "res://tests/combat_test.gd"
## Headless player movement checks: sprint, walk toggle, jump, dash attack and
## idle variants, on the real player scene (reuses the combat test's arena and
## helpers).
##   godot --headless --path . -s res://tests/movement_test.gd
## Exit code 0 = every check passed.

const DASH := preload("res://resources/combat/player_dash_attack.tres")


func _initialize() -> void:
	await process_frame
	await test_sprint()
	await test_walk_toggle()
	await test_jump()
	await test_dash_attack()
	await test_idle_variants()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_sprint() -> void:
	print("1. Sprint raises the top speed and plays the sprint cycle")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(3)
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await ticks(90)
	var speed := flat(player.velocity).length()
	check(player.is_sprinting, "is_sprinting while held and moving")
	check(absf(speed - player.sprint_speed) < 0.2, "sprint speed %.2f m/s" % speed)
	check(_anim(player) == &"Sprint", "Sprint cycle plays (%s)" % _anim(player))
	Input.action_release("sprint")
	await ticks(60)
	speed = flat(player.velocity).length()
	check(absf(speed - player.move_speed) < 0.2, "back to run speed %.2f m/s" % speed)
	check(_anim(player) == &"Jog_Fwd", "Jog cycle after releasing (%s)" % _anim(player))
	# Sprinting overrides strafing: facing follows the movement, not the cursor.
	player.aim_override = Vector3.LEFT
	Input.action_press("aim")
	Input.action_press("sprint")
	await ticks(60)
	var forward := flat(-player.global_basis.z).normalized()
	var moving := flat(player.velocity).normalized()
	check(not player.is_strafing, "not strafing while sprinting with aim held")
	check(forward.dot(moving) > 0.95, "faces the sprint direction (dot %.2f)" % forward.dot(moving))
	Input.action_release("sprint")
	await ticks(30)
	check(player.is_strafing, "strafing again after releasing sprint")
	Input.action_release("aim")
	Input.action_release("move_forward")
	await clear_arena()


func test_walk_toggle() -> void:
	print("2. The walk toggle caps the speed and plays the formal walk")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(3)
	await _press_action("walk_toggle")
	check(player.is_walking, "walk_toggle input turns walking on")
	Input.action_press("move_forward")
	await ticks(90)
	var speed := flat(player.velocity).length()
	check(absf(speed - player.walk_speed) < 0.1, "walk speed %.2f m/s" % speed)
	check(_anim(player) == &"Walk_Formal", "Walk_Formal cycle plays (%s)" % _anim(player))
	await _press_action("walk_toggle")
	check(not player.is_walking, "pressing again turns it off")
	await ticks(90)
	speed = flat(player.velocity).length()
	check(absf(speed - player.move_speed) < 0.2, "run speed again %.2f m/s" % speed)
	Input.action_release("move_forward")
	await clear_arena()


func test_jump() -> void:
	print("3. Jump: height, animations, no attacks in the air, momentum")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(10)
	var floor_y := player.global_position.y
	await _press_action("jump")
	await ticks(2)
	check(not player.is_on_floor(), "left the floor")
	check(_animator(player).current_action() == &"Jump_Start",
		"Jump_Start plays (%s)" % _animator(player).current_action())
	player.request_attack(false)
	var apex := [floor_y]
	var attacked := [false]
	var air_ticks := [0]
	await wait_until(func() -> bool:
		apex[0] = maxf(apex[0], player.global_position.y)
		attacked[0] = attacked[0] or (player.melee.is_busy() and not player.is_on_floor())
		air_ticks[0] += 1
		return player.is_on_floor() and air_ticks[0] > 5, 120)
	var height: float = apex[0] - floor_y
	check(absf(height - player.jump_height) < 0.1, "apex %.2f m (jump_height %.2f)" % [height, player.jump_height])
	check(not attacked[0], "no attack starts in the air")
	await ticks(2)
	check(_animator(player).current_action() == &"Jump_Land",
		"Jump_Land on touch-down (%s)" % _animator(player).current_action())
	await ticks(40)
	# Running jump keeps its momentum.
	Input.action_press("move_forward")
	await ticks(60)
	var start := player.global_position
	player.request_jump()
	await ticks(3)
	Input.action_release("move_forward")  # Weak air control: still carries on.
	await wait_until(func() -> bool: return player.is_on_floor(), 120)
	var distance := flat(player.global_position - start).length()
	check(distance > 3.0, "running jump carries %.2f m" % distance)
	await clear_arena()


func test_dash_attack() -> void:
	print("4. A light attack at sprint speed is the dash attack")
	await make_arena()
	var player := spawn_player(Vector3(0, 0, 8))
	await ticks(3)
	Input.action_press("move_forward")
	await ticks(40)
	player.request_attack(false)
	await ticks(2)
	check(player.melee.current != DASH, "a running light attack is not the dash (%s)"
		% player.melee.current.display_name)
	await wait_until(func() -> bool: return not player.melee.is_busy(), 120)
	await ticks(10)
	Input.action_press("sprint")
	await ticks(60)
	var dir := flat(player.velocity).normalized()
	var dummy := spawn_dummy(player.global_position + dir * 4.0, 0.4)
	var hp := dummy.current_health
	player.request_attack(false)
	await ticks(2)
	check(player.melee.current == DASH, "sprinting light attack is the dash (%s)"
		% player.melee.current.display_name)
	check(_animator(player).current_action() == &"UAL2/Sword_Dash", "Sword_Dash plays")
	Input.action_release("sprint")
	Input.action_release("move_forward")
	await wait_until(func() -> bool: return dummy.current_health < hp, 60)
	check(dummy.current_health < hp, "the lunge reaches a target 4 m ahead")
	await wait_until(func() -> bool: return not player.melee.is_busy(), 120)
	await clear_arena()


func test_idle_variants() -> void:
	print("5. Standing still plays idle variants; moving or aiming stops them")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	var animator := _animator(player)
	animator.idle_variant_delay = 0.5
	animator.idle_variant_min_duration = 0.5
	check(animator.idle_variants.size() == 10, "%d idle variants configured" % animator.idle_variants.size())
	var seen := {}
	for i in 400:
		await physics_frame
		var variant := animator.current_idle_variant()
		if variant != &"":
			seen[variant] = true
			if animator.animation_player.current_animation != variant:
				check(false, "variant %s is the playing clip" % variant)
				break
	# Each variant loops whole clips (2.5-2.9 s): two fit in this window.
	check(seen.size() >= 2, "different variants in turn (%s)" % ", ".join(seen.keys()))
	Input.action_press("move_forward")
	await ticks(20)
	check(animator.current_idle_variant() == &"", "moving ends the variant")
	Input.action_release("move_forward")
	Input.action_press("aim")
	await ticks(120)
	check(animator.current_idle_variant() == &"", "no variants while aiming")
	Input.action_release("aim")
	await clear_arena()


## Sends a real press + release of `action` through the input pipeline, so the
## binding and the player's _unhandled_input are exercised.
func _press_action(action: StringName) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
		Input.flush_buffered_events()
		await physics_frame


func _anim(player: PlayerController) -> StringName:
	return _animator(player).animation_player.current_animation


func _animator(player: PlayerController) -> CharacterAnimator:
	return player.get_node("Animator") as CharacterAnimator
