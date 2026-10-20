class_name DamageNumbers
extends Node3D
## Pops a floating number above its parent whenever `health` takes damage,
## and a "+N" in `heal_color` when it heals.
## Place it at the height the numbers should appear (e.g. above the head).
## Numbers are top-level, so they stay where they spawned while they float.

@export var health: HealthComponent
@export var color: Color = Color(1.0, 0.95, 0.85)
@export var heal_color: Color = Color(0.45, 1.0, 0.45)
@export var font_size: int = 48
## World units per font pixel; 0.012 is ~0.6 m tall text.
@export var pixel_size: float = 0.012
@export var rise: float = 0.9
@export var lifetime: float = 0.8
## Random horizontal spread so consecutive numbers don't stack.
@export var jitter: float = 0.3


func _ready() -> void:
	health.damaged.connect(_on_damaged)
	health.healed.connect(func(amount: int) -> void: spawn("+%d" % amount).modulate = heal_color)


func _on_damaged(amount: int, _source: Node) -> void:
	spawn(str(amount))


## Spawns a floating label; returns it (used by tests).
func spawn(text: String) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.outline_size = 12
	label.modulate = color
	label.outline_modulate = Color(0, 0, 0, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.render_priority = 10
	label.outline_render_priority = 9
	label.top_level = true
	add_child(label)
	var start := global_position + Vector3(randf_range(-jitter, jitter), 0.0, randf_range(-jitter, jitter))
	label.global_position = start

	var tween := label.create_tween().set_parallel()
	tween.tween_property(label, "global_position", start + Vector3.UP * rise, lifetime) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, lifetime * 0.5).set_delay(lifetime * 0.5)
	tween.tween_property(label, "outline_modulate:a", 0.0, lifetime * 0.5).set_delay(lifetime * 0.5)
	tween.chain().tween_callback(label.queue_free)
	return label
