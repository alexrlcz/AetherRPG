class_name MutantBoss
extends Node
## The mutant boss's shows, on top of the usual EnemyController:
## - Intro: the first time it notices the player (the player steps into its
##   arena: its detection reaches the arena's doors), it plays one of
##   `intro_animations` at random (roar / flex), standing still facing the
##   player (EnemyController.hold()), then fights.
## - Victory: when the player dies from one of its hits, it stops and dances
##   (`victory_animation`, a looping clip) for as long as the scene lasts.

signal intro_started(animation: StringName)
signal victory_started

@export var controller: EnemyController
@export var animator: CharacterAnimator
@export var intro_animations: Array[StringName] = [&"Mutant/Roar", &"Mutant/Flex"]
@export var victory_animation: StringName = &"Mutant/Dance"

var intro_played: bool = false
var dancing: bool = false


func _ready() -> void:
	controller.state_changed.connect(_on_state_changed)
	_bind_player.call_deferred()


func _bind_player() -> void:
	var player := get_tree().get_first_node_in_group(&"player")
	var health := player.get(&"health") as HealthComponent if player else null
	if health:
		health.died.connect(_on_player_died.bind(player))


func _on_state_changed(state: EnemyController.State) -> void:
	if intro_played or state != EnemyController.State.CHASE:
		return
	intro_played = true
	var choice: StringName = intro_animations.pick_random()
	if not animator.animation_player.has_animation(choice):
		return
	controller.hold(animator.animation_player.get_animation(choice).length)
	animator.play_action(choice)
	intro_started.emit(choice)


func _on_player_died(player: Node) -> void:
	if controller.state == EnemyController.State.DEAD:
		return
	var hurtbox := player.get_node_or_null(^"Hurtbox") as HurtboxComponent
	if hurtbox == null or hurtbox.last_hit == null or hurtbox.last_hit.source != controller:
		return
	dancing = true
	controller.hold(INF)
	animator.play_action(victory_animation)
	victory_started.emit()
