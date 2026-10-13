extends Node3D
## Top-level game flow for the prototype scene: restart after the player dies.

@export var player: PlayerController
## Seconds after death before "restart" is accepted (avoids accidental skips).
@export var restart_delay: float = 1.0

var _restart_allowed_at: float = INF


func _ready() -> void:
	player.health.died.connect(_on_player_died)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart") and can_restart():
		restart()


func can_restart() -> bool:
	return player.is_dead and _now() >= _restart_allowed_at


func restart() -> void:
	get_tree().reload_current_scene()


func _on_player_died() -> void:
	_restart_allowed_at = _now() + restart_delay


static func _now() -> float:
	return Time.get_ticks_msec() / 1000.0
