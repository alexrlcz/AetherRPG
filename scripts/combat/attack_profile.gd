class_name AttackProfile
extends Resource
## Data for one melee attack: timing, the animation segment it plays and how
## hard it hits. MeleeAttackComponent runs it; the HitEvent it produces carries
## it to the victim (reaction) and the attacker (impact feedback).
##
## Animation markers are seconds into `animation`. Each phase plays its own
## segment at its own speed so the visible swing matches the hit window:
##   wind-up   anim_start        -> anim_strike_start  (over `windup` s)
##   strike    anim_strike_start -> anim_strike_end    (over `strike_duration` s, hitbox live)
##   recovery  anim_strike_end   -> anim_recovery_end  (over `recovery` s)

enum Weight { LIGHT, HEAVY }

@export var display_name: String = "Attack"
@export var weight: Weight = Weight.LIGHT
@export var damage: int = 10

@export_group("Timing")
@export var windup: float = 0.3
## Last part of the wind-up spent holding the raised pose (anticipation beat).
@export var windup_hold: float = 0.0
@export var strike_duration: float = 0.12
@export var recovery: float = 0.3

@export_group("Animation")
@export var animation: StringName = &""
@export var anim_start: float = 0.0
@export var anim_strike_start: float = 0.3
## <= anim_strike_start: one playback speed for the whole attack (legacy).
@export var anim_strike_end: float = 0.0
## 0 = the animation's full length.
@export var anim_recovery_end: float = 0.0

@export_group("Commitment")
## Seconds into recovery after which a buffered attack may chain out of it.
@export var chain_delay: float = 0.1
## Seconds into recovery after which movement input ends it early. < 0 = never.
@export var move_cancel: float = 0.25

@export_group("Movement")
## Forward step taken from the end of the wind-up through the strike.
@export var lunge_distance: float = 0.0
## Part of the wind-up (s) the lunge starts before the strike.
@export var lunge_lead: float = 0.08

@export_group("Impact")
## Real-time freeze on a confirmed hit (s).
@export var hitstop: float = 0.05
## 0..1 camera kick strength.
@export var camera_shake: float = 0.2
## Initial knockback speed (m/s) given to the victim.
@export var knockback: float = 3.0
## Victim hitstun (s) when the hit staggers.
@export var hitstun: float = 0.3
## Poise damage: armoured victims stagger once it adds up past their poise.
@export var stagger: float = 10.0
## Multiplier on the victim's ragdoll fling when this hit is lethal.
@export var ragdoll_force: float = 1.0
## Visual size of the impact effect.
@export var impact_scale: float = 1.0
@export var impact_color: Color = Color(1.0, 0.85, 0.55)

@export_group("Trail")
@export var trail_color: Color = Color(0.85, 0.9, 1.0, 0.55)


func is_heavy() -> bool:
	return weight == Weight.HEAVY


func uses_segments() -> bool:
	return anim_strike_end > anim_strike_start
