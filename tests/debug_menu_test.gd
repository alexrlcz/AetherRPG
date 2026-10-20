extends "res://tests/combat_test.gd"
## Headless checks of debug tools: god mode (reuses the combat test's arena
## and helpers, then the real Main scene for the menu checkbox).
##   godot --headless --path . -s res://tests/debug_menu_test.gd
## Exit code 0 = every check passed.


func _initialize() -> void:
	await process_frame
	await test_god_mode_blocks_hits()
	await test_god_mode_checkbox()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_god_mode_blocks_hits() -> void:
	print("1. God mode: enemy hits deal no damage and don't stagger")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	player.health.god_mode = true
	var enemy := spawn_enemy(Vector3(0, 0, -1.4), true)
	await ticks(5)
	var hp := player.health.current_health
	var log := {"damaged": 0, "staggered": 0}
	player.health.damaged.connect(func(_a: int, _s: Node) -> void: log.damaged += 1)
	player.reaction.staggered.connect(func(_e: HitEvent) -> void: log.staggered += 1)
	var hurtbox := player.get_node("Hurtbox") as HurtboxComponent
	enemy.call("_start_attack")
	await wait_until(func() -> bool: return not enemy.melee.is_busy(), 300)
	# hit_confirmed only fires on damage; the hurtbox records every contact.
	check(hurtbox.last_hit != null and hurtbox.last_hit.source == enemy, "the swing connected")
	check(player.health.current_health == hp, "no damage (%d / %d)" % [player.health.current_health, hp])
	check(log.damaged == 0 and log.staggered == 0, "no damaged / staggered signals")
	player.health.god_mode = false
	await ticks(30)
	enemy.call("_start_attack")
	await wait_until(func() -> bool: return not enemy.melee.is_busy(), 300)
	check(player.health.current_health < hp, "off again: the next swing hurts (%d)" % player.health.current_health)
	await clear_arena()


func test_god_mode_checkbox() -> void:
	print("2. The debug menu's God mode checkbox toggles the player's god mode")
	var main: Node3D = preload("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await ticks(10)
	var menu := main.get_node("DebugMenu") as DebugMenu
	var box := menu.get_node("%GodModeCheck") as CheckBox
	var health := (main.get_node("Player") as PlayerController).health
	check(not box.button_pressed and not health.god_mode, "off by default")
	box.button_pressed = true  # Emits toggled, like a click.
	check(health.god_mode, "ticking it turns god mode on")
	var hp := health.current_health
	health.take_damage(50)
	check(health.current_health == hp, "damage ignored")
	box.button_pressed = false
	check(not health.god_mode, "unticking turns it off")
	main.queue_free()
	await ticks(2)
