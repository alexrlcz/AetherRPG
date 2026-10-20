extends "res://tests/combat_test.gd"
## Headless healing flask checks on the real player (reuses the combat test's
## arena and helpers), then the HUD in the real Main scene.
##   godot --headless --path . -s res://tests/flask_test.gd
## Exit code 0 = every check passed.


func _initialize() -> void:
	await process_frame
	await test_drink()
	await test_refused()
	await test_interrupted()
	await test_refill_and_input()
	await test_hud()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_drink() -> void:
	print("1. A drink restores 35% of max health partway through, rooted, one charge")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	var flask := player.flask
	await ticks(3)
	check(flask != null and flask.charges == 3 and flask.max_charges == 3, "3 charges")
	player.health.take_damage(50)
	Input.action_press("move_forward")
	player.request_flask()
	await ticks(2)
	check(flask.is_drinking(), "R starts a drink")
	check(_animator(player).current_action() == &"UAL2/Consume", "the drink plays UAL2/Consume")
	await ticks(20)
	check(flat(player.velocity).length() < 0.05, "rooted while drinking, even holding forward (%.2f m/s)"
		% flat(player.velocity).length())
	check(player.health.current_health == 50, "no health yet before the heal point")
	player.request_attack(false)
	player.request_dodge()
	await wait_until(func() -> bool: return flask.charges == 2, 60)
	check(player.health.current_health == 85, "+35 health (%d / 100)" % player.health.current_health)
	check(flask.charges == 2, "one charge spent")
	check(not player.melee.is_busy() and not player.dodge.is_dodging(), "no attack or roll during the drink")
	await wait_until(func() -> bool: return not flask.is_drinking(), 60)
	await ticks(30)
	check(flat(player.velocity).length() > 1.0, "moves again after the drink")
	Input.action_release("move_forward")
	await clear_arena()


func test_refused() -> void:
	print("2. No drink at full health or without charges")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(3)
	player.request_flask()
	await ticks(5)
	check(not player.flask.is_drinking(), "full health: no drink")
	player.health.take_damage(30)
	player.flask.charges = 0
	player.request_flask()
	await ticks(5)
	check(not player.flask.is_drinking() and player.health.current_health == 70, "no charges: no drink")
	await clear_arena()


func test_interrupted() -> void:
	print("3. A staggering hit before the heal cuts the drink short; the charge is kept")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(3)
	player.health.take_damage(40)
	var log := {"interrupted": 0}
	player.flask.interrupted.connect(func() -> void: log.interrupted += 1)
	player.request_flask()
	await ticks(10)
	check(player.flask.is_drinking(), "drinking")
	var event := HitEvent.new()
	event.amount = 10
	event.profile = CLEAVE
	event.direction = Vector3.BACK
	event.point = player.global_position + Vector3.UP
	(player.get_node("Hurtbox") as HurtboxComponent).receive_event(event)
	await ticks(1)
	check(player.reaction.is_reacting(), "the hit staggers")
	check(not player.flask.is_drinking() and log.interrupted == 1, "the drink is cut short")
	await ticks(60)
	check(player.health.current_health == 50, "no heal (%d)" % player.health.current_health)
	check(player.flask.charges == 3, "the charge is kept")
	await clear_arena()


func test_refill_and_input() -> void:
	print("4. Charges refill on a new level; R drinks (and still restarts when dead)")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(3)
	player.flask.charges = 1
	GameRun.current().jump_to(GameRun.current().level + 1)
	check(player.flask.charges == 3, "a new level refills the flasks")
	for action in [&"use_flask", &"restart"]:
		var keys := InputMap.action_get_events(action).filter(func(e: InputEvent) -> bool:
			return e is InputEventKey and (e as InputEventKey).physical_keycode == KEY_R)
		check(not keys.is_empty(), "%s is bound to R" % action)
	await clear_arena()


func test_hud() -> void:
	print("5. The HUD shows the flasks")
	var main: Node3D = preload("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await ticks(10)
	var label := main.get_node("HUD").get_node("%FlaskLabel") as Label
	var flask := (main.get_node("Player") as PlayerController).flask
	check(label.visible and label.text.begins_with("Flasks 3 / 3"), "HUD: %s" % label.text)
	flask.charges = 1
	flask.charges_changed.emit(1, 3)
	check(label.text.begins_with("Flasks 1 / 3"), "follows the charges (%s)" % label.text)
	main.queue_free()
	await ticks(2)


func _animator(player: PlayerController) -> CharacterAnimator:
	return player.get_node("Animator") as CharacterAnimator
