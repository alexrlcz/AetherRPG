extends "res://tests/combat_test.gd"
## Headless weapon checks: equipping and swapping (model, hitbox, animation
## set, overrides restored), the greatsword moveset with root motion, and
## greatsword knights. Reuses the combat test's arena and helpers.
##   godot --headless --path . -s res://tests/weapon_test.gd
## Exit code 0 = every check passed.

const SWORD := preload("res://resources/weapons/sword.tres")
const GS_COMBO := [
	preload("res://resources/combat/gs_cleave_down.tres"),
	preload("res://resources/combat/gs_rising_sweep.tres"),
	preload("res://resources/combat/gs_flurry_a.tres"),
	preload("res://resources/combat/gs_flurry_b.tres"),
	preload("res://resources/combat/gs_flurry_c.tres"),
]


func _initialize() -> void:
	await process_frame
	await test_swap()
	await test_greatsword_geometry()
	await test_greatsword_combo()
	await test_blade_stays_above_floor()
	await test_root_motion()
	await test_sprint_attacks()
	await test_greatsword_locomotion()
	await test_enemy_weapons()
	await test_greatsword_knight()
	await test_debug_menu()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_swap() -> void:
	print("1. Swapping weapons: model, hitbox, attacks, animation set, overrides")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(3)
	var weapon := _weapon(player)
	var animator := _animator(player)
	check(weapon.current == SWORD, "player starts with the sword")
	check(_model_name(weapon) == "Sword", "sword model in the hand (%s)" % _model_name(weapon))
	check(player.light_combo == SWORD.light_combo, "sword combo")
	weapon.equip(GREATSWORD)
	await ticks(20)
	check(_model_name(weapon) == "Claymore", "Claymore model in the hand (%s)" % _model_name(weapon))
	check(_hand(player).get_children().filter(func(n: Node) -> bool:
		return n.name.begins_with("WeaponModel") and not n.is_queued_for_deletion()).size() == 1,
		"only one weapon model")
	var box := _hitbox_shape(player)
	check(box.shape.size == GREATSWORD.hitbox_size, "hitbox sized to the blade %s" % box.shape.size)
	check(player.light_combo == GREATSWORD.light_combo and player.heavy_attack == GREATSWORD.heavy_attack,
		"greatsword attacks taken")
	check(animator.idle_animation == &"GS/Idle" and animator.animation_player.current_animation == "GS/Idle",
		"greatsword idle plays (%s)" % animator.animation_player.current_animation)
	check(player.move_speed == 5.0, "greatsword top speed %.1f" % player.move_speed)
	check(player.reaction.light_animation == &"GS/Impact_2", "greatsword hit reaction")
	weapon.equip(SWORD)
	await ticks(20)
	check(_model_name(weapon) == "Sword", "back to the sword model")
	check(animator.idle_animation == &"Sword_Idle" and animator.run_animation == &"Jog_Fwd"
		and animator.sprint_animation == &"Sprint", "animation set restored")
	check(animator.idle_variants.size() == 10, "player idle variants restored (%d)" % animator.idle_variants.size())
	check(player.move_speed == 6.0 and player.sprint_speed == 8.0, "speeds restored")
	check(player.reaction.light_animation == &"Hit_Chest", "hit reaction restored")
	check(_hitbox_shape(player).shape.size == SWORD.hitbox_size, "sword hitbox restored")
	await clear_arena()


func test_greatsword_geometry() -> void:
	print("2. The greatsword hitbox lies along the Claymore's blade")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(3)
	_weapon(player).equip(GREATSWORD)
	await ticks(10)
	var mesh := _weapon(player).get_model().find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var aabb := mesh.global_transform * mesh.get_aabb()
	var box := _hitbox_shape(player)
	var centre := box.global_position
	check(aabb.grow(0.05).has_point(centre), "hitbox centre inside the sword's bounds")
	# The blade runs along the model root's Y; the box's long side is its Y too.
	var blade_axis := _weapon(player).get_model().global_basis.y.normalized()
	var box_axis := box.global_basis.y.normalized()
	check(absf(blade_axis.dot(box_axis)) > 0.99, "hitbox long axis along the blade (dot %.3f)" % blade_axis.dot(box_axis))
	var length := aabb.get_longest_axis_size()
	check(length > 1.3 and length < 1.8, "sword %.2f m long" % length)
	await clear_arena()


func test_greatsword_combo() -> void:
	print("3. Every greatsword combo step lands on an enemy in front")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(3)
	_weapon(player).equip(GREATSWORD)
	var enemy := spawn_enemy(Vector3(0, 0, -1.6), true)
	enemy.health.max_health = 5000
	enemy.health.reset()
	enemy.reaction.knockback_scale = 0.0  # Stays in reach; its body stops the root motion.
	await ticks(5)
	var landed: Array = []
	enemy.hurtbox.hit_received.connect(func(event: HitEvent) -> void: landed.append(event.profile))
	for profile: AttackProfile in GS_COMBO:
		player.request_attack(false)
		await wait_until(func() -> bool:
			return player.melee.current == profile \
				and player.melee.phase == MeleeAttackComponent.Phase.RECOVERY, 300)
	await wait_until(func() -> bool: return not player.melee.is_busy(), 300)
	check(landed == GS_COMBO, "each of the five steps hit once (%s)"
		% [landed.map(func(p: AttackProfile) -> String: return p.display_name)])
	check(enemy.reaction.is_knocked_down() or enemy.reaction.knockdown_duration() > 0.0,
		"Flurry III knocks down")
	await clear_arena()


func test_blade_stays_above_floor() -> void:
	print("3b. No greatsword attack drives the blade into the floor")
	var attacks: Array = GS_COMBO.duplicate()
	attacks.append_array([GREATSWORD.heavy_attack, GREATSWORD.dash_attack, GREATSWORD.dash_heavy_attack])
	for profile: AttackProfile in attacks:
		await make_arena()
		var player := spawn_player(Vector3.ZERO)
		await ticks(3)
		_weapon(player).equip(GREATSWORD)
		await ticks(3)
		var hand := _hand(player)
		var lowest := [INF]
		player.melee.start(profile)
		await wait_until(func() -> bool:
			lowest[0] = minf(lowest[0], (hand.global_transform * GREATSWORD.trail_tip).y)
			return not player.melee.is_busy(), 400)
		check(lowest[0] > 0.1, "%s: tip lowest %.2f m" % [profile.display_name, lowest[0]])
		await clear_arena()


func test_root_motion() -> void:
	print("4. Root-motion attacks move the body by the clip's travel")
	for profile: AttackProfile in [GREATSWORD.heavy_attack, GS_COMBO[2]]:
		await make_arena()
		var player := spawn_player(Vector3.ZERO)
		await ticks(3)
		_weapon(player).equip(GREATSWORD)
		await ticks(3)
		var anim := _animator(player).animation_player.get_animation(profile.animation)
		var curve: PackedFloat32Array = anim.get_meta(&"root_motion")
		var start := player.global_position
		var forward := flat(-player.global_basis.z).normalized()
		player.melee.start(profile)
		await wait_until(func() -> bool: return not player.melee.is_busy(), 400)
		var moved := flat(player.global_position - start).dot(forward)
		# The clip's travel up to where the attack's animation ends.
		var end := profile.anim_recovery_end if profile.anim_recovery_end > 0.0 else anim.length
		var expected: float = curve[mini(int(round(end * 30.0)), curve.size() - 1)]
		check(absf(moved - expected) < 0.15, "%s moved %.2f m (clip %.2f m)" % [profile.display_name, moved, expected])
		await clear_arena()


func test_sprint_attacks() -> void:
	print("5. Sprinting: light = Slide Strike, heavy = Leaping Slam; both reach")
	for heavy in [false, true]:
		await make_arena()
		var player := spawn_player(Vector3(0, 0, 10))
		await ticks(3)
		_weapon(player).equip(GREATSWORD)
		Input.action_press("move_forward")
		Input.action_press("sprint")
		await ticks(60)
		var dir := flat(player.velocity).normalized()
		var target := spawn_dummy(player.global_position + dir * 4.5, 0.4)
		var hp := target.current_health
		player.request_attack(heavy)
		await ticks(2)
		var expected: AttackProfile = GREATSWORD.dash_heavy_attack if heavy else GREATSWORD.dash_attack
		check(player.melee.current == expected, "%s started (%s)" % [expected.display_name,
			player.melee.current.display_name if player.melee.current else "none"])
		Input.action_release("sprint")
		Input.action_release("move_forward")
		await wait_until(func() -> bool: return target.current_health < hp, 200)
		check(target.current_health < hp, "%s reaches a target 4.5 m ahead" % expected.display_name)
		await wait_until(func() -> bool: return not player.melee.is_busy(), 200)
		await clear_arena()


func test_greatsword_locomotion() -> void:
	print("6. Greatsword locomotion clips")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(3)
	_weapon(player).equip(GREATSWORD)
	var animator := _animator(player)
	Input.action_press("move_forward")
	await ticks(60)
	check(animator.animation_player.current_animation == "GS/Run", "runs with GS/Run (%s)" % animator.animation_player.current_animation)
	Input.action_press("sprint")
	await ticks(40)
	check(animator.animation_player.current_animation == "GS/Run", "sprints with GS/Run too (%s)" % animator.animation_player.current_animation)
	Input.action_release("sprint")
	Input.action_release("move_forward")
	# Aim up the screen, move screen-left: 90 degrees off the facing.
	player.aim_override = flat(-camera_rig.camera.global_basis.z).normalized()
	Input.action_press("aim")
	Input.action_press("move_left")
	await ticks(40)
	var strafe := animator.animation_player.current_animation
	check(strafe in ["GS/Strafe_L", "GS/Strafe_R"], "strafes with a GS clip (%s)" % strafe)
	Input.action_release("move_left")
	Input.action_release("aim")
	await ticks(30)
	player.request_jump()
	await ticks(3)
	check(animator.current_action() == &"GS/Jump", "standing jump plays GS/Jump (%s)" % animator.current_action())
	await wait_until(func() -> bool: return player.is_on_floor(), 120)
	await ticks(2)
	check(animator.current_action() == &"GS/Jump" and animator.get_action_position() >= 0.6,
		"lands with the clip's own landing (%.2f s in)" % animator.get_action_position())
	await ticks(40)
	Input.action_press("move_forward")
	await ticks(40)
	player.request_jump()
	await ticks(3)
	check(animator.current_action() == &"GS/Jump_Run", "running jump plays GS/Jump_Run (%s)" % animator.current_action())
	Input.action_release("move_forward")
	await wait_until(func() -> bool: return player.is_on_floor(), 120)
	await ticks(30)
	animator.idle_variant_delay = 0.3
	await ticks(90)
	var variant := animator.current_idle_variant()
	check(String(variant).begins_with("GS/Idle_"), "greatsword idle variant (%s)" % variant)
	await clear_arena()


func test_enemy_weapons() -> void:
	print("7. Knights pick the club or the greatsword at random")
	await make_arena()
	var counts := {}
	for i in 16:
		var enemy: EnemyController = ENEMY.instantiate()
		enemy.position = Vector3(i * 1.5 - 12.0, 0, -8)
		world.add_child(enemy)
		var name := (enemy.get_node("Weapon") as WeaponComponent).current.display_name
		counts[name] = counts.get(name, 0) + 1
		var animator := _animator(enemy)
		if name == "Greatsword":
			check(enemy.attack_profile == GREATSWORD.enemy_attack, "greatsword knight swing")
			check(animator.idle_variants.is_empty(), "knights get no idle variants")
	check(counts.size() == 2, "both weapons used %s" % counts)
	await clear_arena()


func test_greatsword_knight() -> void:
	print("8. Greatsword knights: reach and the leap knockdown")
	await make_arena()
	var reach: float = GREATSWORD.enemy_attack_range
	check(await _gs_swing_hits(reach), "slash hits at its attack range (%.1f m)" % reach)
	check(not await _gs_swing_hits(3.2), "slash misses at 3.2 m")
	await clear_arena()
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	player.health.max_health = 1000
	var enemy := spawn_enemy(Vector3(0, 0, -4.5), false, GREATSWORD)
	var hp := player.health.current_health
	var dashed := await wait_until(func() -> bool: return enemy.melee.current == GREATSWORD.enemy_dash_attack, 60)
	check(dashed, "leap attack chosen at 4.5 m")
	await wait_until(func() -> bool: return player.health.current_health < hp, 200)
	await physics_frame
	check(player.health.current_health < hp, "the leap reached the player")
	check(player.reaction.is_knocked_down(), "and knocked them down")
	await clear_arena()


func test_debug_menu() -> void:
	print("9. The debug menu's weapon option swaps the player's weapon")
	var main: Node3D = preload("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await ticks(10)
	var menu := main.get_node("DebugMenu") as DebugMenu
	var option := menu.get_node("%WeaponOption") as OptionButton
	var weapon := _weapon(main.get_node("Player"))
	check(option.item_count == 2 and option.get_item_text(option.selected) == "Sword",
		"offers %d weapons, Sword selected" % option.item_count)
	option.select(1)
	option.item_selected.emit(1)
	await ticks(5)
	check(weapon.current == GREATSWORD, "picking Greatsword equips it")
	menu.equip_player_weapon(0)
	await ticks(5)
	check(weapon.current == SWORD, "and back to the sword")
	main.queue_free()
	await ticks(2)


func _gs_swing_hits(distance: float) -> bool:
	await clear_arena()
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	player.health.max_health = 1000
	var enemy := spawn_enemy(Vector3(0, 0, -distance), true, GREATSWORD)
	await ticks(5)
	var hp := player.health.current_health
	enemy.call("_start_attack")
	await wait_until(func() -> bool: return not enemy.melee.is_busy(), 300)
	return player.health.current_health < hp


func _weapon(character: Node) -> WeaponComponent:
	return character.get_node("Weapon") as WeaponComponent


func _animator(character: Node) -> CharacterAnimator:
	return character.get_node("Animator") as CharacterAnimator


func _hand(character: Node) -> Node3D:
	return character.get_node("Visual/Model/Armature/Skeleton3D/RightHand") as Node3D


func _hitbox_shape(character: Node) -> CollisionShape3D:
	return character.get_node("Visual/Model/Armature/Skeleton3D/RightHand/AttackHitbox/CollisionShape3D") as CollisionShape3D


func _model_name(weapon: WeaponComponent) -> String:
	var model := weapon.get_model()
	if model == null:
		return "none"
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	return String(meshes[0].name) if meshes.size() > 0 else "no mesh"
