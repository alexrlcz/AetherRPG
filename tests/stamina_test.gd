extends "res://tests/combat_test.gd"
## Headless stamina checks: the component on its own, then the player's
## attacks, dodge and sprint, and an enemy that runs out of breath (reuses
## the combat test's arena and helpers).
##   godot --headless --path . -s res://tests/stamina_test.gd
## Exit code 0 = every check passed.


func _initialize() -> void:
	await process_frame
	await test_component()
	await test_player_actions()
	await test_sprint_drain()
	await test_enemy_exhaustion()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_component() -> void:
	print("1. StaminaComponent: spend, regen delay, exhaustion and recovery")
	var stamina := StaminaComponent.new()
	stamina.max_stamina = 100.0
	stamina.regen_rate = 50.0
	stamina.regen_delay = 0.5
	stamina.recover_threshold = 0.25
	root.add_child(stamina)
	var log := {"exhausted": 0, "recovered": 0}
	stamina.exhausted.connect(func() -> void: log.exhausted += 1)
	stamina.recovered.connect(func() -> void: log.recovered += 1)
	check(stamina.spend(30.0), "spend allowed at full stamina")
	check(is_equal_approx(stamina.current_stamina, 70.0), "30 spent (%.1f left)" % stamina.current_stamina)
	await ticks(20)  # 0.33 s < regen_delay
	check(is_equal_approx(stamina.current_stamina, 70.0), "no regen during the delay (%.1f)" % stamina.current_stamina)
	await ticks(30)
	check(stamina.current_stamina > 70.0, "regenerates after the delay (%.1f)" % stamina.current_stamina)
	stamina.current_stamina = 10.0
	check(stamina.spend(40.0), "a cost above what is left is still allowed")
	check(stamina.current_stamina == 0.0 and stamina.is_exhausted, "bottoms out at 0 and exhausts")
	check(log.exhausted == 1, "exhausted emitted once")
	check(not stamina.can_act() and not stamina.spend(1.0), "no actions while exhausted")
	await wait_until(func() -> bool: return stamina.current_stamina >= 20.0, 120)
	check(stamina.is_exhausted, "still exhausted below the recover threshold (%.1f)" % stamina.current_stamina)
	await wait_until(func() -> bool: return not stamina.is_exhausted, 120)
	check(not stamina.is_exhausted and log.recovered == 1, "recovers at 25%% (%.1f)" % stamina.current_stamina)
	check(stamina.current_stamina >= 25.0 and stamina.current_stamina < 27.0, "recovered right at the threshold")
	stamina.infinite = true
	stamina.drain(500.0)
	check(stamina.spend(500.0) and stamina.current_stamina >= 25.0, "infinite: nothing is spent")
	stamina.queue_free()
	await ticks(1)


func test_player_actions() -> void:
	print("2. Player attacks and dodges cost stamina and are refused when exhausted")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	var stamina := player.stamina
	await ticks(3)
	check(stamina != null and stamina.ratio() == 1.0, "player starts with full stamina")
	player.request_attack(false)
	await wait_until(func() -> bool: return player.melee.is_busy(), 30)
	var cost := player.melee.current.stamina_cost
	check(cost > 0.0, "the light attack has a cost (%.0f)" % cost)
	check(is_equal_approx(stamina.current_stamina, stamina.max_stamina - cost),
		"the attack paid its cost (%.1f left)" % stamina.current_stamina)
	await wait_until(func() -> bool: return not player.melee.is_busy(), 120)
	await ticks(5)

	var before := stamina.current_stamina
	player.request_dodge()
	await wait_until(func() -> bool: return player.dodge.is_dodging(), 30)
	check(player.dodge.is_dodging(), "dodge starts")
	# A tick or two of regeneration may land between `before` and the roll.
	check(before - stamina.current_stamina >= player.dodge.stamina_cost - 2.0,
		"the dodge paid %.0f" % (before - stamina.current_stamina))
	await wait_until(func() -> bool: return not player.dodge.is_dodging(), 120)
	await ticks(60)  # past the dodge cooldown

	stamina.drain(stamina.max_stamina)
	check(stamina.is_exhausted, "drained to exhaustion")
	player.request_attack(false)
	player.request_dodge()
	await ticks(10)
	check(not player.melee.is_busy(), "no attack while exhausted")
	check(not player.dodge.is_dodging(), "no dodge while exhausted")
	await wait_until(func() -> bool: return stamina.can_act(), 300)
	check(stamina.can_act(), "recovers (%.1f)" % stamina.current_stamina)
	player.request_attack(false)
	await wait_until(func() -> bool: return player.melee.is_busy(), 30)
	check(player.melee.is_busy(), "attacks again after recovering")
	await clear_arena()


func test_sprint_drain() -> void:
	print("3. Sprinting drains stamina and stops at exhaustion")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	var stamina := player.stamina
	await ticks(3)
	Input.action_press("move_forward")
	player.sprint_toggled = true
	await ticks(60)
	check(player.is_sprinting, "sprinting")
	var expected := player.sprint_stamina_per_second * 59.0 / 60.0
	var spent := stamina.max_stamina - stamina.current_stamina
	check(absf(spent - expected) < player.sprint_stamina_per_second * 0.1,
		"drains %.0f/s (spent %.1f in ~1 s)" % [player.sprint_stamina_per_second, spent])
	stamina.current_stamina = 1.0
	await ticks(10)
	check(stamina.is_exhausted, "runs dry")
	check(not player.is_sprinting and not player.sprint_toggled, "sprint stops and the toggle clears")
	var speed := flat(player.velocity).length()
	check(speed < player.move_speed + 0.3, "back to run speed (%.2f m/s)" % speed)
	await wait_until(func() -> bool: return stamina.can_act(), 300)
	player.sprint_toggled = true
	await ticks(30)
	check(player.is_sprinting, "can sprint again after recovering")
	Input.action_release("move_forward")
	player.sprint_toggled = false
	await clear_arena()


func test_enemy_exhaustion() -> void:
	print("4. Enemies pay for attacks and hold off while exhausted")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	player.health.max_health = 100000  # Survive the whole test.
	var enemy := spawn_enemy(Vector3(0, 0, -1.4), false)
	var stamina := enemy.stamina
	check(stamina != null and is_equal_approx(stamina.max_stamina, enemy.stats.max_stamina),
		"enemy stamina from EnemyStats (%.0f)" % stamina.max_stamina)
	# Before its first tick: it spawns in range and would swing at once.
	stamina.drain(stamina.max_stamina)
	await ticks(60)
	check(not enemy.melee.is_busy() and enemy.state != EnemyController.State.ATTACK,
		"an exhausted enemy in range does not attack")
	check(flat(enemy.velocity).length() < 0.5, "and holds its ground (%.2f m/s)"
		% flat(enemy.velocity).length())
	await wait_until(func() -> bool: return enemy.melee.is_busy(), 600)
	check(enemy.melee.is_busy(), "attacks once recovered")
	check(stamina.current_stamina < stamina.max_stamina * stamina.recover_threshold,
		"the swing spent its cost (%.1f left)" % stamina.current_stamina)
	await clear_arena()
