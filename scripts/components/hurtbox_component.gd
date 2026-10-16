class_name HurtboxComponent
extends Area3D
## Area that can receive hits. Forwards damage to a HealthComponent.
##
## Put it on the "player_hurtbox" or "enemy_hurtbox" physics layer;
## HitboxComponents choose targets through their collision mask.

signal hurt(amount: int, source: Node)
## Every hit that removed health, with its full details (reactions, effects).
## Emitted after HealthComponent's signals, so `event.lethal` is final.
signal hit_received(event: HitEvent)

@export var health: HealthComponent

## The latest hit, set before damage is applied (read by `died` listeners
## such as the ragdoll).
var last_hit: HitEvent


func _ready() -> void:
	monitoring = false
	monitorable = true


## Plain damage without attack data (hazards, scripts).
func receive_hit(amount: int, source: Node) -> void:
	var event := HitEvent.new()
	event.source = source
	event.amount = amount
	event.point = global_position + Vector3.UP
	receive_event(event)


func receive_event(event: HitEvent) -> void:
	if health == null or health.is_dead:
		return
	event.hurtbox = self
	last_hit = event
	event.applied = health.take_damage(event.amount, event.source)
	event.lethal = health.is_dead
	if event.applied > 0:
		hurt.emit(event.applied, event.source)
		hit_received.emit(event)


## Vertical world-space segment through the body (the capsule's spine), used
## to place contact points.
func get_body_segment() -> Array[Vector3]:
	for child in get_children():
		var cs := child as CollisionShape3D
		if cs == null or cs.shape == null:
			continue
		var centre := cs.global_position
		var half := 0.0
		if cs.shape is CapsuleShape3D:
			var capsule := cs.shape as CapsuleShape3D
			half = maxf(capsule.height * 0.5 - capsule.radius, 0.0)
		elif cs.shape is BoxShape3D:
			half = (cs.shape as BoxShape3D).size.y * 0.5
		var up := cs.global_basis.y.normalized() * half
		return [centre - up, centre + up]
	return [global_position, global_position]


func get_body_radius() -> float:
	for child in get_children():
		var cs := child as CollisionShape3D
		if cs and cs.shape is CapsuleShape3D:
			return (cs.shape as CapsuleShape3D).radius
	return 0.3
