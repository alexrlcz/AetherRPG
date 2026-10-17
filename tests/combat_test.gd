extends SceneTree
## Headless combat verification on the real player and enemy scenes.
##   godot --headless --path . -s res://tests/combat_test.gd
## Exit code 0 = every check passed. Runs in real time (~1 min): hitstop and
## attack timings are real-time behaviour.

const PLAYER := preload("res://scenes/player/player.tscn")
const ENEMY := preload("res://scenes/enemies/enemy_knight.tscn")
const CAMERA := preload("res://scenes/camera/iso_camera_rig.tscn")
## The player's light combo: A -> B -> C (UAL2 Sword_Regular_A/B/C).
const SLASH := preload("res://resources/combat/player_combo_a.tres")
const RISING := preload("res://resources/combat/player_combo_b.tres")
const FINISHER := preload("res://resources/combat/player_combo_c.tres")
const CLEAVE := preload("res://resources/combat/player_cleave.tres")
const CLUB := preload("res://resources/weapons/club.tres")
const GREATSWORD := preload("res://resources/weapons/greatsword.tres")

var failures: int = 0
var world: Node3D
var hitstop: Hitstop
var camera_rig: IsoCameraRig


func check(condition: bool, message: String) -> void:
	print(("  PASS " if condition else "  FAIL ") + message)
	if not condition:
		failures += 1


func _initialize() -> void:
	await process_frame
	await test_miss()
	await test_valid_hit()
	await test_sweep_frame_rates()
	await test_knockback_wall()
	await test_hitstop_limits()
	await test_enemy_armor_and_recovery()
	await test_death_interrupts()
	await test_multiple_targets()
	await test_combo_and_buffer()
	await test_full_combo_connects()
	await test_commitment()
	await test_player_reaction()
	check(is_equal_approx(Engine.time_scale, 1.0), "time scale restored at the end")
	print("FAILURES: %d" % failures)
	quit(1 if failures > 0 else 0)


# --- Scenarios ---------------------------------------------------------------

func test_miss() -> void:
	print("1. A miss produces no hit confirmation")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	var enemy := spawn_enemy(Vector3(0, 0, 2.0), true)  # behind the player
	await ticks(5)
	var watch := Watch.new(self, player, [enemy])
	player.request_attack(false)
	await ticks(2)
	while player.melee.is_busy():
		await physics_frame
		watch.poll()
	check(enemy.health.current_health == enemy.health.max_health, "enemy behind the player not damaged")
	check(watch.feedback.hits_handled == 0, "no impact feedback")
	check(not watch.hitstop_seen, "no hitstop")
	check(watch.max_shake == 0.0, "no camera kick")
	check(not watch.reaction_seen, "no enemy reaction")
	check(count_effects() == 0, "no impact effects spawned")
	await clear_arena()


func test_valid_hit() -> void:
	print("2/3. A valid hit lands at contact, once, with reaction and feedback")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	var enemy := spawn_enemy(Vector3(0, 0, -1.3), true)
	await ticks(5)
	var start_z := enemy.global_position.z
	var hits := HitLog.new(enemy)
	var watch := Watch.new(self, player, [enemy])
	var phase_at_hit := -1
	var state_at_hit := -1
	var hitstop_at_hit := false
	var shake_at_hit := 0.0
	var knock_at_hit := Vector3.ZERO
	player.request_attack(false)
	while true:
		await physics_frame
		watch.poll()
		if hits.events.size() > 0 and phase_at_hit < 0:
			phase_at_hit = player.melee.phase
			state_at_hit = enemy.state
			hitstop_at_hit = hitstop.is_active()
			shake_at_hit = camera_rig.last_impulse_strength
			knock_at_hit = enemy.reaction.knockback_velocity
		if not player.melee.is_busy():
			break
	check(hits.events.size() == 1, "exactly one hit per attack (got %d)" % hits.events.size())
	if hits.events.is_empty():
		await clear_arena()
		return
	var event: HitEvent = hits.events[0]
	check(phase_at_hit == MeleeAttackComponent.Phase.STRIKE, "damage applied during the strike window")
	check(event.applied == SLASH.damage, "damage = %d" % event.applied)
	check(state_at_hit == EnemyController.State.STAGGER, "enemy staggered on the hit tick")
	check(hitstop_at_hit, "hitstop active on the hit tick")
	check(shake_at_hit > 0.0, "camera kicked on the hit tick")
	check(knock_at_hit.z < -1.0, "knockback pushes the enemy away (%.2f m/s)" % -knock_at_hit.z)
	check(hits.contact_offsets[0] <= enemy.hurtbox.get_body_radius() + 0.05,
		"contact point is on the enemy's body (%.2f m from its axis)" % hits.contact_offsets[0])
	check(event.swing_direction.x < -0.3 and event.swing_direction.y > 0.1,
		"rising slash moves right-to-left and upward at contact (%s)" % event.swing_direction)
	check(watch.feedback.hits_handled == 1, "feedback ran once")
	check(count_effects() >= 1 or watch.effects_seen, "impact effect spawned")
	await ticks(30)
	var pushed := start_z - enemy.global_position.z
	check(pushed > 0.1 and pushed < 1.0, "enemy recoiled %.2f m" % pushed)
	await clear_arena()


func test_sweep_frame_rates() -> void:
	print("4. Fast swings register at different physics rates")
	for rate in [20, 30, 60, 144]:
		Engine.physics_ticks_per_second = rate
		await make_arena()
		var player := spawn_player(Vector3.ZERO)
		# Thin targets: one where the rising slash enters (front right), one
		# straight ahead.
		var front := spawn_dummy(Vector3(0.0, 0, -1.25), 0.2)
		var left := spawn_dummy(Vector3(0.65, 0, -0.95), 0.2)
		await ticks(5)
		player.request_attack(false)
		await ticks(2)
		while player.melee.is_busy():
			await physics_frame
		check(front.current_health < 100 and left.current_health < 100,
			"%d Hz: both thin targets hit (front %d, right %d)" % [rate, front.current_health, left.current_health])
		check(front.current_health == 100 - SLASH.damage and left.current_health == 100 - SLASH.damage,
			"%d Hz: each hit exactly once" % rate)
		await clear_arena()
	Engine.physics_ticks_per_second = 60


func test_knockback_wall() -> void:
	print("5. Knockback respects walls")
	await make_arena([[Vector3(0, 1, -2.2), Vector3(6, 2, 0.4)]])  # wall face at z = -2.0
	var player := spawn_player(Vector3.ZERO)
	var enemy := spawn_enemy(Vector3(0, 0, -1.45), true)
	await ticks(5)
	var hits := HitLog.new(enemy)
	player.request_attack(true)
	var min_z := enemy.global_position.z
	for i in 120:
		await physics_frame
		min_z = minf(min_z, enemy.global_position.z)
	check(hits.events.size() == 1, "heavy attack connected")
	check(min_z >= -2.0 + 0.4 - 0.05, "enemy stopped by the wall (deepest z %.2f, wall -2.0)" % min_z)
	check(absf(enemy.global_position.y) < 0.1, "enemy stayed on the floor")
	await clear_arena()


func test_hitstop_limits() -> void:
	print("6. Hitstop never sticks or stacks")
	await make_arena()
	var begin := Time.get_ticks_msec()
	for i in 20:
		hitstop.request(0.1)
		await process_frame
	while hitstop.is_active():
		await process_frame
	var duration := (Time.get_ticks_msec() - begin) / 1000.0
	check(duration <= hitstop.max_duration + 0.05, "20 rapid requests froze %.3f s (max %.2f)" % [duration, hitstop.max_duration])
	check(is_equal_approx(Engine.time_scale, 1.0), "time scale back to 1")
	# A heavy hit's freeze must not leave the attack or AI stuck.
	var player := spawn_player(Vector3.ZERO)
	var enemy := spawn_enemy(Vector3(0, 0, -1.4), true)
	await ticks(5)
	player.request_attack(true)
	await ticks(2)
	await wait_until(func() -> bool: return not player.melee.is_busy(), 300)
	check(not player.melee.is_busy(), "player attack completed through hitstop")
	check(enemy.health.current_health < enemy.health.max_health, "heavy hit landed")
	await wait_until(func() -> bool: return enemy.state != EnemyController.State.STAGGER, 200)
	check(enemy.state != EnemyController.State.STAGGER, "enemy left hitstun")
	player.request_attack(false)
	await ticks(3)
	check(player.melee.is_busy(), "player can attack again")
	await clear_arena()


func test_enemy_armor_and_recovery() -> void:
	print("7. Enemy poise during its attack, and AI resuming after hitstun")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	player.health.max_health = 1000
	var enemy := spawn_enemy(Vector3(0, 0, -1.4), false)
	await ticks(3)
	# Light hit during the enemy's wind-up: armour holds, attack continues.
	enemy.call("_start_attack")
	player.request_attack(false)
	var hits := HitLog.new(enemy)
	await wait_until(func() -> bool: return hits.events.size() > 0, 120)
	check(hits.events.size() == 1, "light hit landed during the enemy wind-up")
	await physics_frame
	check(enemy.state == EnemyController.State.ATTACK and enemy.melee.is_busy(),
		"light hit did not interrupt the armoured attack")
	await wait_until(func() -> bool: return not player.melee.is_busy() and not enemy.melee.is_busy(), 200)
	await ticks(20)
	# Heavy hit during the wind-up: poise breaks, attack cancelled.
	player.request_attack(true)
	await ticks(6)
	enemy.call("_start_attack")
	await wait_until(func() -> bool: return hits.events.size() > 1, 120)
	await physics_frame
	check(enemy.state == EnemyController.State.STAGGER, "heavy hit staggered the enemy")
	check(not enemy.melee.is_busy(), "enemy attack cancelled")
	# The Cleave knocks down: the stun is the fall + get-up, not its hitstun.
	check(CLEAVE.knockdown and enemy.reaction.is_knocked_down(), "Cleave knocked the enemy down")
	var expected := enemy.reaction.knockdown_duration()
	var stun_start := Time.get_ticks_msec()
	await wait_until(func() -> bool: return enemy.state != EnemyController.State.STAGGER, 300)
	var stun := (Time.get_ticks_msec() - stun_start) / 1000.0
	check(enemy.state in [EnemyController.State.CHASE, EnemyController.State.ATTACK],
		"AI resumed chasing/attacking after %.2f s" % stun)
	check(absf(stun - expected) < 0.3, "knockdown ended on time (expected %.2f s)" % expected)
	await clear_arena()


func test_death_interrupts() -> void:
	print("8. Death interrupts movement, attacks and reactions")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	player.health.max_health = 1000
	var enemy := spawn_enemy(Vector3(0, 0, -1.4), false)
	await ticks(3)
	enemy.health.current_health = 10
	player.request_attack(true)
	await ticks(6)
	enemy.call("_start_attack")
	await wait_until(func() -> bool: return enemy.health.is_dead, 120)
	await physics_frame
	check(enemy.health.is_dead, "heavy hit killed the enemy")
	check(enemy.state == EnemyController.State.DEAD, "enemy state DEAD")
	check(not enemy.melee.is_busy(), "enemy attack cancelled by death")
	check(not enemy.reaction.is_reacting(), "no hit reaction on the killing blow")
	var ragdoll: RagdollComponent = enemy.get_node("Ragdoll")
	check(ragdoll.is_ragdoll, "ragdoll took over")
	await ticks(40)
	var finite := true
	for bone in ragdoll.get_physical_bones():
		var p := bone.global_position
		if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)) or p.length() > 30.0:
			finite = false
	check(finite, "ragdoll stayed valid through the lethal hitstop")
	var hp := player.health.current_health
	await ticks(60)
	check(player.health.current_health == hp, "dead enemy deals no further damage")
	await clear_arena()


func test_multiple_targets() -> void:
	print("9. Several enemies in the arc are each hit once")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	var a := spawn_enemy(Vector3(0.05, 0, -1.3), true)
	var b := spawn_enemy(Vector3(1.1, 0, -0.7), true)  # where the slash enters
	await ticks(5)
	var hits_a := HitLog.new(a)
	var hits_b := HitLog.new(b)
	var feedback: ImpactFeedbackComponent = player.get_node("ImpactFeedback")
	player.request_attack(false)
	await ticks(2)
	while player.melee.is_busy():
		await physics_frame
	check(hits_a.events.size() == 1 and hits_b.events.size() == 1,
		"both enemies hit once (%d, %d)" % [hits_a.events.size(), hits_b.events.size()])
	check(feedback.hits_handled == 2, "feedback for each hit")
	await clear_arena()


func test_combo_and_buffer() -> void:
	for rate in [60, 30, 120]:
		print("10. Combo chaining and input buffer at %d Hz" % rate)
		Engine.physics_ticks_per_second = rate
		await make_arena()
		var player := spawn_player(Vector3.ZERO)
		var melee := player.melee
		await ticks(3)
		# Follow-up pressed during recovery chains exactly at the chain point.
		player.request_attack(false)
		await wait_until(func() -> bool: return melee.phase == MeleeAttackComponent.Phase.RECOVERY, 120)
		player.request_attack(false)
		var recovery_ticks := 0
		while melee.current == SLASH:
			await physics_frame
			recovery_ticks += 1
		var chain_time: float = float(recovery_ticks) / rate
		check(melee.current == RISING, "light -> light chains into the second swing")
		check(absf(chain_time - SLASH.chain_delay) <= 2.0 / rate + 0.001,
			"chained %.3f s into recovery (chain_delay %.2f)" % [chain_time, SLASH.chain_delay])
		check(melee.animator.current_action() == RISING.animation,
			"second swing plays its own clip (%s)" % melee.animator.current_action())
		# Third press chains into the finisher.
		await wait_until(func() -> bool: return melee.phase == MeleeAttackComponent.Phase.RECOVERY, 120)
		player.request_attack(false)
		await wait_until(func() -> bool: return melee.current == FINISHER, 120)
		check(melee.current == FINISHER, "light -> light -> light chains into the finisher")
		# Heavy out of the finisher's recovery.
		await wait_until(func() -> bool: return melee.phase == MeleeAttackComponent.Phase.RECOVERY, 120)
		player.request_attack(true)
		await wait_until(func() -> bool: return melee.current == CLEAVE, 120)
		check(melee.current == CLEAVE, "light -> heavy chains into Cleave")
		await wait_until(func() -> bool: return not melee.is_busy(), 300)
		await ticks(5)
		# A press long before the chain point expires instead of auto-chaining.
		player.request_attack(false)
		await ticks(int(0.05 * rate))
		player.request_attack(false)
		var second_started := false
		await wait_until(func() -> bool: return not melee.is_busy(), 300)
		for i in 10:
			await physics_frame
			second_started = second_started or melee.is_busy()
		check(not second_started, "early press expired, no automatic follow-up")
		# Without a follow-up the swing plays into its return-to-guard clip.
		if rate == 60:
			player.request_attack(false)
			await wait_until(func() -> bool: return melee.phase == MeleeAttackComponent.Phase.RECOVERY, 120)
			var saw_recovery_clip := false
			while melee.is_busy():
				saw_recovery_clip = saw_recovery_clip \
					or melee.animator.current_action() == SLASH.recovery_animation
				await physics_frame
			check(saw_recovery_clip, "unchained swing plays %s" % SLASH.recovery_animation)
		await clear_arena()
	Engine.physics_ticks_per_second = 60


func test_full_combo_connects() -> void:
	print("10c. Every swing of the A -> B -> C combo lands on an enemy in front")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	var enemy := spawn_enemy(Vector3(0, 0, -1.3), true)
	enemy.health.max_health = 1000
	enemy.health.reset()
	await ticks(5)
	var hits := HitLog.new(enemy)
	var landed: Array[AttackProfile] = []
	enemy.hurtbox.hit_received.connect(func(event: HitEvent) -> void: landed.append(event.profile))
	for profile: AttackProfile in [SLASH, RISING, FINISHER]:
		player.request_attack(false)
		await wait_until(func() -> bool:
			return player.melee.current == profile \
				and player.melee.phase == MeleeAttackComponent.Phase.RECOVERY, 200)
	await wait_until(func() -> bool: return not player.melee.is_busy(), 300)
	var expected: Array[AttackProfile] = [SLASH, RISING, FINISHER]
	check(landed == expected,
		"A, B and C each hit once (%s)" % [landed.map(func(p: AttackProfile) -> String: return p.display_name)])
	check(hits.events.size() == 3, "three hits total")
	await clear_arena()


func test_commitment() -> void:
	print("10b. Attack commitment: rooted, lunge only, movement cancel")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	await ticks(3)
	Input.action_press("move_forward")
	await ticks(40)
	var start := player.global_position
	player.request_attack(false)
	await ticks(2)
	var moved_during_input := 0.0
	while player.melee.is_busy() and not player.melee.can_move_cancel():
		await physics_frame
	moved_during_input = flat(player.global_position - start).length()
	check(absf(moved_during_input - SLASH.lunge_distance) < 0.12,
		"only the lunge moved the player during the attack (%.2f m, lunge %.2f)" % [moved_during_input, SLASH.lunge_distance])
	await ticks(2)
	check(not player.melee.is_busy(), "holding a direction cancels late recovery")
	await ticks(10)
	check(flat(player.velocity).length() > 1.0, "movement resumed (%.2f m/s)" % flat(player.velocity).length())
	Input.action_release("move_forward")
	await clear_arena()


func test_player_reaction() -> void:
	print("11. Player hit reactions")
	await make_arena()
	var player := spawn_player(Vector3.ZERO)
	player.health.max_health = 1000
	var enemy := spawn_enemy(Vector3(0, 0, -1.4), false)
	await ticks(3)
	enemy.call("_start_attack")
	var hp := player.health.current_health
	await wait_until(func() -> bool: return player.health.current_health < hp, 120)
	await physics_frame
	check(player.reaction.is_reacting(), "idle player staggered by the enemy hit")
	Input.action_press("move_back")
	var before := player.global_position
	await ticks(3)
	var during := flat(player.velocity)
	check(during.dot(Vector3(0, 0, 1)) > 0.0 and during.length() <= 5.0,
		"stunned player is pushed back, input ignored")
	Input.action_release("move_back")
	await wait_until(func() -> bool: return not player.reaction.is_reacting(), 60)
	check(not player.reaction.is_reacting(), "player recovers")
	await wait_until(func() -> bool: return not enemy.melee.is_busy(), 200)
	# Armoured while attacking: one enemy hit does not cancel the player's swing.
	await ticks(40)
	player.request_attack(true)
	await ticks(3)
	enemy.call("_start_attack")
	hp = player.health.current_health
	await wait_until(func() -> bool: return player.health.current_health < hp or not player.melee.is_busy(), 200)
	if player.health.current_health < hp:
		await physics_frame
		check(player.melee.is_busy() and player.melee.current == CLEAVE,
			"player's attack survives one hit (poise)")
	else:
		check(false, "enemy hit the attacking player")
	await clear_arena()


# --- Helpers -----------------------------------------------------------------

func make_arena(walls: Array = []) -> void:
	world = Node3D.new()
	root.add_child(world)
	hitstop = Hitstop.new()
	world.add_child(hitstop)
	var nav := NavigationRegion3D.new()
	world.add_child(nav)
	_box(nav, Vector3(0, -0.5, 0), Vector3(30, 1, 30))
	for wall in walls:
		_box(nav, wall[0], wall[1])
	var mesh := NavigationMesh.new()
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1
	mesh.agent_height = 2.0
	nav.navigation_mesh = mesh
	nav.bake_navigation_mesh(false)
	camera_rig = CAMERA.instantiate()
	world.add_child(camera_rig)
	camera_rig.camera.make_current()
	await ticks(3)


func clear_arena() -> void:
	Input.action_release("move_forward")
	Input.action_release("move_back")
	world.queue_free()
	await ticks(2)
	Engine.time_scale = 1.0


func spawn_player(at: Vector3) -> PlayerController:
	var player: PlayerController = PLAYER.instantiate()
	player.position = at
	player.aim_override = Vector3.FORWARD
	world.add_child(player)
	camera_rig.set_target(player)
	return player


## A real enemy facing the player. `passive` = never notices anyone, so tests
## control everything it does. It wields `weapon` (the club by default)
## instead of a random one.
func spawn_enemy(at: Vector3, passive: bool, weapon: WeaponDefinition = CLUB) -> EnemyController:
	var enemy: EnemyController = ENEMY.instantiate()
	var weapon_node := enemy.get_node("Weapon") as WeaponComponent
	weapon_node.random_weapons = []
	weapon_node.weapon = weapon
	if passive:
		var stats: EnemyStats = enemy.stats.duplicate()
		stats.detection_radius = 0.0
		stats.lose_interest_radius = 0.01
		enemy.stats = stats
	enemy.position = at
	enemy.rotation.y = atan2(at.x, at.z)  # face the origin
	world.add_child(enemy)
	return enemy


## Bare enemy hurtbox (no body, no AI) with a capsule of `radius`.
func spawn_dummy(at: Vector3, radius: float) -> HealthComponent:
	var hurtbox := HurtboxComponent.new()
	hurtbox.collision_layer = 16
	hurtbox.collision_mask = 0
	var health := HealthComponent.new()
	health.max_health = 100
	hurtbox.add_child(health)
	hurtbox.health = health
	var cs := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = 1.8
	cs.shape = capsule
	cs.position.y = 0.9
	hurtbox.add_child(cs)
	hurtbox.position = at
	world.add_child(hurtbox)
	return health


func count_effects() -> int:
	var count := 0
	for child in root.get_children():
		if child is ImpactEffect:
			count += 1
	return count


func ticks(n: int) -> void:
	for i in n:
		await physics_frame


func wait_until(condition: Callable, max_ticks: int) -> bool:
	for i in max_ticks:
		if condition.call():
			return true
		await physics_frame
	return condition.call()


func _box(parent: Node, at: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	body.add_child(cs)
	body.position = at
	parent.add_child(body)


static func flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


## Records every hit an enemy receives.
class HitLog:
	var events: Array[HitEvent] = []
	## Per hit: distance from the contact point to the body's axis, at hit time.
	var contact_offsets: Array[float] = []

	func _init(enemy: EnemyController) -> void:
		enemy.hurtbox.hit_received.connect(_on_hit.bind(enemy.hurtbox))

	func _on_hit(event: HitEvent, hurtbox: HurtboxComponent) -> void:
		events.append(event)
		var axis := hurtbox.get_body_segment()
		var closest := Geometry3D.get_closest_point_to_segment(event.point, axis[0], axis[1])
		contact_offsets.append(event.point.distance_to(closest))


## Samples hit-confirmation side effects each tick.
class Watch:
	var test  # The test SceneTree (untyped: reads its script members).
	var feedback: ImpactFeedbackComponent
	var enemies: Array
	var hitstop_seen: bool = false
	var reaction_seen: bool = false
	var effects_seen: bool = false
	var max_shake: float = 0.0

	func _init(t, player: PlayerController, list: Array) -> void:
		test = t
		feedback = player.get_node("ImpactFeedback")
		enemies = list

	func poll() -> void:
		hitstop_seen = hitstop_seen or test.hitstop.is_active()
		max_shake = maxf(max_shake, test.camera_rig.last_impulse_strength)
		effects_seen = effects_seen or test.count_effects() > 0
		for enemy: EnemyController in enemies:
			reaction_seen = reaction_seen or enemy.reaction.is_reacting()
