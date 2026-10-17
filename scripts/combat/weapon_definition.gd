class_name WeaponDefinition
extends Resource
## One weapon: its model, hitbox and trail, the attacks of whoever wields it
## and the animation set to use meanwhile. WeaponComponent equips it; one
## .tres per weapon in resources/weapons/.
##
## Placement values are in the space of the hand's bone attachment
## (`RightHand`, bone hand_r). Player and enemy attacks are separate so one
## weapon can serve both.

@export var display_name: String = "Weapon"

@export_group("Model")
## Instanced under the hand attachment.
@export var model: PackedScene
@export var model_transform: Transform3D = Transform3D.IDENTITY

@export_group("Hitbox")
## Box covering the striking part (blade, club head), and its placement.
@export var hitbox_size: Vector3 = Vector3(0.25, 0.3, 0.9)
@export var hitbox_transform: Transform3D = Transform3D(Basis.IDENTITY, Vector3(-0.03, 0.085, 0.52))
## Blade ends for the weapon trail.
@export var trail_base: Vector3 = Vector3(0, 0.085, 0.15)
@export var trail_tip: Vector3 = Vector3(0, 0.085, 0.95)

@export_group("Player Attacks")
## Light attack chain (see PlayerController).
@export var light_combo: Array[AttackProfile] = []
@export var heavy_attack: AttackProfile
## Light / heavy attack started while sprinting. Null = the normal attack.
@export var dash_attack: AttackProfile
@export var dash_heavy_attack: AttackProfile
## Combo step a light attack continues with after a heavy or dash attack.
@export var light_after_heavy: int = 0

@export_group("Enemy Attacks")
## Basic swing, used within `enemy_attack_range` (centre to centre).
@export var enemy_attack: AttackProfile
@export var enemy_attack_range: float = 1.7
## Gap closer used between the dash ranges. Null = none.
@export var enemy_dash_attack: AttackProfile
@export var enemy_dash_min_range: float = 3.0
@export var enemy_dash_max_range: float = 5.0

@export_group("Overrides")
## CharacterAnimator properties while wielded (idle_animation, run_animation,
## idle_variants...). Restored when another weapon is equipped.
@export var animator_overrides: Dictionary = {}
## HitReactionComponent properties while wielded (hit animations...).
@export var reaction_overrides: Dictionary = {}
## Properties of the character itself while wielded (e.g. the player's
## move_speed for a heavy weapon). Missing properties are ignored.
@export var character_overrides: Dictionary = {}
