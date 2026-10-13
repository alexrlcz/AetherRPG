class_name HurtboxComponent
extends Area3D
## Area that can receive hits. Forwards damage to a HealthComponent.
##
## Put it on the "player_hurtbox" or "enemy_hurtbox" physics layer;
## HitboxComponents choose targets through their collision mask.

signal hurt(amount: int, source: Node)

@export var health: HealthComponent


func _ready() -> void:
	monitoring = false
	monitorable = true


func receive_hit(amount: int, source: Node) -> void:
	if health == null or health.is_dead:
		return
	var applied := health.take_damage(amount, source)
	if applied > 0:
		hurt.emit(applied, source)
