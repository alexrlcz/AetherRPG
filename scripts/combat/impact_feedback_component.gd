class_name ImpactFeedbackComponent
extends Node
## Attacker-side hit confirmation: hitstop, camera kick, impact effect and hit
## sound, scaled by the hit's AttackProfile (heavier and lethal hits hit
## harder). Driven only by MeleeAttackComponent.hit_confirmed, i.e. a hit the
## victim actually took, so a miss gets nothing but the swing whoosh.
## Several targets hit on the same tick share one hitstop, kick and sound.

@export var melee: MeleeAttackComponent

@export_group("Assets")
## Root must have setup(event: HitEvent, strength: float). Null = placeholder.
@export var effect_scene: PackedScene
## Null = synthesised placeholder (PlaceholderSfx).
@export var hit_sound: AudioStream
@export var heavy_hit_sound: AudioStream
@export var swing_sound: AudioStream
@export var heavy_swing_sound: AudioStream
@export var volume_db: float = -3.0
@export var swing_volume_db: float = -12.0

@export_group("Strength")
@export var hitstop_scale: float = 1.0
@export var shake_scale: float = 1.0
## Extra hitstop (s) and camera kick on a killing blow.
@export var lethal_hitstop_bonus: float = 0.05
@export var lethal_shake_bonus: float = 0.25

## Confirmed hits handled (tests and debugging).
var hits_handled: int = 0
var _last_frame: int = -1


func _ready() -> void:
	melee.hit_confirmed.connect(_on_hit_confirmed)
	melee.struck.connect(_on_struck)


func _on_struck(profile: AttackProfile) -> void:
	var heavy := profile != null and profile.is_heavy()
	var stream := heavy_swing_sound if heavy else swing_sound
	if stream == null:
		stream = PlaceholderSfx.whoosh(heavy)
	var at := owner as Node3D
	_play(stream, at.global_position + Vector3.UP if at else Vector3.ZERO, swing_volume_db)


func _on_hit_confirmed(event: HitEvent) -> void:
	hits_handled += 1
	var profile := event.profile
	var strength := profile.impact_scale if profile else 0.7
	if event.lethal:
		strength *= 1.25
	_spawn_effect(event, strength)
	var frame := Engine.get_physics_frames()
	if frame == _last_frame:
		return
	_last_frame = frame
	var stop := (profile.hitstop if profile else 0.03) * hitstop_scale
	var shake := (profile.camera_shake if profile else 0.1) * shake_scale
	if event.lethal:
		stop += lethal_hitstop_bonus
		shake += lethal_shake_bonus
	Hitstop.request_for(self, stop)
	var rig := get_tree().get_first_node_in_group(IsoCameraRig.GROUP) as IsoCameraRig
	if rig:
		rig.add_impulse(event.direction, shake)
	var heavy := event.is_heavy() or event.lethal
	var stream := heavy_hit_sound if heavy else hit_sound
	if stream == null:
		stream = PlaceholderSfx.hit(heavy)
	_play(stream, event.point, volume_db)


func _spawn_effect(event: HitEvent, strength: float) -> void:
	var effect: Node3D = effect_scene.instantiate() if effect_scene else ImpactEffect.new()
	_world_root().add_child(effect)
	effect.global_position = event.point
	effect.setup(event, strength)


func _play(stream: AudioStream, at: Vector3, db: float) -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = db
	player.pitch_scale = randf_range(0.94, 1.06)
	player.unit_size = 20.0
	_world_root().add_child(player)
	player.global_position = at
	player.finished.connect(player.queue_free)
	player.play()


func _world_root() -> Node:
	var scene := get_tree().current_scene
	return scene if scene else get_tree().root
