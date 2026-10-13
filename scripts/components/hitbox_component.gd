class_name HitboxComponent
extends Area3D
## Area that deals damage to overlapping HurtboxComponents while active.
##
## Each hurtbox is hit once per activation, unless `rehit_interval` > 0,
## in which case it is hit again every `rehit_interval` seconds while it
## stays inside (useful for hazards and damage-over-time zones).
## Set the collision mask to the hurtbox layer(s) this hitbox should hurt.

signal hit_landed(hurtbox: HurtboxComponent, amount: int)

@export var damage: int = 10
@export var active: bool = false:
	set = set_active
## Seconds before the same hurtbox can be hit again. 0 = once per activation.
@export var rehit_interval: float = 0.0
## Reported as the damage source. Defaults to this scene's owner.
@export var source: Node

var _time: float = 0.0
var _last_hit_time: Dictionary = {}  # hurtbox instance id -> _time of last hit


func _ready() -> void:
	monitoring = true
	monitorable = false
	if source == null:
		source = owner


func set_active(value: bool) -> void:
	active = value
	_last_hit_time.clear()


func _physics_process(delta: float) -> void:
	_time += delta
	if not active:
		return
	for area in get_overlapping_areas():
		var hurtbox := area as HurtboxComponent
		if hurtbox == null:
			continue
		var id := hurtbox.get_instance_id()
		if _last_hit_time.has(id):
			if rehit_interval <= 0.0 or _time - _last_hit_time[id] < rehit_interval:
				continue
		_last_hit_time[id] = _time
		hurtbox.receive_hit(damage, source)
		hit_landed.emit(hurtbox, damage)
