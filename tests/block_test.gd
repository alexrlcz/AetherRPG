extends "res://tests/combat_test.gd"
## Headless shield checks on the real player: the shield item, raising it
## with "aim" (right mouse), moving with it up, which hits it blocks and what
## they cost, the guard break, actions lowering it, a real enemy's swing
## blocked, and the Outfits & gear panel's Off hand picker (reuses the combat
## test's arena and helpers).
##   godot --headless --path . -s res://tests/block_test.gd
## Exit code 0 = every check passed.

const SHIELD := preload("res://resources/items/gear/shield_wooden.tres")


func _initialize() -> void:
	await process_frame
	PlayerProfile.current().save_path = ""
	test_item()
	await test_no_shield()
	await test_guard_and_move()
	await test_blocking()
	await test_guard_break()
	await test_actions_lower_guard()
	await test_enemy_swing()
	await test_menu()
	Input.action_release("aim")
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_item() -> void:
	print("1. The wooden shield item")
	check(SHIELD is ShieldDefinition and SHIELD.slot == GearDefinition.Slot.OFF_HAND,
		"%s is a shield for the off hand" % SHIELD.display_name)
	check(SHIELD.kind == ItemDefinition.Kind.GEAR and not SHIELD.auto_collect, "it is gear, picked up with interact")
	check(SHIELD.anchor_bone == &"hand_l" and SHIELD.fit_in_bone_space, "held in the left hand")


func test_no_shield() -> void:
	print("2. Without a shield, right mouse only aims")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(2)
	Input.action_press("aim")
	await ticks(5)
	var block := _block(player)
	check(player.is_aiming and not block.has_shield() and not player.is_guarding, "aiming, no guard")
	_hit(player, Vector3(0, 0, -2), 10)
	check(player.health.current_health == 100 - _after_armor(player, 10), "a hit from the front lands (%d hp)"
		% player.health.current_health)
	Input.action_release("aim")
	await clear_arena()


func test_guard_and_move() -> void:
	print("3. Holding right mouse raises the shield; the player can still move")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(2)
	_wear(player, SHIELD)
	var block := _block(player)
	check(block.shield == SHIELD, "the block component sees the worn shield")
	var names := _names(player)
	check(names.has("Gear_ShieldWooden"), "the shield is on the rig")
	check(not player.is_guarding, "not raised until right mouse is held")
	player.sprint_toggled = true
	Input.action_press("aim")
	await ticks(20)
	check(player.is_guarding and block.get_pose().influence >= 1.0, "right mouse held: guard up, arm raised")
	check(not player.sprint_toggled, "raising the shield ends the sprint")
	var animator := player.get_node("Animator") as CharacterAnimator
	var animation_player := player.get_node("Visual/Model/AnimationPlayer") as AnimationPlayer
	check(animation_player.current_animation == animator.guard_idle_animation,
		"standing still plays the guard stance (%s)" % animation_player.current_animation)
	var start := player.global_position
	Input.action_press("move_forward")
	await ticks(40)
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	check(player.global_position.distance_to(start) > 1.5 and speed > 3.0,
		"it runs with the shield up (%.1f m/s, %.1f m)" % [speed, player.global_position.distance_to(start)])
	check(player.is_guarding and block.get_pose().influence >= 1.0, "the guard stays up while running")
	Input.action_release("move_forward")
	Input.action_release("aim")
	await ticks(15)
	check(not player.is_guarding and block.get_pose().influence <= 0.0, "released: the shield lowers")
	await clear_arena()


func test_blocking() -> void:
	print("4. Blocked hits cost stamina instead of health; only from the front")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(2)
	_wear(player, SHIELD)
	Input.action_press("aim")
	await ticks(10)
	var blocked := [0]
	(player.get_node("Hurtbox") as HurtboxComponent).blocked.connect(func(_e: HitEvent) -> void: blocked[0] += 1)
	var stamina_before := player.stamina.current_stamina
	_hit(player, Vector3(0.5, 0, -2), 20)
	check(player.health.current_health == 100 and blocked[0] == 1, "a hit from the front is blocked (%d hp)"
		% player.health.current_health)
	var paid := stamina_before - player.stamina.current_stamina
	check(is_equal_approx(paid, 20 * SHIELD.stamina_per_damage), "it costs %.0f stamina" % paid)
	check(not player.reaction.is_reacting(), "no stagger")
	_hit(player, Vector3(1.5, 0, -1.5), 20)
	check(player.health.current_health == 100, "a hit from 45 deg to the side, inside the arc, is blocked")
	_hit(player, Vector3(2.0, 0, 0.0), 5)
	var side := _after_armor(player, 5)
	check(player.health.current_health == 100 - side, "a hit from straight beside, outside the arc, lands")
	_hit(player, Vector3(0, 0, 2), 15)
	check(player.health.current_health == 100 - side - _after_armor(player, 15),
		"a hit from behind lands, less the shield's armor (%d hp)" % player.health.current_health)
	Input.action_release("aim")
	await clear_arena()


func test_guard_break() -> void:
	print("5. A hit costing more than the stamina left breaks the guard")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(2)
	_wear(player, SHIELD)
	Input.action_press("aim")
	await ticks(10)
	var broken := [false]
	_block(player).guard_broken.connect(func(_e: HitEvent) -> void: broken[0] = true)
	player.stamina.drain(player.stamina.current_stamina - 10.0)
	_hit(player, Vector3(0, 0, -2), 20)
	check(broken[0] and player.health.current_health == 100 - _after_armor(player, 20), "guard broken, the hit lands (%d hp)"
		% player.health.current_health)
	check(player.stamina.is_exhausted and not player.is_guarding, "exhausted: the shield is down")
	player.stamina.reset()
	await ticks(30)
	check(player.is_guarding, "it comes back up once stamina recovers (still holding)")
	Input.action_release("aim")
	await clear_arena()


func test_actions_lower_guard() -> void:
	print("6. Attacking or rolling lowers the shield until done")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(2)
	_wear(player, SHIELD)
	Input.action_press("aim")
	await ticks(10)
	player.request_attack(false)
	await ticks(3)
	check(player.melee.is_busy() and not player.is_guarding, "attacking: guard down")
	_hit(player, Vector3(0, 0, -2), 1)
	check(player.health.current_health == 99, "a hit mid-swing lands")
	await wait_until(func() -> bool: return not player.melee.is_busy(), 120)
	await ticks(2)
	check(player.is_guarding, "after the attack the guard is back up")
	player.request_dodge()
	await ticks(3)
	check(player.dodge.is_dodging() and not player.is_guarding, "rolling: guard down")
	Input.action_release("aim")
	await clear_arena()


func test_enemy_swing() -> void:
	print("7. A real enemy's swing is blocked")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(2)
	_wear(player, SHIELD)
	player.stamina.infinite = true
	Input.action_press("aim")
	var enemy := spawn_enemy(Vector3(0, 0, -2.2), false)
	var block := _block(player)
	var got_blocked := await wait_until(func() -> bool: return block.hits_blocked > 0, 600)
	check(got_blocked and player.health.current_health == player.health.max_health,
		"the knight's swing hit the shield (%d blocked, %d hp)" % [block.hits_blocked, player.health.current_health])
	check(is_instance_valid(enemy), "the enemy is unharmed by the block")
	Input.action_release("aim")
	await clear_arena()


func test_menu() -> void:
	print("8. The Equipment panel's Off hand picker")
	var main: Node3D = preload("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await ticks(10)
	var menu := main.get_node("DebugMenu") as DebugMenu
	var panel := menu.get_node("EquipmentMenu") as EquipmentMenu
	var block := main.get_node("Player/Block") as BlockComponent
	(menu.get_node("%EquipmentButton") as Button).pressed.emit()
	var off_hand := panel.get_option(&"off_hand")
	check(off_hand.item_count == 2 and off_hand.get_item_text(1) == SHIELD.display_name,
		"it offers None and %s" % off_hand.get_item_text(1))
	panel.choose(&"off_hand", SHIELD)
	check(block.shield == SHIELD, "choosing it equips the shield")
	panel.choose(&"off_hand", null)
	check(block.shield == null, "None takes it off")
	main.queue_free()
	await ticks(2)


## Damage left of a hit of `amount` after the player's armor (its gear).
func _after_armor(player: PlayerController, amount: int) -> int:
	var armor := player.character_stats.get_value(CharacterStats.Stat.ARMOR)
	return maxi(roundi(amount * (1.0 - CharacterStats.armor_reduction(armor))), 1)


## A plain hit on the player from an attacker standing at `from`.
func _hit(player: PlayerController, from: Vector3, amount: int) -> void:
	var attacker := Node3D.new()
	world.add_child(attacker)
	attacker.global_position = from
	var event := HitEvent.new()
	event.source = attacker
	event.amount = amount
	event.point = player.global_position + Vector3.UP
	var away := player.global_position - from
	away.y = 0.0
	event.direction = away.normalized()
	(player.get_node("Hurtbox") as HurtboxComponent).receive_event(event)
	attacker.queue_free()


func _wear(player: PlayerController, item: GearDefinition) -> void:
	player.equipment.equip(item)


func _block(player: PlayerController) -> BlockComponent:
	return player.get_node("Block") as BlockComponent


func _names(player: PlayerController) -> Array:
	var component := player.get_node("Appearance") as AppearanceComponent
	return component.get_parts().filter(func(m: MeshInstance3D) -> bool: return is_instance_valid(m)) \
		.map(func(m: MeshInstance3D) -> String: return String(m.name))
