class_name Interactor
extends Node
## Lets its owner interact with things in the world (chests now, gear
## pickups later). Every tick it focuses the nearest node of group GROUP
## within `reach` (horizontal, from `body`) whose can_interact() is true;
## try_interact() then plays the target's interact_animation() over
## `duration` seconds (the owner stays committed while is_busy()) and calls
## its interact(body).
##
## An interactable is any Node3D in GROUP with:
##   can_interact() -> bool, interact_prompt() -> String, interact(by),
##   and optionally interact_animation() -> StringName.

## The focused target changed (null = nothing in reach). UI shows a prompt.
signal focus_changed(target: Node3D)
signal interacted(target: Node3D)

const GROUP := &"interactables"

@export var body: Node3D
@export var animator: CharacterAnimator
## Metres (horizontal) within which a target can be used.
@export var reach: float = 1.8
## Seconds an interaction keeps the owner busy (its animation is fitted).
@export var duration: float = 1.1
## Interactions only happen while this is true (the owner turns it off
## while dead).
var enabled: bool = true

var focus: Node3D
var _busy_left: float = 0.0
var _action: StringName = &""


func is_busy() -> bool:
	return _busy_left > 0.0


## Uses the focused target. Returns false if there is none or already busy.
func try_interact() -> bool:
	if not enabled or is_busy() or focus == null or not is_instance_valid(focus) \
			or not focus.can_interact():
		return false
	var target := focus
	_busy_left = duration
	_action = target.interact_animation() if target.has_method(&"interact_animation") else &""
	if animator and _action != &"" and animator.animation_player.has_animation(_action):
		var length := animator.animation_player.get_animation(_action).length
		animator.play_action(_action, length / maxf(duration, 0.01))
	target.interact(body)
	interacted.emit(target)
	return true


## Ends the current interaction early (stagger, death); the target keeps
## whatever already happened.
func cancel() -> void:
	if not is_busy():
		return
	_busy_left = 0.0
	if animator and _action != &"" and animator.current_action() == _action:
		animator.stop_action()


func _physics_process(delta: float) -> void:
	if _busy_left > 0.0:
		_busy_left -= delta
		if _busy_left <= 0.0:
			cancel()
	_set_focus(_nearest() if enabled else null)


func _nearest() -> Node3D:
	if body == null:
		return null
	var best: Node3D = null
	var best_distance := reach
	for node in get_tree().get_nodes_in_group(GROUP):
		var target := node as Node3D
		if target == null or not target.can_interact():
			continue
		var offset := target.global_position - body.global_position
		var distance := Vector2(offset.x, offset.z).length()
		if distance <= best_distance:
			best = target
			best_distance = distance
	return best


func _set_focus(target: Node3D) -> void:
	if target != focus:
		focus = target
		focus_changed.emit(target)
