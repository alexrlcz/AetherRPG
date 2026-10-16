class_name Hitstop
extends Node
## Brief real-time freeze when a hit connects. The only code that changes
## Engine.time_scale, so stops cannot fight each other:
## - overlapping requests extend to the longest one, never add up, and one
##   stop never lasts longer than `max_duration`;
## - a request right after a stop ended is shortened (`cooldown`), so rapid
##   multi-hits don't turn into a stutter.
## Time never fully stops (`frozen_time_scale` > 0): zero-length physics steps
## give ragdoll bones invalid velocities. Input keeps arriving while frozen;
## everything driven by delta simply barely advances.
## Place one in the main scene; attackers find it through its group.

const GROUP := &"hitstop"

@export_range(0.001, 1.0) var frozen_time_scale: float = 0.03
@export var max_duration: float = 0.18
## Requests within this long (s) after a stop ended are halved.
@export var cooldown: float = 0.08

var _active: bool = false
var _start_usec: int = 0
var _end_usec: int = 0
var _last_end_usec: int = -1000000000


static func request_for(node: Node, duration: float) -> void:
	if node == null or not node.is_inside_tree():
		return
	var stop := node.get_tree().get_first_node_in_group(GROUP) as Hitstop
	if stop:
		stop.request(duration)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(GROUP)


func _exit_tree() -> void:
	if _active:
		_release()


func is_active() -> bool:
	return _active


func request(duration: float) -> void:
	if duration <= 0.0:
		return
	var now := Time.get_ticks_usec()
	if not _active and now - _last_end_usec < int(cooldown * 1e6):
		duration *= 0.5
	if not _active:
		_active = true
		_start_usec = now
		_end_usec = now
		Engine.time_scale = frozen_time_scale
	var limit := _start_usec + int(max_duration * 1e6)
	_end_usec = mini(maxi(_end_usec, now + int(duration * 1e6)), limit)


func _process(_delta: float) -> void:
	if _active and Time.get_ticks_usec() >= _end_usec:
		_release()


func _release() -> void:
	_active = false
	_last_end_usec = Time.get_ticks_usec()
	Engine.time_scale = 1.0
