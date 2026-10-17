extends "res://tests/combat_test.gd"
## Headless enemy checks on the real enemy, player and main scenes (reuses the
## combat test's arena and helpers).
##   godot --headless --path . -s res://tests/enemy_test.gd
## Exit code 0 = every check passed.



func _initialize() -> void:
	await process_frame
	await test_club_hitbox()
	await test_strike_window()
	await test_chase_and_hit()
	await test_dash_knocks_player_down()
	await test_hits_on_downed_enemy()
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


func test_club_hitbox() -> void:
	print("1. The club is the hitbox: reach in front, nothing behind or far")
	await make_arena()
	var enemy := spawn_enemy(Vector3(0, 0, -5), true)
	await ticks(2)
	var hitbox := enemy.melee.hitbox
	check(hitbox.get_parent().name == &"RightHand", "hitbox rides the RightHand bone")
	check(hitbox.sweep, "hitbox sweeps between ticks")
	check(enemy.melee.telegraph == null and enemy.find_child("Telegraph", true, false) == null,
		"no ground telegraph")
	var reach := enemy.attack_range
	await clear_arena()
	check(await _swing_hits(Vector3(0, 0, -1.0), Vector3.ZERO), "hits at 1.0 m in front")
	check(await _swing_hits(Vector3(0, 0, -reach), Vector3.ZERO),
		"hits at attack_range (%.1f m)" % reach)
	check(await _swing_hits(Vector3(0, 0, -1.3), Vector3(0.6, 0, 0)), "hits 0.6 m off-centre")
	check(not await _swing_hits(Vector3(0, 0, -2.3), Vector3.ZERO), "misses at 2.3 m")
	check(not await _swing_hits(Vector3(0, 0, -1.2), Vector3.ZERO, true), "misses behind it")


func test_strike_window() -> void:
	print("2. The club only hurts during the strike")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	player.health.max_health = 1000
	var enemy := spawn_enemy(Vector3(0, 0, -1.3), true)
	await ticks(3)
	var hitbox := enemy.melee.hitbox
	var stray := [0]
	var hit_phase := [-1]
	var hp := player.health.current_health
	enemy.call("_start_attack")
	for i in 200:
		var phase := enemy.melee.phase
		# close_after_current_pose() keeps it open up to 2 ticks into recovery.
		var allowed := phase == MeleeAttackComponent.Phase.STRIKE \
			or (phase == MeleeAttackComponent.Phase.RECOVERY and enemy.melee.phase_time < 0.05)
		if hitbox.active and not allowed:
			stray[0] += 1
		if hit_phase[0] < 0 and player.health.current_health < hp:
			hit_phase[0] = phase
		if not enemy.melee.is_busy():
			break
		await physics_frame
	check(stray[0] == 0, "hitbox closed outside the strike (%d stray ticks)" % stray[0])
	check(hit_phase[0] in [MeleeAttackComponent.Phase.STRIKE, MeleeAttackComponent.Phase.RECOVERY],
		"damage landed at the strike, not the wind-up (phase %d)" % hit_phase[0])
	await clear_arena()


func test_chase_and_hit() -> void:
	print("3. A free enemy closes in and lands the club on an idle player")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	player.health.max_health = 1000
	var enemy := spawn_enemy(Vector3(0, 0, -5), false)
	var hp := player.health.current_health
	var hit := await wait_until(func() -> bool: return player.health.current_health < hp, 400)
	check(hit, "enemy hit the player (state %s)" % EnemyController.State.keys()[enemy.state])
	await clear_arena()


func test_dash_knocks_player_down() -> void:
	print("5. Mid range: the enemy dashes in and knocks the player down")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	player.health.max_health = 1000
	var enemy := spawn_enemy(Vector3(0, 0, -4.2), false)
	var dash := enemy.dash_attack
	var start_gap := flat(enemy.global_position - player.global_position).length()
	var dashed := await wait_until(func() -> bool: return enemy.melee.current == dash, 30)
	check(dashed, "dash attack chosen at %.1f m" % start_gap)
	var hp := player.health.current_health
	await wait_until(func() -> bool: return player.health.current_health < hp, 120)
	var gap := flat(enemy.global_position - player.global_position).length()
	check(player.health.current_health < hp, "the lunge closed the gap (%.1f m) and hit" % gap)
	await physics_frame
	check(player.reaction.is_knocked_down(), "player knocked down")
	check(_animator(player).current_action() == &"UAL2/Hit_Knockback",
		"Hit_Knockback plays (%s)" % _animator(player).current_action())
	var to_enemy := flat(enemy.global_position - player.global_position).normalized()
	check(flat(-player.global_basis.z).dot(to_enemy) > 0.9, "faces the attacker while falling")
	check((player.get_node("Hurtbox") as HurtboxComponent).invulnerable, "invulnerable while down")
	check(enemy.get(&"_dash_cooldown_left") > 0.0, "dash on cooldown")
	await wait_until(func() -> bool:
		return _animator(player).current_action() == &"UAL2/LayToIdle", 120)
	check(_animator(player).current_action() == &"UAL2/LayToIdle", "LayToIdle follows")
	Input.action_press("move_back")
	var moved_while_down := [0.0]
	var origin := player.global_position
	await wait_until(func() -> bool:
		if player.reaction.is_knocked_down():
			moved_while_down[0] = maxf(moved_while_down[0],
				flat(player.velocity).length() - flat(player.reaction.knockback_velocity).length())
		return not player.reaction.is_knocked_down(), 200)
	check(moved_while_down[0] < 0.1, "input ignored while getting up")
	check(not (player.get_node("Hurtbox") as HurtboxComponent).invulnerable, "vulnerable again once up")
	await ticks(20)
	check(flat(player.global_position - origin).length() > 0.3, "moves again after getting up")
	Input.action_release("move_back")
	await clear_arena()


func test_hits_on_downed_enemy() -> void:
	print("6. A downed enemy takes damage but stays down for the same time")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	var enemy := spawn_enemy(Vector3(0, 0, -1.3), true)
	enemy.health.max_health = 1000
	await ticks(3)
	player.request_attack(true)  # Cleave: knockdown.
	await wait_until(func() -> bool: return enemy.reaction.is_knocked_down(), 120)
	check(enemy.reaction.is_knocked_down(), "Cleave knocked the enemy down")
	var down_at := Time.get_ticks_msec()
	var expected := enemy.reaction.knockdown_duration()
	await wait_until(func() -> bool: return not player.melee.is_busy(), 120)
	await ticks(5)
	var hp := enemy.health.current_health
	# Step in: the knockback threw it out of reach.
	player.global_position = enemy.global_position + flat(player.global_position - enemy.global_position).normalized() * 1.2
	player.facing_direction = flat(enemy.global_position - player.global_position).normalized()
	player.rotation.y = atan2(-player.facing_direction.x, -player.facing_direction.z)
	player.request_attack(false)
	await wait_until(func() -> bool: return enemy.health.current_health < hp, 60)
	check(enemy.health.current_health < hp, "hit on the downed enemy dealt damage")
	check(enemy.reaction.is_knocked_down(), "still down after the extra hit")
	await wait_until(func() -> bool: return not enemy.reaction.is_knocked_down(), 300)
	var down_for := (Time.get_ticks_msec() - down_at) / 1000.0
	check(absf(down_for - expected) < 0.3, "down %.2f s (knockdown %.2f s, not restarted)" % [down_for, expected])
	await clear_arena()


func _animator(character: Node) -> CharacterAnimator:
	return character.get_node("Animator") as CharacterAnimator


## One enemy swing from a passive enemy at `enemy_at` facing +Z (or -Z when
## `facing_away`), started on the melee component directly so the enemy does
## not turn to the player; true if the player at `player_at` took damage.
func _swing_hits(enemy_at: Vector3, player_at: Vector3, facing_away: bool = false) -> bool:
	await make_arena()
	var player := spawn_player(player_at)
	player.health.max_health = 1000
	var enemy := spawn_enemy(enemy_at, true)
	enemy.facing_direction = Vector3.FORWARD if facing_away else Vector3.BACK
	enemy.rotation.y = 0.0 if facing_away else PI
	await ticks(3)
	var hp := player.health.current_health
	enemy.melee.start()
	await wait_until(func() -> bool: return not enemy.melee.is_busy(), 200)
	var hit := player.health.current_health < hp
	await clear_arena()
	return hit
