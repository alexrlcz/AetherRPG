class_name WorldStaminaBar
extends MeshInstance3D
## Stamina bar floating above a character (under its WorldHealthBar). Uses
## billboard_bar.gdshader with its own fill colour; the fill amount is the
## per-instance shader parameter. Hidden at full stamina and once the owner
## dies; dimmed while exhausted.

@export var stamina: StaminaComponent
## Optional: hides the bar for good on death.
@export var health: HealthComponent
## Alpha while exhausted.
@export var exhausted_alpha: float = 0.45


func _ready() -> void:
	stamina.stamina_changed.connect(_on_stamina_changed)
	stamina.exhausted.connect(_refresh_alpha)
	stamina.recovered.connect(_refresh_alpha)
	if health:
		health.died.connect(hide)
	_on_stamina_changed(stamina.current_stamina, stamina.max_stamina)
	_refresh_alpha()


func _on_stamina_changed(current: float, maximum: float) -> void:
	set_instance_shader_parameter(&"ratio", current / maxf(maximum, 1.0))
	visible = current < maximum and not (health and health.is_dead)


func _refresh_alpha() -> void:
	transparency = 1.0 - exhausted_alpha if stamina.is_exhausted else 0.0
