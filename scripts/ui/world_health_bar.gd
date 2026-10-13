class_name WorldHealthBar
extends MeshInstance3D
## Health bar floating above a character. Uses billboard_bar.gdshader;
## the fill amount is a per-instance shader parameter.

@export var health: HealthComponent
## Hide the bar while the owner is at full health.
@export var hide_when_full: bool = false


func _ready() -> void:
	health.health_changed.connect(_on_health_changed)
	health.died.connect(hide)
	_on_health_changed(health.current_health, health.max_health)


func _on_health_changed(current: int, maximum: int) -> void:
	set_instance_shader_parameter(&"ratio", float(current) / float(maxi(maximum, 1)))
	visible = current > 0 and not (hide_when_full and current >= maximum)
