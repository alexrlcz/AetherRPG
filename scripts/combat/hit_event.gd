class_name HitEvent
extends RefCounted
## One confirmed contact between a HitboxComponent and a HurtboxComponent.
## Built by the hitbox, filled in by the hurtbox (applied damage, lethal) and
## then broadcast: the victim reacts through `HurtboxComponent.hit_received`,
## the attacker's feedback through `HitboxComponent.hit_landed`.

## Attacker (the hitbox's `source`).
var source: Node
var hitbox: HitboxComponent
var hurtbox: HurtboxComponent
## Null for plain damage sources (hazards): victims only flinch.
var profile: AttackProfile
var amount: int = 0
## Damage actually removed by the victim's HealthComponent.
var applied: int = 0
var lethal: bool = false
## World-space contact point on the weapon.
var point: Vector3
## Horizontal unit vector from the attacker toward the victim (knockback).
var direction: Vector3
## Unit vector of the weapon's motion at contact (effects); may be ZERO.
var swing_direction: Vector3


func is_heavy() -> bool:
	return profile != null and profile.is_heavy()
