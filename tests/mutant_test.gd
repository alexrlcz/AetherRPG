extends "res://tests/combat_test.gd"
## Headless checks of the level 5 mutant boss: its encounter on level 5, its
## animations, the roar / flex intro when it first notices the player, its
## attacks landing, the hip-hop dance when it kills the player (not when
## something else does), and its death animation (reuses the combat test's
## arena and helpers).
##   godot --headless --path . -s res://tests/mutant_test.gd
## Exit code 0 = every check passed.

const MUTANT := preload("res://scenes/enemies/enemy_mutant.tscn")


func _initialize() -> void:
	await process_frame
	PlayerProfile.current().save_path = ""
	test_level_five()
	await test_intro_and_fight()
	await test_victory_dance()
	await test_no_dance_for_other_deaths()
	await test_death()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_level_five() -> void:
	print("1. Level 5's boss is the mutant; other boss floors keep the Warden")
	var pool := LevelPool.new()
	var five := pool.layout_for(1234, 5)
	var ten := pool.layout_for(1234, 10)
	check(five.boss != null and five.boss.title == "Warrok the Mutant", "level 5: %s" % (five.boss.title if five.boss else "none"))
	check(ten.boss != null and ten.boss.title == "Ashbound Warden", "level 10: %s" % (ten.boss.title if ten.boss else "none"))
	var spawn := five.spawns.filter(func(s: Dictionary) -> bool: return s.get("boss", false))
	check(spawn.size() == 1 and (spawn[0]["entry"] as EnemyEntry).scene == MUTANT, "the boss spawn is the mutant scene")


func test_intro_and_fight() -> void:
	print("2. It roars or flexes when it first sees the player, then fights")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	player.health.max_health = 1000
	player.health.reset()
	var mutant := _spawn(Vector3(0, 0, -7))
	var boss := mutant.get_node("MutantBoss") as MutantBoss
	var intro := [&""]
	boss.intro_started.connect(func(anim: StringName) -> void: intro[0] = anim)
	await ticks(3)
	var anims := (mutant.get_node("Visual/Model/AnimationPlayer") as AnimationPlayer)
	for clip in ["Idle", "Walk", "Swipe", "JumpAttack", "Roar", "Flex", "Dance", "Dying"]:
		check(anims.has_animation("Mutant/" + clip), "has Mutant/%s" % clip)
	await wait_until(func() -> bool: return boss.intro_played, 120)
	check(intro[0] in [&"Mutant/Roar", &"Mutant/Flex"], "intro: %s" % intro[0])
	var animator := mutant.get_node("Animator") as CharacterAnimator
	check(animator.current_action() == intro[0] and mutant.is_held(), "playing it, standing still")
	var start := mutant.global_position
	await ticks(60)
	check(mutant.global_position.distance_to(start) < 0.2 and mutant.is_held(), "it doesn't move during the intro")
	var hp := player.health.current_health
	await wait_until(func() -> bool: return player.health.current_health < hp, 900)
	check(not mutant.is_held() and player.health.current_health < hp, "then it attacks and lands a hit (%d -> %d)"
		% [hp, player.health.current_health])
	await clear_arena()


func test_victory_dance() -> void:
	print("3. When it kills the player, it dances")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	var mutant := _spawn(Vector3(0, 0, -2.5))
	var boss := mutant.get_node("MutantBoss") as MutantBoss
	await wait_until(func() -> bool: return boss.intro_played and not mutant.is_held(), 400)
	player.health.take_damage(player.health.current_health - 1)
	await wait_until(func() -> bool: return player.is_dead, 900)
	await ticks(2)
	var animator := mutant.get_node("Animator") as CharacterAnimator
	check(player.is_dead and boss.dancing and animator.current_action() == &"Mutant/Dance", "the player died; Mutant/Dance plays")
	await ticks(120)
	check(animator.current_action() == &"Mutant/Dance" and mutant.is_held(), "it keeps dancing in place")
	await clear_arena()


func test_no_dance_for_other_deaths() -> void:
	print("4. No dance when something else kills the player")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	var mutant := _spawn(Vector3(0, 0, -12))
	await ticks(3)
	player.get_node("Hurtbox").receive_hit(9999, null)
	await ticks(3)
	check(player.is_dead and not (mutant.get_node("MutantBoss") as MutantBoss).dancing, "no dance")
	await clear_arena()


func test_death() -> void:
	print("5. It dies with its own animation")
	await make_arena()
	spawn_player(Vector3(0, 0, 20))
	var mutant := _spawn(Vector3.ZERO)
	await ticks(3)
	mutant.health.take_damage(mutant.health.current_health)
	await ticks(3)
	var anims := mutant.get_node("Visual/Model/AnimationPlayer") as AnimationPlayer
	check(mutant.state == EnemyController.State.DEAD and anims.current_animation == "Mutant/Dying", "Mutant/Dying plays")
	await clear_arena()


func _spawn(at: Vector3) -> EnemyController:
	var mutant: EnemyController = MUTANT.instantiate()
	mutant.health_scale = 10.0
	mutant.poise_scale = 3.0
	mutant.position = at
	mutant.rotation.y = atan2(at.x, at.z)
	world.add_child(mutant)
	return mutant
