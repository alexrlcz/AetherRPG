extends "res://tests/combat_test.gd"
## Headless CharacterStats checks: the modifier maths, the final values
## pushed into health / stamina / melee / hurtbox, gear armor on the player,
## the MOVE_SPEED multiplier on real movement, and enemies' stats (EnemyStats
## as the base, elite scaling as modifiers). Reuses the combat test's arena.
##   godot --headless --path . -s res://tests/stats_test.gd
## Exit code 0 = every check passed.

const HELMET := preload("res://resources/items/gear/helmet_fantasy.tres")
const SHIELD := preload("res://resources/items/gear/shield_wooden.tres")
const IMP := preload("res://scenes/enemies/enemy_imp.tscn")
const Stat := CharacterStats.Stat
const Kind := StatModifier.Kind


func _initialize() -> void:
	await process_frame
	PlayerProfile.current().save_path = ""
	test_maths()
	await test_player_base()
	await test_gear_armor()
	await test_health_and_speed()
	await test_enemies()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_maths() -> void:
	print("1. Modifier maths and pushing into components")
	var stats := CharacterStats.new()
	var health := HealthComponent.new()
	var stamina := StaminaComponent.new()
	var melee := MeleeAttackComponent.new()
	var hurtbox := HurtboxComponent.new()
	stats.health = health
	stats.stamina = stamina
	stats.melee = melee
	stats.hurtbox = hurtbox
	var base := StatBlock.new()
	base.max_health = 100
	base.armor = 20.0
	stats.set_base(base)
	check(stats.get_value(Stat.MAX_HEALTH) == 100.0 and stats.get_value(Stat.DAMAGE) == 1.0
		and stats.get_value(Stat.MOVE_SPEED) == 1.0, "base values; damage and speed start at x1")
	stats.set_modifiers(&"a", [StatModifier.make(Stat.MAX_HEALTH, Kind.FLAT, 20.0),
		StatModifier.make(Stat.MAX_HEALTH, Kind.PERCENT, 0.1)])
	stats.set_modifiers(&"b", [StatModifier.make(Stat.MAX_HEALTH, Kind.PERCENT, 0.1),
		StatModifier.make(Stat.MAX_HEALTH, Kind.MULTIPLY, 2.0)])
	check(is_equal_approx(stats.get_value(Stat.MAX_HEALTH), 288.0),
		"(100 + 20) x (1 + 10%% + 10%%) x 2 = %.0f" % stats.get_value(Stat.MAX_HEALTH))
	check(health.max_health == 288 and health.current_health == 288, "pushed to health (full stays full)")
	stats.remove_modifiers(&"b")
	check(is_equal_approx(stats.get_value(Stat.MAX_HEALTH), 132.0) and health.max_health == 132,
		"removing a source undoes only its modifiers (%d)" % health.max_health)
	stats.set_modifiers(&"c", [StatModifier.make(Stat.DAMAGE, Kind.PERCENT, 0.25),
		StatModifier.make(Stat.MAX_STAMINA, Kind.FLAT, 50.0), StatModifier.make(Stat.STAMINA_REGEN, Kind.MULTIPLY, 0.5)])
	check(is_equal_approx(melee.damage_scale, 1.25), "damage x1.25 -> melee.damage_scale")
	check(is_equal_approx(stamina.max_stamina, 150.0) and is_equal_approx(stamina.regen_rate, 15.0),
		"stamina 150, regen 15/s pushed")
	check(is_equal_approx(hurtbox.damage_reduction, 20.0 / 120.0), "armor 20 -> %.0f%% less damage"
		% (hurtbox.damage_reduction * 100.0))
	check(CharacterStats.armor_reduction(0.0) == 0.0 and is_equal_approx(CharacterStats.armor_reduction(100.0), 0.5),
		"armor 0 -> 0%, armor 100 -> 50%")
	stats.set_modifiers(&"d", [StatModifier.make(Stat.ARMOR, Kind.FLAT, -50.0)])
	check(stats.get_value(Stat.ARMOR) == 0.0 and hurtbox.damage_reduction == 0.0, "values never go below 0")
	for node: Node in [stats, health, stamina, melee, hurtbox]:
		node.free()


func test_player_base() -> void:
	print("2. The player's base stats")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(2)
	var stats := player.character_stats
	check(stats != null and stats.base.resource_path.ends_with("player_stats.tres"), "base from player_stats.tres")
	check(player.health.max_health == 100 and is_equal_approx(player.stamina.max_stamina, 100.0)
		and is_equal_approx(player.stamina.regen_rate, 30.0), "health 100, stamina 100, regen 30/s")
	check(stats.get_value(Stat.ARMOR) == 0.0 and player.melee.damage_scale == 1.0, "no armor, damage x1")
	await clear_arena()


func test_gear_armor() -> void:
	print("3. Gear armor reduces damage taken")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(2)
	var stats := player.character_stats
	_wear(player, [HELMET, SHIELD])
	check(stats.get_value(Stat.ARMOR) == 15.0, "helmet +10 and shield +5: armor %.0f" % stats.get_value(Stat.ARMOR))
	_hit(player, Vector3(0, 0, 2), 20)
	var expected := roundi(20 * (1.0 - CharacterStats.armor_reduction(15.0)))
	check(player.health.current_health == 100 - expected, "a 20 hit does %d (%d hp)"
		% [expected, player.health.current_health])
	_wear(player, [])
	check(stats.get_value(Stat.ARMOR) == 0.0 and stats.get_modifiers(CharacterStats.GEAR_SOURCE).is_empty(),
		"taking the gear off removes its armor")
	_hit(player, Vector3(0, 0, 2), 1)
	check(player.health.current_health == 100 - expected - 1, "a hit always does at least 1")
	await clear_arena()


func test_health_and_speed() -> void:
	print("4. Max health and move speed modifiers on the real player")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(2)
	var stats := player.character_stats
	stats.set_modifiers(&"test", [StatModifier.make(Stat.MAX_HEALTH, Kind.FLAT, 20.0),
		StatModifier.make(Stat.MOVE_SPEED, Kind.PERCENT, 0.2)])
	check(player.health.max_health == 120 and player.health.current_health == 120, "health 120, still full")
	Input.action_press("move_forward")
	await ticks(60)
	var speed := Vector2(player.velocity.x, player.velocity.z).length()
	check(absf(speed - player.move_speed * 1.2) < 0.25, "+20%% speed: runs %.2f m/s (base %.1f)"
		% [speed, player.move_speed])
	Input.action_release("move_forward")
	stats.remove_modifiers(&"test")
	check(player.health.max_health == 100 and player.health.current_health == 100, "back to 100 / 100")
	await clear_arena()


func test_enemies() -> void:
	print("5. Enemies: EnemyStats is the base, elite scaling is modifiers")
	await make_arena()
	var knight := spawn_enemy(Vector3(0, 0, -4), true)
	var imp: EnemyController = IMP.instantiate()
	imp.position = Vector3(3, 0, -4)
	world.add_child(imp)
	var elite: EnemyController = IMP.instantiate()
	elite.health_scale = 2.0
	elite.damage_scale = 1.5
	elite.position = Vector3(-3, 0, -4)
	world.add_child(elite)
	await ticks(2)
	check(knight.health.max_health == 60 and is_equal_approx(knight.stamina.max_stamina, 60.0)
		and is_equal_approx(knight.stamina.regen_rate, 8.0), "knight: the EnemyStats defaults (60 hp, 60 stamina, 8/s)")
	check(imp.health.max_health == 45 and is_equal_approx(imp.stamina.max_stamina, 55.0)
		and is_equal_approx(imp.stamina.regen_rate, 9.0), "imp: its own .tres values (45 hp, 55, 9/s)")
	check(imp.character_stats.base == imp.stats and imp.health.current_health == 45, "base is its EnemyStats, full health")
	check(elite.health.max_health == 90 and elite.health.current_health == 90, "elite x2 health: %d"
		% elite.health.max_health)
	check(is_equal_approx(elite.melee.damage_scale, 1.5) and imp.melee.damage_scale == 1.0, "elite x1.5 damage")
	check(elite.stats.max_health == 45, "the elite's own stats copy is not scaled twice")
	imp.character_stats.set_modifiers(&"test", [StatModifier.make(Stat.ARMOR, Kind.FLAT, 100.0)])
	_hit(imp, Vector3(3, 0, 0), 20)
	check(imp.health.current_health == 35, "an enemy with 100 armor takes half (%d hp)" % imp.health.current_health)
	await clear_arena()


func _hit(target: CharacterBody3D, from: Vector3, amount: int) -> void:
	var attacker := Node3D.new()
	world.add_child(attacker)
	attacker.global_position = from
	var event := HitEvent.new()
	event.source = attacker
	event.amount = amount
	event.point = target.global_position + Vector3.UP
	var away := target.global_position - from
	away.y = 0.0
	event.direction = away.normalized()
	(target.get_node("Hurtbox") as HurtboxComponent).receive_event(event)
	attacker.queue_free()


func _wear(player: PlayerController, items: Array) -> void:
	var component := player.get_node("Appearance") as AppearanceComponent
	var look := component.appearance.duplicate() as CharacterAppearance
	var none: Array[GearDefinition] = []
	look.gear = none
	for item: GearDefinition in items:
		look.set_gear(item.slot, item)
	component.apply(look)
