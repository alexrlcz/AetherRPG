# Architecture

## World and camera

- The world is true 3D (Godot 4.7, Forward+ renderer, Jolt physics).
- The camera is a fixed orthographic isometric view (`IsoCameraRig`): yaw 45°,
  pitch 35.264° (true isometric). The player cannot rotate it. It smoothly
  follows its target; the mouse wheel zooms by changing the orthographic `size`.
- Gameplay code never depends on the camera except to convert input
  (screen-relative WASD, mouse aim). Simulation stays in world space, which
  keeps a future server-authoritative multiplayer model possible.

## Controls

| Action         | Default            | Behaviour |
|----------------|--------------------|-----------|
| `move_*`       | WASD / arrow keys  | Screen-relative movement; character faces movement direction. |
| `aim` (hold)   | Right mouse        | Character keeps facing the cursor; WASD still moves screen-relative (strafe / walk backwards). |
| `lock_on`      | Middle mouse       | Lock onto the nearest visible enemy within 15 m, or release the lock. While locked the character always faces the target and strafes like `aim`; the lock wins over `aim`. |
| `cycle_target` | Tab                | Next lock target, nearest to farthest, wrapping (locks the nearest if unlocked). |
| `attack`       | Left mouse (hold to repeat) | Light combo: Rising Slash -> Sweep -> Finisher -> Rising Slash... (see Combat feel). |
| `heavy_attack` | E                  | Cleave: slow, committed overhead blow that breaks enemy poise. |
| `dodge`        | Space              | Dodge roll toward the WASD direction (toward the cursor if none held), with i-frames (see Dodge roll). |
| `zoom_in/out`  | Mouse wheel        | Orthographic zoom. |
| `restart`      | R                  | After death (1 s delay): reload the level. |
| `debug_menu`   | F1                 | Toggle the debug panel (debug builds only). |
| `debug_spawn_enemy` | F2          | Spawn an enemy at a random walkable point (debug builds only). |

Attack presses are handled as input events (`_unhandled_input`), so clicks on
UI buttons never trigger a swing. A press is buffered for
`input_buffer_time` (0.3 s); a press made during recovery waits for the
chain point however long it is. Holding `attack` repeats the first combo step
after each full recovery; only presses chain combos.

Attack direction: locked on -> toward the target; holding `aim` -> toward
the cursor (fast turn during the wind-up); otherwise exactly where the model
already faces, and the cursor is ignored.

Lock-on (`LockOnComponent`, node `LockOn` on the player) finds candidates in
the "enemies" group (alive, within `lock_range`, line of sight on layer 1).
The lock breaks past `break_range` (20 m) or after `lose_sight_time` (1 s)
out of sight; when the target dies it jumps to the next-nearest enemy or
releases; player death releases it. The marker (ground ring + pointer above
the health bar) is built in code and lives in the "vfx" group. The player
exposes `is_strafing` (aiming or locked), which the animator uses to pick
strafe / backward cycles. Tab is consumed by the player so it doesn't move UI
focus, but if a UI control already has focus it may take Tab first.

## Physics layers

| # | Name           | Used by |
|---|----------------|---------|
| 1 | world          | Ground, walls, obstacles |
| 2 | player         | Player body |
| 3 | enemy          | Enemy bodies |
| 4 | player_hurtbox | Areas that receive damage on the player |
| 5 | enemy_hurtbox  | Areas that receive damage on enemies |
| 6 | interactable   | NPCs, loot, objects |
| 7 | ragdoll        | Ragdoll bones; collide with the world only (corpses never block characters) |

## Combat components

Damage flows through small reusable nodes, never through direct calls between
entities:

```
HitboxComponent (Area3D, mask = target hurtbox layer; optional sweep)
   └─ contact ─► HitEvent ─► HurtboxComponent.receive_event()
                                ├─ HealthComponent.take_damage() ─► damaged / died / ...
                                └─ hit_received(event) ─► HitReactionComponent (victim)
   └─ hit_landed(event) ─► MeleeAttackComponent.hit_confirmed ─► ImpactFeedbackComponent (attacker)
```

`HitEvent` (`scripts/combat/hit_event.gd`) is the one description of a
confirmed contact: source, hitbox, hurtbox, `AttackProfile`, damage applied,
lethal, contact `point`, knockback `direction` (attacker -> victim) and
`swing_direction` (weapon motion at contact). Everything that reacts to a hit
reads it; nothing reacts to an attack merely starting.

- `HealthComponent` (Node): `max_health`, `current_health`, `take_damage()`,
  `heal()`, `reset()`. Valid from construction, independent of ready order.
- `HurtboxComponent`: `receive_event(event)` applies damage, fills in
  `applied`/`lethal`, then emits `hurt(amount, source)` and
  `hit_received(event)` (only if damage was taken). `last_hit` is set before
  damage so `died` listeners (ragdoll) can read the killing blow.
  `receive_hit(amount, source)` remains for plain damage. While `invulnerable`
  (dodge i-frames) every hit is ignored and `evaded(event)` is emitted
  instead. The hitbox still counts that hurtbox as hit for the activation, so
  a dodged swing cannot land later in the same strike.
- `HitboxComponent`: while `active`, hits each hurtbox once per activation, or
  every `rehit_interval` seconds if > 0 (hazards, DoT zones). `source`
  defaults to the scene owner; `profile` (set per attack) goes on the event.
  With `sweep` on (player blade) each tick tests interpolated samples of its
  shapes between the previous and current pose (`sweep_spacing` 0.12 m between
  samples), so rotating arcs are followed and nothing is skipped at any tick
  rate. `close_after_current_pose()` ends the window only after the final
  tick's pose was tested (bone poses apply at the end of a tick, so a hitbox
  always sees the previous tick's pose).
- Teams are decided purely by physics layers: player attacks mask
  `enemy_hurtbox`, enemy attacks and hazards mask `player_hurtbox`.
- UI (`HUD`) only listens to `HealthComponent` signals.
- `MeleeAttackComponent` runs one `AttackProfile` at a time: wind-up
  (optional ground telegraph grows; optional `windup_hold` beat) -> strike
  (hitbox live) -> recovery. Each phase plays its own animation segment at its
  own speed (markers `anim_start`, `anim_strike_start`, `anim_strike_end`,
  `anim_recovery_end`, in seconds into the clip), so the visible swing and the
  hit window agree whatever the timings. Without a profile, its exported
  fields describe the attack (the enemy, from `EnemyStats`, one playback
  speed). `chain(profile)` starts the next attack out of recovery after
  `chain_delay`, continuing the same clip from its current pose;
  `end_recovery()` after `move_cancel`; `lunge_speed()` for the owner's
  forward step. Signals: `started`, `struck`, `strike_ended`, `finished`,
  `hit_confirmed(event)`.
- `AttackProfile` (`scripts/combat/attack_profile.gd`, `.tres` in
  `resources/combat/`): damage, weight (LIGHT/HEAVY), timings, animation
  markers, chain/move-cancel windows, lunge, and impact data (hitstop, camera
  shake, knockback, hitstun, poise damage `stagger`, ragdoll force, effect size
  and colour, trail colour).
- Player `AttackHitbox` (masks `enemy_hurtbox`, `sweep` on) is a
  0.25 x 0.3 x 0.9 m box along the blade under the `RightHand` bone
  attachment: only the swinging blade hits.
- `CharacterAnimator` runs its AnimationPlayer on **physics ticks**
  (`callback_mode_process = PHYSICS`), in lockstep with the attack phase
  timers and the blade sweep. On render frames they drift apart at low frame
  rates (seen headless at ~12 fps: the strike window passed while the sword
  was still raised). Bodies already move per tick (no physics interpolation).

## Combat feel

Player attacks. The light combo uses UAL2's `Sword_Regular_A/B/C`: each swing
ends in the pose the next one starts from (measured: < 0.07 m mean bone
offset), and A and B have separate return-to-guard clips (`_Rec`) that start
exactly on their swing's last frame and end in the idle pose. A chained swing
starts straight from the previous swing's end; the `_Rec` clip only plays when
the combo stops (`AttackProfile.recovery_animation`, queued with
`CharacterAnimator.queue_action`). Strike windows are where the sword tip moves
fastest (sampled at 30 fps). The heavy attack still uses UAL1's `Sword_Attack`
overhead cut.

| Attack | Input | Clip | Wind-up | Strike | Recovery | Damage | Notes |
|---|---|---|---|---|---|---|---|
| Rising Slash | light 1 | Sword_Regular_A | 0.26 s (anim 0-0.20) | 0.11 s (0.20-0.31), rising diagonal right -> left | 0.85 s (rest of A + A_Rec) | 16 | chain after 0.06 s, move-cancel 0.28 s, lunge 0.3 m |
| Sweep | light 2 | Sword_Regular_B | 0.20 s (0-0.20) | 0.11 s (0.20-0.31), horizontal left -> right | 0.95 s (rest of B + B_Rec) | 18 | chain after 0.08 s, lunge 0.35 m |
| Finisher | light 3 | Sword_Regular_C | 0.50 s (0-0.57) | 0.14 s (0.57-0.75), big diagonal cut | 1.0 s (0.75-2.0, back to guard) | 30 | chain after 0.35 s, knockback 5.5, stagger 22, lunge 0.6 m |
| Cleave | heavy | Sword_Attack | 0.62 s incl. 0.14 s hold at the top | 0.10 s (0.37-0.50) | 0.55 s (0.50-0.77) | 40 | breaks poise, knockback 7.5, hitstun 0.6 s, hitstop 0.11 s, lunge 0.9 m |

- Combo order lives on the player (`light_combo`, `heavy_attack`,
  `light_after_heavy` = 0): profiles never reference each other (cyclic
  resources don't load reliably). Light -> light -> light, light -> heavy and
  heavy -> Rising Slash all chain; after the Finisher the combo wraps to A.
- The Finisher's wind-up includes a fast low pass of the sword in front of
  the player (C at 0.05-0.20 s) that does not deal damage; only the big
  diagonal cut does. `player_slash.tres` / `player_rising_cut.tres` (the old
  `Sword_Attack` combo) are no longer used.
- Commitment: attacking stops the player dead; it turns toward the cursor at
  `attack_turn_speed` during the wind-up only, then facing locks. The only
  movement is the lunge (stops once the attack connects), and movement input
  ends recovery after `move_cancel`.
- `HitReactionComponent` (`scripts/combat/`), on the player and enemies:
  - stagger: hitstun (`is_reacting()`), decaying `knockback_velocity` the owner
    applies through `move_and_slide` (walls stop it), `Hit_Chest` (light) /
    `Hit_Head` (heavy) played to fit the hitstun, and a spring lean of the
    `Visual` root along the hit direction (7° light, 13° heavy). The hit
    animations only recoil backwards; the lean gives the direction.
  - poise: while `armored` (enemy and player during wind-up and strike),
    hits only flinch (half lean, 20% knockback) until their `stagger` adds up
    past `poise` (enemy 30 from `EnemyStats.poise`, player 20); then they
    stagger and cancel the attack. Recovery is never armoured. Poise damage
    resets 2 s after the last hit. A Rising Slash (11) needs 3 hits to break an
    attacking enemy; Cleave (40) breaks it at once.
  - hits without a profile (hazards) only flinch; lethal hits are left to the
    ragdoll, which flings along the killing hit scaled by `ragdoll_force`.
- `Hitstop` (`scripts/combat/hitstop.gd`, node in `main.tscn`, group
  `hitstop`): the only code that sets `Engine.time_scale`, to 0.03 (never 0,
  see Ragdoll) for the hit's real-time duration. Overlapping requests extend
  to the longest, capped at `max_duration` 0.18 s per stop; a request within
  `cooldown` 0.08 s of the last stop is halved.
- `ImpactFeedbackComponent` (`scripts/combat/`): attacker-side, driven only by
  `hit_confirmed`. Spawns an impact effect at the contact point, requests
  hitstop, kicks the camera (`IsoCameraRig.add_impulse`, group `camera_rig`:
  directional punch + shake on `Camera3D.h_offset/v_offset`, decaying in real
  time) and plays the hit sound; killing blows add +0.05 s hitstop and +0.25
  shake. Several targets on one tick share one hitstop/kick/sound. Every
  strike plays a swing whoosh, so a miss sounds different from a hit. The
  enemy has one too (hitstop x0.8) for when the player gets hit.
- Placeholders to replace: `ImpactEffect` (`scripts/vfx/impact_effect.gd`:
  primitive sparks, flash and slash streak; set
  `ImpactFeedbackComponent.effect_scene` to an authored scene with the same
  `setup(event, strength)`), `PlaceholderSfx` (`scripts/audio/`, synthesised
  hit thump and whoosh; assign the `*_sound` AudioStream exports).
- `WeaponTrail` (`scripts/vfx/`, under the player's `RightHand`): additive
  ribbon between the blade's base and tip during each strike, in the
  profile's `trail_color`, interpolating the blade transform between frames
  so it draws arcs. Effect meshes are in group `vfx`, which `HitFlash` and
  `OcclusionSilhouette` skip.

## Combat feedback

- `DamageNumbers` (Node3D placed above the head, `scripts/ui/`): on
  `HealthComponent.damaged` spawns a top-level billboard `Label3D` that rises
  and fades. Colour per character (player red, enemies white).
- `HitFlashComponent`: on damage sets a white unshaded `material_overlay` on
  the listed meshes and fades it out (`duration` 0.15 s); surface material
  overrides (enemy recolour) are untouched. Clears the overlay when freed
  mid-flash.
- HUD shows "Defeated" + "Press R to try again"; `scripts/main/main.gd` (on
  the Main node) reloads the scene on `restart` once the player has been dead
  for `restart_delay` seconds.

## Occlusion silhouettes

- `OcclusionSilhouette` (`scripts/characters/`, node `OcclusionSilhouette`)
  gives every mesh under `Visual` (body and weapon) a material copy with
  `BaseMaterial3D` **X-Ray stencil mode**: the normal pass writes stencil 1
  where the character is visible; an extra unshaded, no-depth-test pass draws
  `color` only where stencil != 1, i.e. where something hides the character.
  No self x-ray, and characters don't x-ray through each other.
- Player blue `(0.35, 0.65, 1, 0.55)`, enemies red `(1, 0.3, 0.25, 0.5)`;
  the alpha sets the strength. Turned off on death so corpses don't glow.
- Because it copies materials at `_ready`, any later material change must go
  through `get_materials()` (or re-apply the stencil mode).

## Spawning and debug tools

- `EnemySpawner` (`scripts/world/`): `spawn_random()` picks
  `NavigationServer3D.map_get_random_point` points, rejects ones above
  `max_spawn_height` (navmesh islands on rocks/pillars) or closer than
  `min_distance` to the player, and sets the enemy's transform *before*
  `add_child` (enemies record home/facing in `_ready`).
- `DebugMenu` (`scenes/debug/debug_menu.tscn`): F1 panel with Spawn enemy,
  Heal player, Kill all enemies and an alive-enemy count; F2 spawns directly.
  "Player appearance" section: body, skin texture, skin tint, hairstyle, hair
  colour, eyebrows, beard and Randomize. It edits a duplicate of the player's
  CharacterAppearance and calls `apply()`; changes are not saved.
  Frees itself in non-debug builds (`OS.is_debug_build()`).

## Character visuals and animation

- Models: Quaternius "Universal Base Characters" + "Universal Animation
  Library" (CC0, licences in `assets/characters/universal/`). Male and female
  bodies, hairstyles, beard, eyebrows and the animations (UAL1: 43, UAL2: 43,
  verified to share the same 65 bones and rest pose) all share one
  65-bone UE-mannequin-style skeleton (`pelvis`, `spine_01..03`, `hand_r`, ...),
  ~1.82 m tall, metre units, facing +Z.
- `UAL1_Standard.glb` and `UAL2_Standard.glb` (the no-root-motion versions;
  the `_RM` files were not imported) are each imported as an **AnimationLibrary**
  with the same settings. The rig's AnimationPlayer has UAL1 as the default
  library (`Idle`, `Sword_Attack`) and UAL2 as `UAL2` (`UAL2/Sword_Regular_A`).
  (`importer="animation_library"`). The shared post-import script
  `tools/import/ual_post_import.gd` removes position tracks except `root` and
  `pelvis`, and all scale tracks: the animations were authored on a mannequin
  with different bone lengths, so only rotations are applied and each body
  keeps its own proportions. `remove_immutable_tracks` is off so constant
  rotation tracks are kept. Godot strips the `_Loop` suffix on import
  (`Idle_Loop` -> `Idle`, `Jog_Fwd_Loop` -> `Jog_Fwd`).
- Mixamo locomotion (jog forward diagonals, strafe left/right, jog backward,
  jog backward diagonals) is retargeted onto this skeleton by
  `tools/build_mixamo_library.gd` into
  `assets/characters/mixamo/mixamo_locomotion.res` (the rig's `MX` library).
  The source FBX files ("Without Skin", 65-bone `mixamorig_` skeleton) are
  read at build time from outside the project (`D:/AetherRPG/MIXAMO
  Animations`, or a path passed after `--`), so the raw Mixamo files are
  not in the repo. Both skeletons rest in a T-pose facing +Z, so each bone
  gets the source's world-space rotation delta from rest. The hips keep only
  their bob and sway, scaled to the mannequin hip height (×0.88), with the
  clip's travel removed. The travel speed is stored as `reference_speed`
  metadata. Clips whose source file is missing from the source directory are
  kept from the existing library, so a single new download can be added on
  its own. "With Skin" downloads work too (the builder uses the take with the
  most tracks, skipping the empty `Take 001`). Rebuild the library after
  changing the sources (the rig references it by path):
  `godot --headless --path . -s res://tools/build_mixamo_library.gd -- "<source dir>"`.
- `scenes/characters/humanoid_rig.tscn` = the male body glTF + ragdoll +
  `RightHand` attachment (bone `hand_r`) + `AnimationPlayer` with the library.
  It is **generated** by `tools/build_humanoid_rig.gd` (bone table at the top);
  re-run it instead of hand-editing:
  `godot --headless --path . -s res://tools/build_humanoid_rig.gd`.
- Player and enemy instance the rig at `Visual/Model`, rotated 180° (model
  faces +Z, gameplay forward is -Z). Weapons are children of `RightHand`; the
  blade (+Y of the weapon FBXs) runs along hand +Z (pinky -> index knuckles),
  scale 0.25 (sword) / 0.3 (club) because the weapon FBXs are in their
  original units.
- Appearance: `CharacterAppearance` resource (`scripts/characters/`) = body
  (male/female), skin texture (light/dark) + tint, hairstyle, hair colour,
  beard, eyebrows. `AppearanceComponent` (node `Appearance`) builds it on the
  rig at `_ready` and on every `apply()`: it removes the rig's preview meshes,
  moves the skinned meshes of each part glTF onto the rig's `Skeleton3D`
  (skins bind by bone name), gives each part its own tinted material copy
  (hair textures are greyscale), copies the chosen body's bone rests onto the
  skeleton and shifts the skeleton by the body/animation pelvis-height
  difference so the feet stay on the ground. It emits `applied`, which is
  connected to `OcclusionSilhouette.refresh()`. `HitFlash` uses `root` (all
  meshes under `Visual`, found at flash time) for the same reason.
  Looks: `resources/characters/player_appearance.tres`,
  `resources/enemies/ashbound_knight_appearance.tres`.
- The ragdoll's capsules are sized for the male rests; on the female body they
  are slightly oversized (narrower shoulders) but the joints still line up.
- `CharacterAnimator` (`scripts/characters/`, node `Animator`) is shared by the
  player and enemies. It observes the body's velocity and its HealthComponent:
  idle (`Sword_Idle`) / walk (`Walk`, below `walk_to_run_speed` 2.6 m/s, with
  hysteresis) / run (`Jog_Fwd`, rate = speed / 5.36 m/s), cycle rate clamped to
  0.6–1.6x, 0.25 s locomotion crossfades. While the body's `is_strafing` is
  true (aiming or locked on) the cycle is picked from the movement direction
  relative to the facing: forward < 22.5° (walk/run), forward diagonal
  22.5–67.5° (`MX/Jog_Fwd_L/R`), strafe 67.5–115°
  (`MX/Strafe_L/R`), backward diagonal 115–160° (`MX/Jog_Bwd_L/R`), backward
  (`MX/Jog_Bwd`), with 10° hysteresis at the boundaries. Their rate uses each
  clip's `reference_speed` metadata. If a directional clip is missing, the
  forward cycle plays reversed instead (old behaviour). Gameplay calls
  `play_action(anim, speed)` for one-shots such as attacks (restarting it if
  it is already playing); `MeleeAttackComponent` calls `stop_action()` when
  recovery ends so the follow-through doesn't block locomotion, and
  `queue_action(anim)` to play a continuation clip (a swing's `_Rec`) straight
  after the current one-shot without a crossfade. `death_animation` is empty
  because the ragdoll handles death.
- Old knight assets (`assets/characters/knight/`, `knight_rig.tscn`,
  `build_knight_rig.gd`, `knight_post_import.gd`, `RagdollLimbFollow`) are
  no longer used; kept until the new characters are confirmed.

## Ragdoll

- 11 `PhysicalBone3D`s (pelvis, spine_02 (chest), head, upper/lower arms,
  thighs, calves) under `Skeleton3D/PhysicalBoneSimulator3D`, capsule shapes,
  cone joints with swing/twist limits, layer 7 `ragdoll`, mask `world`.
  Unsimulated bones (spine_01, neck, clavicles, hands, feet) follow their
  nearest simulated parent.
- `RagdollComponent` (node `Ragdoll`) listens to `HealthComponent.died`: it
  freezes the AnimationPlayer, starts the simulation and gives every bone the
  body's velocity plus a knockback away from the last damage source
  (`knockback_speed`, `knockback_lift`; defaults 3 and 1.5 m/s, enemies use 10
  and 6). `knockback_spin` (rad/s, default 5) adds a backwards flip away from
  the attacker: every bone gets `v + w x r` about the body centre so the body
  tumbles as one piece; `spin_randomness` varies axis and speed. Corpses stay
  forever. Its optional `limb_follow` was only needed by the knight's IK feet.
- The CharacterBody3D stays where the character died (collision layer 0);
  only the visuals move.
- Pause the game with `SceneTree.paused`, never `Engine.time_scale = 0`:
  zero-length physics steps give the kinematic physical bones NaN/inf
  velocities. (`RagdollComponent` overwrites velocities on start as a guard.)
- Testing note: `Skeleton3D` restores pre-modifier poses after each update, so
  scripts must observe ragdoll bone positions through `BoneAttachment3D`
  nodes, not `get_bone_global_pose()`.
- Unused but imported for a future equipment system: `assets/equipment/`
  (ShortSword, Katana, Helmet1-3, ShoulderPads).

## Enemies

- `EnemyStats` resource (`scripts/enemies/enemy_stats.gd`) holds per-type
  numbers; one `.tres` per enemy type in `resources/enemies/`.
- `EnemyController` state machine: `IDLE` (walk back to spawn) -> `CHASE`
  (within `detection_radius` and in line of sight) -> `ATTACK` (within
  `attack_range`) and back; gives up beyond `lose_interest_radius` or when the
  target dies.
- Line of sight: `can_see_target()` raycasts from `eye_height` to the target's
  `target_aim_height` against `sight_mask` (world layer). Pillars and walls
  block sight; low rocks may not. While chasing without sight the enemy heads
  to the last seen position and returns home after `stats.lose_sight_time`
  seconds. `stats.requires_line_of_sight = false` restores radius-only
  detection. `DEAD`
  disables collision and the hurtbox.
- Attacks go through the enemy's `MeleeAttack` node (`MeleeAttackComponent`),
  configured from `stats` at ready. Facing locks when the wind-up starts so
  the player can sidestep.
- `STAGGER` state: a staggering hit (`HitReaction.staggered`) cancels the
  attack; navigation and attacks are suspended until hitstun ends, then the
  enemy resumes `CHASE`. Knockback (also a flinch's small push) is added to
  its velocity in every live state. `EnemyStats.poise` / `knockback_scale`
  configure the reaction.
- The enemy's own `AttackHitbox` is still the fixed box in front of it (not
  club-shaped and not swept).
- Taking damage while idle switches the enemy to `CHASE` (hit aggro), even
  without line of sight.
- Target = first node in group `player`; aliveness via its `is_dead` property.
- `enemy_knight.tscn`: the knight model recoloured through surface material
  overrides (armour/skin/boots), wielding the Club. Stats:
  `resources/enemies/ashbound_knight.tres`.
- `WorldHealthBar` + `shaders/billboard_bar.gdshader`: camera-facing bar,
  fill via the per-instance shader parameter `ratio`.

## Player movement feel

- `PlayerController._apply_movement()` is momentum-based: velocity along the
  wanted direction accelerates (`acceleration` 15 m/s², `start_boost` 1.3x at
  standstill fading to 1x), the part across/against it brakes (`turn_braking`
  28), and with no input it slows at `deceleration` 30. Roughly 0.4 s to full
  speed, 0.2 s to stop, short arcs on direction changes. Tunables are in the
  "Movement Feel" export group.
- While strafing (aiming or locked on), off-axis movement is slower:
  `diagonal_speed_multiplier` 0.65 at 45° from the facing,
  `strafe_speed_multiplier` 0.6 at 90°, `backpedal_speed_multiplier` 0.55 at
  180°, blended in between, full speed only straight ahead. The Mixamo
  directional cycles naturally move at 2.1–2.65 m/s; at full speed (6 m/s)
  they would skate even at the 1.6x cycle-rate cap. 1 = off.

## Dodge roll

- `DodgeComponent` (`scripts/components/`, node `Dodge` on the player) runs
  one roll at a time: ROLL (moving) -> RECOVERY (rooted, getting up) ->
  READY. The owner calls `start(direction)` and, while `is_dodging()`,
  applies `current_velocity()` instead of its own movement (same pattern as
  the melee lunge). Each tick's velocity is the change of an analytic
  ease-out position curve (`falloff` 0.75) over that tick, so the distance is
  exact at any tick rate. Defaults: `distance` 4 m over `duration` 0.6 s,
  `recovery` 0.15 s, i-frames 0.03–0.4 s from the start (sets
  `HurtboxComponent.invulnerable`), `cooldown` 0.9 s between roll starts.
- Animation: UAL1 `Roll` (in place, 1.47 s) via `play_action()`, sped up to
  span roll + recovery (~1.96x). Only a forward roll exists, so the character
  snaps to face the roll direction; while aiming or locked on it turns back
  toward the cursor / target afterwards.
- Player rules (`PlayerController._update_dodge()`): Space is buffered for
  `input_buffer_time`. Direction = WASD, else the cursor, else the model's
  forward. A roll can cut into an attack's recovery but not its wind-up or
  strike (the press stays buffered). During the roll, attack presses are
  buffered without expiring; movement input, a buffered attack or a held
  attack ends the get-up recovery early. A stagger or death cancels the roll.
  Not armoured while rolling: outside the i-frames hits stagger as usual.
- Debug-menu buttons don't take keyboard focus, so Space (`ui_accept`) never
  presses a focused button instead of dodging.

## Levels

- `scenes/world/dungeon_01.tscn` is the current level. It is **generated** by
  `tools/build_dungeon.gd` from the Dungeon Scrawl map
  `assets/maps/dungeon_01.ds` (preview: `dungeon_01_preview.png`); re-run it
  instead of hand-editing:
  `godot --headless --path . -s res://tools/build_dungeon.gd`.
- The generator reads the .ds zip (`map` JSON): the template's dungeon shape
  polygon (floor + outer walls), its polylines (partition walls), door assets
  (wooden frames) and text labels (a `Marker3D` per label under `Markers`,
  e.g. `Start`, `BossRoom`). 1 grid cell (36 px) = `CELL` 2 m; map x -> +X,
  map y -> +Z, bounding-box centre = origin.
- Floor = one box per run of grid cells; walls = boxes on the void side of
  each edge (2.6 m). Outer walls facing the camera (+X/+Z) are drawn only
  0.9 m tall so they don't hide the room, but their collision stays full
  height (movement and enemy line of sight are unaffected). Torches go on the
  other walls (one per edge >= 4 cells, two from 8).
- Props are a hand-placed table at the top of the script (grid-cell
  coordinates): pillars, crates, barrels, tables, chest, rubble, statue,
  braziers, campfire, throne (static bodies under the navigation region) and
  decor without collision (carpet, bedroll). Placeholder primitive meshes.
- The player start and the single (boss-room) enemy are placed in
  `main.tscn` at the `Start` / `BossRoom` marker positions.
- `test_arena.tscn` and its navmesh are no longer used by `main.tscn`.

## Navigation

- `TestArena/NavigationRegion3D` parents all walkable/blocking static geometry
  (ground, walls, obstacles); hazards stay outside so they don't block paths.
- The dungeon navmesh is baked by `tools/build_dungeon.gd` into
  `resources/navigation/dungeon_01_navmesh.tres` (static colliders on layer 1,
  agent radius 0.5, agent height 2). The test arena's
  (`test_arena_navmesh.tres`) is baked with the editor's "Bake NavigationMesh"
  button.
- The baked mesh sits 0.5 m above the floor, so agents use
  `path_height_offset = 0.5`; without it they never advance past their first
  waypoint.

## Layout

```
scenes/main/main.tscn                Entry scene: dungeon + player + enemies + camera rig + HUD
scenes/world/dungeon_01.tscn         GENERATED level (tools/build_dungeon.gd from assets/maps/dungeon_01.ds)
scenes/world/test_arena.tscn         Old prototype arena (unused)
scenes/world/hazards/spike_trap.tscn Test hazard: 10 damage/s to the player
scenes/player/player.tscn            CharacterBody3D, humanoid rig + sword, appearance, health, hurtbox, animator, ragdoll
scenes/characters/humanoid_rig.tscn  GENERATED: male body glTF + ragdoll + hand attachment + animations
scripts/characters/                  character_animator, character_appearance, appearance_component, ragdoll_component, occlusion_silhouette
tools/build_humanoid_rig.gd          Generates humanoid_rig.tscn
tools/build_dungeon.gd               Generates dungeon_01.tscn + its navmesh
assets/maps/                         Dungeon Scrawl source maps (.ds) and previews
tools/import/ual_post_import.gd      Strips per-bone position tracks from the animation library
tools/build_mixamo_library.gd        Retargets Mixamo FBX locomotion onto the Universal skeleton
assets/characters/mixamo/            mixamo_locomotion.res (generated; rig library "MX")
assets/characters/universal/         Base character bodies, hair parts, animation library (CC0)
resources/characters/                CharacterAppearance .tres files
(unused)                             knight_rig.tscn, build_knight_rig.gd, knight_post_import.gd, assets/characters/knight/
assets/equipment/                    Weapon and armour FBX meshes
scenes/camera/iso_camera_rig.tscn
scenes/ui/hud.tscn                   Player health bar, "Defeated" + restart hint
scenes/debug/debug_menu.tscn         F1 debug panel
scripts/main/main.gd                 Restart flow (on the Main node)
scripts/world/enemy_spawner.gd       Random navmesh spawns
scripts/ui/damage_numbers.gd         Floating combat numbers
scripts/components/                  health, hitbox, hurtbox, melee attack, hit flash components
scripts/combat/                      AttackProfile, HitEvent, HitReactionComponent, ImpactFeedbackComponent, Hitstop
scripts/vfx/                         ImpactEffect (placeholder), WeaponTrail
scripts/audio/placeholder_sfx.gd     Synthesised stand-in hit/whoosh sounds
resources/combat/                    Player AttackProfiles (combo A/B/C, cleave; slash and rising cut unused)
tests/combat_test.gd                 Headless combat checks: godot --headless --path . -s res://tests/combat_test.gd
tests/lock_on_test.gd                Headless lock-on / attack-direction checks (same command, lock_on_test.gd)
scripts/player/player_controller.gd
scripts/player/lock_on_component.gd  Enemy lock-on (middle mouse / Tab) and target marker
scenes/enemies/enemy_knight.tscn     Melee enemy (ash-skinned humanoid + club)
scripts/enemies/                     enemy_controller.gd, enemy_stats.gd
resources/enemies/                   EnemyStats and enemy CharacterAppearance .tres files
resources/navigation/                Baked navmeshes
shaders/billboard_bar.gdshader
scripts/ui/world_health_bar.gd
scripts/camera/iso_camera_rig.gd
scripts/ui/hud.gd
```

First milestone complete. Enemy line-of-sight added. Characters replaced with
the Universal base characters + runtime appearance. Weighted movement. First
dungeon level generated from a Dungeon Scrawl map. Combat feel: swept blade
hits, attack profiles with a light combo and a heavy attack, hit reactions
with poise, hitstop, impact effects and placeholder sounds. Possible next
steps: real hit/swing sounds and VFX, a club-shaped swept hitbox for the
enemy, more enemy types, equipment, abilities.
