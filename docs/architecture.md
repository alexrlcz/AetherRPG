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
| `dodge`        | Left Shift         | Dodge roll toward the WASD direction (toward the cursor if none held), with i-frames (see Dodge roll). |
| `jump`         | Space              | Jump (see Player movement feel). |
| `sprint` (hold) | Left Alt          | Sprint at 8 m/s; faces the movement direction even while aiming / locked on. Light attack while sprinting = Dash Strike. |
| `walk_toggle`  | Left Ctrl          | Toggle walking (1.6 m/s, `Walk_Formal` cycle). |
| `zoom_in/out`  | Mouse wheel        | Orthographic zoom. |
| `restart`      | R                  | After death (1 s delay): start a new run at level 1 (new seed). |
| `debug_menu`   | F1                 | Toggle the debug panel (debug builds only): spawn / kill enemies, heal, **generate a level** (seed + Generate, or Random level), player appearance and **player weapon** (Sword / Greatsword). |
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
- Player `AttackHitbox` (masks `enemy_hurtbox`, `sweep` on) is a box along
  the blade under the `RightHand` bone attachment, sized and placed by the
  equipped weapon (sword: 0.25 x 0.3 x 0.9 m; see Weapons): only the
  swinging blade hits.
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
| Cleave | heavy | Sword_Attack | 0.62 s incl. 0.14 s hold at the top | 0.10 s (0.37-0.50) | 0.55 s (0.50-0.77) | 40 | breaks poise, **knockdown**, knockback 7.5, hitstop 0.11 s, lunge 0.9 m |
| Dash Strike | light while sprinting | UAL2/Sword_Dash | 0.25 s (0-0.27) | 0.13 s (0.27-0.40) | 0.6 s (0.40-1.50) | 25 | heavy weight, lunge 3.0 m (lead 0.2 s), knockback 6, stagger 30; next light = Sweep |

- Combo order lives on the player (`light_combo`, `heavy_attack`,
  `light_after_heavy` = 0): profiles never reference each other (cyclic
  resources don't load reliably). Light -> light -> light, light -> heavy and
  heavy -> Rising Slash all chain; after the Finisher the combo wraps to A.
  The Finisher and the Cleave have `knockdown` set (see the knockdown below).
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
  - knockdown: a staggering hit whose profile has `knockdown` plays
    `UAL2/Hit_Knockback` (0.83 s, falls on its back) then
    `UAL2/LayToIdle` (`get_up_speed` 1.3x, ~1.18 s), queued without a
    crossfade: the first ends in exactly the pose the second starts from.
    The whole sequence (`knockdown_duration()`, ~2.0 s) is the hitstun;
    `is_knocked_down()` is true throughout. The owner turns the victim to
    face the attacker so it falls away from the blow. Hits while down deal
    damage but don't restart or extend it. The player's reaction has
    `knockdown_invulnerable` (hurtbox ignores hits until up; set after
    `staggered` so the dodge cancel can't clear it); enemies can be hit
    while down. Knockdown sources: player Cleave and Finisher, enemy dash.
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
- Mixamo clips are retargeted onto this skeleton by
  `tools/build_mixamo_library.gd` into two libraries: locomotion (jog
  forward diagonals, strafe left/right, jog backward, jog backward
  diagonals) in `assets/characters/mixamo/mixamo_locomotion.res` (the rig's
  `MX` library) and all 48 greatsword clips in
  `assets/characters/mixamo/mixamo_greatsword.res` (`GS`: locomotion, turns,
  jumps, attacks, impacts, deaths, block, crouch, draw, power-up, casting;
  names in the builder's `CLIPS_GS`). The source FBX files (65-bone
  `mixamorig_` skeleton) are read at build time from outside the project
  (`E:/GODOT/Aether/mixamo animations`, or a path passed after `--`), so the
  raw Mixamo files are not in the repo. Per-clip options: `loop` (false for
  one-shots), `root_motion` (forward travel extracted into a curve, see
  Weapons) and `no_rise` (in-place jumps keep their crouch but never rise). Both skeletons rest in a T-pose facing +Z, so each bone
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
  `queue_action(anim, speed)` to play a continuation clip (a swing's `_Rec`,
  the knockdown's get-up) straight after the current one-shot without a
  crossfade. `death_animation` is empty because the ragdoll handles death.
- Sprint / formal walk: above `run_to_sprint_speed` 7.0 m/s (±0.3 hysteresis)
  the cycle is `Sprint` (rate = speed / 7.06 m/s, its stride measured against
  `Jog_Fwd`'s). While the body's `is_walking` is true the walk cycle is
  `Walk_Formal` (same stride and timing as `Walk`).
- Jump / air / landing are automatic from `is_on_floor()`: leaving the floor
  moving up faster than 1 m/s plays `Jump_Start` (from 0.1 s, past the
  crouch, at 1.5x); after it ends, or when falling for more than
  `min_air_time` 0.12 s, the `Jump` loop plays (legs hanging). Touching down
  after that plays `Jump_Land` from its contact frame (0.05 s, 1.4x); moving
  cuts it short after `land_cancel_time` 0.15 s. A flat 1 m jump lands
  before `Jump_Start` ends, so the `Jump` loop is only seen on long falls.
- Idle variants (player only, `idle_variants` on its Animator): after
  `idle_variant_delay` 8 s standing still and not strafing, a random variant
  (never the same twice in a row) loops for whole cycles of at least
  `idle_variant_min_duration` 4 s, then `Sword_Idle` returns and the delay
  restarts. Moving, any one-shot, aiming or lock-on cancels it. Variants:
  `Idle`, `Idle_Talking`, `Idle_Torch`, and UAL2 `Idle_FoldArms`,
  `Idle_Lantern`, `Idle_No`, `Idle_Rail`, `Idle_Rail_Call`, `Idle_Shield`,
  `Idle_TalkingPhone`. The prop idles (torch, lantern, shield, phone, rail)
  are played with the sword in hand; nobody holds those props yet.
- Old knight assets (`assets/characters/knight/`, `knight_rig.tscn`,
  `build_knight_rig.gd`, `knight_post_import.gd`, `RagdollLimbFollow`) are
  no longer used; kept until the new characters are confirmed.

## Weapons

- `WeaponDefinition` (`scripts/combat/weapon_definition.gd`, one `.tres`
  per weapon in `resources/weapons/`): model + placement, hitbox box and
  placement, trail ends (all in the `RightHand` attachment's space), player
  attacks (`light_combo`, `heavy_attack`, `dash_attack` / `dash_heavy_attack`
  for light / heavy at sprint speed, `light_after_heavy`), enemy attacks
  (`enemy_attack` + range, `enemy_dash_attack` + ranges) and three override
  dictionaries applied while wielded: `animator_overrides`
  (CharacterAnimator: animation set), `reaction_overrides`
  (HitReactionComponent: hit clips) and `character_overrides` (the body,
  e.g. the player's speeds).
- `WeaponComponent` (`scripts/combat/weapon_component.gd`, node `Weapon`,
  last child of the player and the knight): `equip(weapon)` restores the
  previous weapon's overridden properties, swaps the model under
  `RightHand` (`WeaponModel`), gives the hitbox's CollisionShape3D a new box
  (`HitboxComponent.refresh_shapes()`), moves the trail ends, applies the
  overrides and emits `equipped`. The controllers take their attacks from
  it (`_on_weapon_equipped()`, an attack in progress is cancelled) and the
  occlusion silhouette refreshes. `random_weapons` picks one on ready;
  `ignored_overrides` lets a character skip some (knights skip
  `idle_variants`).
- Player: starts with the sword; the debug menu (F1) swaps Sword /
  Greatsword (`DebugMenu.player_weapons`, `equip_player_weapon()`).
  Knights: club or greatsword at random.
- `sword.tres` (player): `Sword.fbx`, the A -> B -> C combo, Cleave, Dash
  Strike; no overrides (the scene defaults are the sword set).
  `club.tres` (knights): `Club.fbx`, club swing (1.7 m), knight dash (3–5 m).
- `greatsword.tres`: `assets/equipment/Claymore.fbx` (Quaternius Medieval
  Weapons, CC0, `LICENSE_medieval_weapons.txt`), scale 0.26 → 1.35 m long,
  1.08 m blade (fists are 0.27 m apart in the clips, so both fit on the
  grip). Right fist just under the cross guard, flat facing the palm.
  Blade direction in `hand_r` space: (0, -0.205, 0.979), close to the hand's
  forward axis. The line between the two fists would be the natural
  handle, but the Mixamo left hand isn't constrained to it, and following
  it (the first version) drove the tip into the floor in the Downward
  Cleave (-0.21 m), Flurry and Whirlwind (-0.58 m) and held the idle sword
  far out to the side. The chosen axis keeps the tip at least 0.2 m above
  the floor in every greatsword clip (checked by `tests/weapon_test.gd`,
  every attack > 0.1 m) at the cost of the left hand sitting further off
  the handle (~48° average fist mismatch vs 22°). Hitbox 0.3 x 1.1 x 0.25 m
  along the blade.
- Greatsword animation set (`animator_overrides`): idle `GS/Idle`
  (variants `GS/Idle_2..5`), walk `GS/Walk` (0.97 m/s), run `GS/Run`
  (3.84 m/s, also used for sprint: `sprint_animation` empty), strafe
  `GS/Strafe_L/R`, backward and backward diagonals `GS/Run_Bwd`, forward
  diagonals fall back to the run, no formal walk. Jump `GS/Jump` from its
  take-off (0.15 s) at 0.66x, so its contact frame (0.62 s) meets the 0.7 s
  arc's landing; landing = the same clip from 0.62 s; at run speed
  `GS/Jump_Run` (`run_jump_animation`, from 0.08 s). Hit reactions
  `GS/Impact_2` (light) / `GS/Impact` (heavy); knockdown stays UAL.
  Player speeds: run 5 m/s, sprint 6.5, walk 1.2 (the clips are slower than
  the sword set's).
- Greatsword strike windows were measured from the blade tip's speed and
  position (fast and in front of the body), not guessed:

| Attack | Input | Clip | Wind-up | Strike | Recovery | Damage | Notes |
|---|---|---|---|---|---|---|---|
| Downward Cleave | light 1 | GS/Slash | 0.45 s (0-0.57) | 0.18 s (0.57-0.80) | 0.55 s (to 1.27) | 24 | lunge 0.4 m |
| Rising Sweep | light 2 | GS/Slash_3 | 0.55 s (0-0.80) | 0.18 s (0.80-1.03) | 0.6 s (to 1.83) | 26 | lunge 0.4 m |
| Flurry I | light 3 | GS/Slash_2 | 0.55 s (0-0.80) | 0.16 s (0.80-1.03) | 0.35 s (to 1.30) | 18 | root motion, chain after 0.08 s |
| Flurry II | light 4 | GS/Slash_2 | 0.25 s (1.30-1.66) | 0.14 s (1.66-1.86) | 0.35 s (to 2.30) | 18 | continues the clip |
| Flurry III | light 5 | GS/Slash_2 | 0.2 s (2.30-2.55) | 0.15 s (2.55-2.72) | 0.75 s (to 3.53) | 30 | **knockdown** |
| Whirlwind | heavy | GS/Spin_Attack | 0.3 s | 1.0 s (0.30-1.30, each target once) | 0.5 s | 38 | root motion 2.1 m, **knockdown** |
| Slide Strike | light while sprinting | GS/Slide_Attack | 0.9 s (0-1.20, slides) | 0.17 s (1.20-1.43) | 0.6 s | 28 | root motion 3.1 m; reaches 4.5 m |
| Leaping Slam | heavy while sprinting | GS/Jump_Attack | 0.75 s (0-1.03, leaps) | 0.2 s (1.03-1.27) | 0.75 s | 40 | root motion ×1.4 (4 m), **knockdown** |
| Knight Cleave | knight | GS/Slash | 0.8 s incl. 0.12 s hold | 0.2 s | 1.0 s | 18 | reach measured 2.0 m (`enemy_attack_range`) |
| Knight Leap | knight dash, 2.8-5 m | GS/Jump_Attack | 1.0 s | 0.22 s | 1.1 s | 22 | root motion ×1.4, **knockdown** |

- Root motion (`AttackProfile.root_motion`): the builder stores the hips'
  forward travel as metadata `root_motion` (metres per frame at 30 fps)
  and leaves it out of the pose; `MeleeAttackComponent.lunge_speed()`
  returns its rate at the current clip position × playback speed ×
  `root_motion_scale`, through every phase, so the body covers exactly the
  clip's distance whatever the phase timings (tested within 0.15 m). It
  stops when the clip stops (move-cancel) and on contact with bodies.
- Not used yet (imported, waiting for their mechanics): `GS/Attack` and
  `GS/Slash_4` (no clear strike in front: a pommel/body move and an overhead
  twirl), kicks, crouched slash, block (`Block*`), crouch (`Crouch*`,
  `Crouch_Impact*`), `Draw*` (sheathing), `Power_Up`, `Casting`, turns in
  place (`Turn*`), deaths (the ragdoll handles death).

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
- Attacks go through the enemy's `MeleeAttack` node (`MeleeAttackComponent`)
  and come from its weapon (`Weapon` node, see Weapons): `attack_profile`
  within `attack_range`, `dash_attack` between `dash_min_range` and
  `dash_max_range`; `EnemyStats` keeps only `dash_cooldown`. Each knight
  picks the club or the greatsword at random on spawn
  (`WeaponComponent.random_weapons`). Facing locks when the wind-up starts
  so the player can sidestep.
- `STAGGER` state: a staggering hit (`HitReaction.staggered`) cancels the
  attack; navigation and attacks are suspended until hitstun ends, then the
  enemy resumes `CHASE`. Knockback (also a flinch's small push) is added to
  its velocity in every live state. `EnemyStats.poise` / `knockback_scale`
  configure the reaction.
- The enemy's `AttackHitbox` (masks `player_hurtbox`, `sweep` on) is a box
  along the weapon under the `RightHand` bone attachment, like the player's
  blade: only the swinging weapon hits, so sidesteps and rolls are judged
  against the real arc. Club (`knight_club_swing.tres`, the old
  `EnemyStats` swing: 15 damage, 0.7 s wind-up): 0.28 x 0.28 x 0.62 m, the
  `Sword_Attack` markers (strike 0.37–0.5 s, recovery to 1.0 s); measured
  reach up to 1.7 m (centre to centre) ahead and 0.6 m to either side,
  misses at 2.3 m and behind it (`tests/enemy_test.gd`). Greatsword: see
  Weapons.
- No ground telegraph: the wind-up animation is the only warning.
- Taking damage while idle switches the enemy to `CHASE` (hit aggro), even
  without line of sight.
- Dash attack (the weapon's `enemy_dash_attack`; club:
  `resources/combat/knight_dash.tres`): while chasing with the target in
  sight between the dash ranges (club 3–5 m) and `dash_cooldown` 5 s since
  the last one. The club version plays `UAL2/Sword_Dash`: 0.6 s wind-up (0.15 s hold), a 3.3 m lunge
  (from 0.25 s before the strike), strike 0.27–0.40 s of the clip, 1.1 s
  recovery with no move-cancel. 20 damage, heavy, **knockdown**. The
  controller adds `melee.lunge_speed()` along its facing while attacking;
  the lunge stops on contact (bodies collide, or the hit lands). The club
  hitbox and the facing lock work as for the basic swing, so a sidestep or
  roll late in the wind-up avoids it.
- Target = first node in group `player`; aliveness via its `is_dead` property.
- `enemy_knight.tscn`: the knight model recoloured through surface material
  overrides (armour/skin/boots), wielding a random weapon. Stats:
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
- Top speed (`_top_speed()`): `sprint_speed` 8 m/s while `sprint` is held
  and moving (`is_sprinting`, cleared while attacking, staggered or
  rolling), else `walk_speed` 1.6 m/s with the walk toggle on
  (`is_walking`), else `move_speed` 6 m/s. Sprinting turns strafing off
  (`is_strafing` is false), so the character faces where it runs even while
  aiming or locked on; the lock itself stays.
- Jump: `jump_height` 1 m with gravity × `air_gravity_multiplier` 1.6 in the
  air (≈0.7 s airborne). Takes off only on the floor and when not attacking,
  staggered or rolling; presses are buffered for `input_buffer_time`. In the
  air, held directions steer at `air_control` 0.35 of the ground rates and
  no input keeps the momentum (a running jump carries ~4 m); attacks and
  dodges don't start until the landing (their presses stay buffered). A
  1 m jump can reach crates and tables; enemies can't follow (navmesh).

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
- Player rules (`PlayerController._update_dodge()`): the dodge press (Left Shift) is buffered for
  `input_buffer_time`. Direction = WASD, else the cursor, else the model's
  forward. A roll can cut into an attack's recovery but not its wind-up or
  strike (the press stays buffered). During the roll, attack presses are
  buffered without expiring; movement input, a buffered attack or a held
  attack ends the get-up recovery early. A stagger or death cancels the roll.
  Not armoured while rolling: outside the i-frames hits stagger as usual.
- Debug-menu buttons don't take keyboard focus, so Space (`ui_accept`, now jump) never
  presses a focused button instead of jumping.

## Levels

- Levels are built by code from a `DungeonLayout`, at runtime or by a tool
  (step 1 of the procedural levels plan, see the "Aetherfall — Procedural
  Level Generation Design" doc):
  - `DungeonLayout` (`scripts/world/dungeon_layout.gd`): a level on the 2 m
    cell grid, independent of its source: `floor_rings` (closed polygons;
    floor = inside an odd number of them, so outlines, holes and islands
    all work), `partitions`, `doors`, `labels`, `props`, `origin`.
    `from_dungeon_scrawl(path)` reads a Dungeon Scrawl map; the seeded
    generator (step 2) will fill one in code.
  - `DungeonBuilder` (`scripts/world/dungeon_builder.gd`): `build(layout)`
    returns the level's node tree (rules below); static
    `bake_navigation(level, on_thread)` bakes its navmesh
    (`make_navigation_mesh()` = the shared settings).
  - `DungeonLevel` (`scripts/world/dungeon_level.gd`, a Node3D): `build(layout)`
    at runtime, bakes on a thread and emits `navigation_ready` once the
    **navigation map** uses the new navmesh, not merely when the bake ends:
    the map takes a new region's navmesh in on a later background sync (a
    few physics frames), and until then path queries come back empty, so it
    polls until the map finds a point of the new navmesh. Spawn enemies and
    start the level only after the signal. dungeon_01 builds in 0.013 s and
    is playable 0.03-0.06 s after `build()` (headless).
- `LevelGenerator` (`scripts/world/level_generator.gd`, step 2): seeded
  layouts made in code. A main path of `main_rooms` (6) rectangular rooms
  (6-11 cells a side) from the start to the exit, `branches` (2) side
  branches of 1-2 rooms off the rooms between, and with `loop_chance` (0.5)
  one extra corridor between two rooms that face each other across a short
  gap. Rooms join by straight corridors, 2 cells wide and 3-7 long, at least
  1 cell from a room's corners, with a door frame at each end. Unconnected
  rooms and corridors keep `gap` (2) empty cells apart, so walls never
  merge. For the first half of its tries each main-path room must land
  further from the start than the previous one, so the path heads somewhere
  instead of curling back. All randomness comes from one
  RandomNumberGenerator seeded from the level seed (and the attempt number
  when a layout can't be completed, which is rare; `layout.seed` is the
  asked-for seed either way), so a seed always gives the same level. The
  floor cells are traced into outline rings (`DungeonLayout.set_floor_cells()`,
  collinear points merged) for DungeonBuilder; `layout.rooms` /
  `layout.corridors` keep roles (start, path, exit, side), depth and links
  for the props, enemy and gate passes. Labels: `Start`, `Exit`. Measured:
  1.4 ms per layout, 7-10 rooms per level, about a third with a loop, built
  and baked in 0.06-0.11 s (`tests/level_generator_test.gd`: 300-seed sweep,
  outline vs cells on 60 seeds, 15 real builds with a navmesh path from Start
  to the Exit and every room).
- Population (step 3), run by `LevelGenerator.generate(seed, level)` after
  the layout, each pass on its own RNG seeded from the level seed:
  - `PropScatter` (`scripts/world/prop_scatter.gd`), on any room shape (each
    room's `cells`): reserves each room's routes (a 3x3 block around the
    room's centre cell plus the shortest walk from every doorway to it,
    widened by one cell) as `layout.reserved_cells`, then places props off
    them (props against interior/partition walls sit nearer the cell centre:
    those walls stand on the cell edge): 4 pillars in half
    the rooms >= 9 cells a side; 1 to area/20 clusters of 1-2 crates or
    barrels against the walls (crates 0.2 cells from the wall, barrels 0.25,
    one crate in corner cells: a turned crate's corner reaches further);
    rubble in a corner (30%); a table (25%, rooms >= 8); a statue (15% of
    path rooms); campfire + bedroll in the start room; braziers in two exit
    room corners; a chest against the far wall of dead-end side rooms (60%).
    One prop group per cell (`layout.blocked_cells` = cells with collision),
    and a blocking prop is skipped if any free cell of its room would lose
    its way to the doorways. About 38 props per level.
  - `EncounterPlanner` (`scripts/world/encounter_planner.gd`, on room
    `cells` too) with an
    `EnemyRoster` (`resources/encounters/knights.tres`: `EnemyEntry`
    resources = scene, weapon, cost, first level; club knight 2 points from
    level 1, greatsword knight 3 from level 3): each room's budget =
    (2 + 1.5 x level) +-20%, x0.5 side rooms, x1.5 the exit, none in the
    start room, spent on random affordable entries, at most one enemy per
    12 room cells. Each enemy gets its own cell, never a prop cell, more
    than 2 cells (Chebyshev) from every doorway and 6 cells (12 m) from
    Start, facing the room's centre. Writes `layout.spawns`. Measured: 7.1
    enemies per level at level 1, 15.5 at 3, 26.4 at 6 (starting values to
    tune; nothing yet stops a room from attacking at once).
- Hand-made maps in the run (step 5). `LevelPool`
  (`scripts/world/level_pool.gd`) picks each run level's source: one of the
  `.ds` maps in `assets/maps/` for `scrawl_chance` (30%) of levels, decided
  by the level seed, else a generated layout; an unusable map falls back to
  a generated level with a warning. `LevelPool.map_layout(path, seed, level)`
  reads the map, finds its rooms and populates it with the same PropScatter
  and EncounterPlanner rules. In pool mode a map's own hand-placed props
  (dungeon_01's table) are not used.
  - `RoomAnalysis` (`scripts/world/room_analysis.gd`): floor cells = cells
    whose centre is floor; partition polylines block the cell edges they run
    along (`layout.blocked_edges`; walking = `layout.can_step()`). Core cells:
    3x3 block all floor, no partition touching it, and part of a 2x2 block of
    such cells, so passages up to 3 cells wide and door gaps are never core.
    Connected cores (>= 4 cells) are rooms; each reaches out `claim_radius`
    (2) cells from its core by walking. The rest is corridor. Start room =
    the one holding the `start` label (labels match case-insensitively);
    exit = the `exit` label's room, else the room furthest (walking) from
    the start, and an `Exit` label is added at its centre (the builder puts
    the gate there). Rooms on the room-graph route start -> exit are
    `path`, the rest `side`. dungeon_01: 8 rooms, exit = the boss room.
  - `DungeonLayout` now carries `floor_cells`, `blocked_edges`, each room's
    `cells` (generated rooms fill theirs from the rect) and `source`;
    `room_entries()` finds doorways from cells (room cells you can step out of
    into other floor), `room_centre()`, `walk_distances()`.
  - Adding a map: draw it in Dungeon Scrawl on its grid, put a text label
    `start` (optional `exit`), interior walls as the template's lines, doors
    as door assets; save the `.ds` into `assets/maps/`. It joins the pool,
    and the debug menu's map list (Play map, with the seed / level boxes)
    plays it directly. For exported builds `*.ds` must be added to the export
    filter (non-resource files are not exported by default).
  - `Main.play_layout(layout)` is the shared core (ticket, spawns, gate);
    `generate_level()`, `play_map()` and `load_run_level()` (via the pool)
    call it. `tests/map_pool_test.gd`: rooms of dungeon_01, props / enemies
    on it over 60 seeds (incl. partition-wall clearance and no cut-off
    cells), a real build with gate and reachable spawns, the pool's share
    and fallbacks, Main playing a map.
- Boss floors (step 6). `GameRun.floor_kind(n)` (static): `FLOOR_BOSS` every
  5th level of a chapter, `FLOOR_CHAPTER_BOSS` on its last (15), else
  normal; `GameRun.level_title(n)` ("Level 5 · Boss") titles the fade and
  the HUD. `LevelPool.layout_for()` turns boss levels into
  `LevelGenerator.generate_boss(seed, level, encounter)` floors (never maps;
  `Main.generate_level()` goes through the pool too, so the debug Generate
  at level 5 gives a boss floor).
  - `BossEncounter` (`scripts/world/boss_encounter.gd`, one .tres per boss in
    `resources/encounters/`): title, boss `EnemyEntry`, escorts + count,
    arena side. `warden_boss.tres` (Ashbound Warden: 14-cell arena, alone)
    and `chapter_boss.tres` (The Cinder Champion: 16-cell arena, 2 club
    knights).
  - Layout: start + 1-2 approach rooms (no branches, no loop) + a square arena
    with role `boss` (`exit_role` / `exit_room_size` on LevelGenerator). The
    `Exit` label (gate) sits 2.5 cells from the arena wall opposite the way
    in. PropScatter: arena always gets pillars (when >= 9 cells), braziers
    in all four corners, wall clusters, no table / statue; the cells around
    every Exit label are kept clear (all levels). The roster budget for
    `boss` rooms is 0; `EncounterPlanner.place_boss()` puts the boss on the
    arena's centre facing the way in (`spawn.boss = true`) and escorts on
    free cells >2 cells from it. `layout.boss` = the encounter.
  - Elites: `EnemyEntry` Elite group (`size_scale`, `health_scale`,
    `damage_scale`, `poise_scale`), copied by Main onto `EnemyController`
    before `_ready()`, which then applies them to its own copy of `stats`
    (health, poise, knockback / detection), the `Visual` scale, its own
    copies of the body and hurtbox capsules, health bar / damage numbers
    height, nav agent size, reach (`attack_range`, dash ranges), root-motion
    lunge, `MeleeAttackComponent.damage_scale`, and the ragdoll's death
    throw (÷ size). Bosses are elite knights until they get their own
    scenes and AI.
  - `Main`: the boss spawn becomes `Main.boss`; the gate is `sealed` (dark
    red portal, ignores the player) until the boss's `died` →
    `ExitGate.unseal()`; signal `boss_spawned(boss, title)` → `HUD.show_boss()`
    (`hud` export). The HUD's top-centre boss bar fades in when the boss first
    leaves IDLE (it noticed the player), follows its health, and reads
    "<title> falls — the gate opens" on death.
  - `tests/boss_test.gd`: floor kinds and titles, 40 seeds each of level 5
    and 15 floors (roles, arena size, gate in the arena and clear of props,
    one boss + escorts apart), elite scaling (own stats and shapes, ragdoll
    sane), a real chapter-boss build (gate and all enemies reachable), Main:
    sealed gate, bar on engage, gate opens on the boss's death, through to
    level 6.
- Run flow (step 4). `RunState` autoload (`scripts/run/run_state.gd`,
  class `GameRun`; scripts reach it with `GameRun.current()`, because the
  autoload's global name doesn't compile when a script is the main loop,
  i.e. the `-s` test suites): `run_seed`, `level` (1-based across
  chapters), `player_health` carried at each gate, `level_seed(n)` =
  hash(run seed, n), `chapter()` / `level_in_chapter()` (15 per chapter),
  `is_boss_level()` (step 6: boss and chapter-boss floors), `start_new_run()`,
  `advance(health)`, debug `jump_to(level)`, signal `level_changed`.
  - `Main` (`scripts/main/main.gd`) no longer holds a static level: on start
    it starts a run if none is active and builds the run's current level
    (`load_run_level()`), behind `LevelFade` (black + "Level N" title,
    0.35 s fades). Health carries naturally (the player node persists);
    `RunState.player_health` records it for scene-based loading later.
  - `ExitGate` (`scripts/world/exit_gate.gd`): stone arch + glowing portal +
    light, built in code. `DungeonBuilder` puts one on every `Exit` label
    under the navigation region, so its solid pillars bake into the navmesh.
    It emits `player_entered` once, only for bodies in group `player`, armed
    0.5 s after it enters the tree. Main then calls `RunState.advance()`,
    fades out, builds the next level and fades back in.
  - Enemies keep `exit_clearance` (2 cells) off the gate.
  - Death: R (`restart()`) starts a new run and reloads the scene.
  - `HUD` shows "Level N" (RunState.level_changed).
- `Main.generate_level(seed, level)` (debug menu: seed + level boxes +
  Generate, or Random level; the debug path also moves the run to that level)
  replaces the dungeon with a generated `DungeonLevel`, puts the player on
  `Start` (snapping the camera) and, once the navmesh is in use, replaces the
  old enemies with the level's spawns (each wielding its entry's weapon,
  home = its spawn) and connects the gate. Each call takes a ticket; a call
  that finds a newer one started while it baked returns null, so only the
  newest level is ever kept.
  `tests/run_test.gd`: RunState, start on level 1, gate ignores knights,
  player through the gate -> level 2 with health carried, gate pillars are
  navmesh holes, overlapping requests.
  `tests/population_test.gd`: props in rooms, off routes, inside walls, no
  cut-off cells (200 seeds); spawn rules at levels 1/3/6; every spawn on the
  navmesh and reachable in 8 real builds; spawned enemies stay put.
- `DungeonLevel` readiness: the map's closest point to the new navmesh must
  belong to this level's region (`map_get_closest_point_owner`); a plain
  distance check passed early when a level replaced another, because the map
  still held the old level's navmesh for a few frames.
- `scenes/world/dungeon_01.tscn` is the current level, **generated** by
  `tools/build_dungeon.gd` from `Dungeon01Layout`
  (`scripts/world/dungeon_01_layout.gd`: the Dungeon Scrawl map
  `assets/maps/dungeon_01.ds`, preview `dungeon_01_preview.png`, plus its
  prop table) through `DungeonBuilder`; re-run it instead of hand-editing:
  `godot --headless --path . -s res://tools/build_dungeon.gd`. The tool
  keeps the scene's UID (`main.tscn` references it). The earlier hand edits
  (campfire light 10, Barrel6 moved) now live in the builder / prop table.
  `tests/dungeon_builder_test.gd` checks that the runtime build matches the
  saved scene shape for shape.
- The .ds reader takes the `map` JSON in the zip: the template's dungeon
  shape polygon (floor + outer walls), its polylines (partition walls), door
  assets (wooden frames) and text labels (a `Marker3D` per label under
  `Markers`, e.g. `Start`, `BossRoom`). 1 grid cell (36 px) = `CELL` 2 m;
  map x -> +X, map y -> +Z, bounding-box centre = origin.
- Floor = one box per run of grid cells; walls = boxes on the void side of
  each edge (2.6 m). Outer walls facing the camera (+X/+Z) are drawn only
  0.9 m tall so they don't hide the room, but their collision stays full
  height (movement and enemy line of sight are unaffected). Torches go on the
  other walls (one per edge >= 4 cells, two from 8).
- Props are `[kind, cell x, cell y, yaw]` entries (dungeon_01: the table in
  `Dungeon01Layout`): pillars, crates, barrels, tables, chest, rubble, statue,
  braziers, campfire, throne (static bodies under the navigation region) and
  decor without collision (carpet, bedroll). Placeholder primitive meshes.
- `main.tscn` no longer instances dungeon_01 or its seven knights: the run
  builds its levels; dungeon_01 is in the level pool with any other map in
  `assets/maps/`.
- `test_arena.tscn` and its navmesh are no longer used by `main.tscn`.

## Navigation

- `TestArena/NavigationRegion3D` parents all walkable/blocking static geometry
  (ground, walls, obstacles); hazards stay outside so they don't block paths.
- The dungeon navmesh is baked by `tools/build_dungeon.gd` into
  `resources/navigation/dungeon_01_navmesh.tres` (static colliders on layer 1,
  agent radius 0.5, agent height 2: `DungeonBuilder.make_navigation_mesh()`);
  runtime levels bake the same settings on a thread (`DungeonLevel`). The test arena's
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
tools/build_dungeon.gd               Saves dungeon_01.tscn + its navmesh (via DungeonBuilder)
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
scripts/world/dungeon_layout.gd      DungeonLayout: a level on the cell grid (+ Dungeon Scrawl reader)
scripts/world/dungeon_builder.gd     DungeonBuilder: layout -> level scene, navmesh settings and bake
scripts/world/dungeon_level.gd       DungeonLevel: runtime build + threaded bake, navigation_ready
scripts/world/dungeon_01_layout.gd   Dungeon01Layout: the first dungeon's map + prop table
scripts/world/level_generator.gd     LevelGenerator: seeded room-and-corridor layouts (+ population)
scripts/world/room_analysis.gd       RoomAnalysis: rooms, start / exit of hand-made maps
scripts/world/level_pool.gd          LevelPool: generated level or a hand-made map per run level
scripts/world/exit_gate.gd           ExitGate: the portal to the next level
scripts/run/run_state.gd             RunState autoload (class GameRun): the current run
scripts/ui/level_fade.gd             LevelFade: fade + level title over level swaps
scripts/world/prop_scatter.gd        PropScatter: route reservation + prop rules
scripts/world/encounter_planner.gd   EncounterPlanner: enemy budget and placement
scripts/world/enemy_roster.gd        EnemyRoster / enemy_entry.gd EnemyEntry: data for the planner
resources/encounters/                Rosters and enemy entries
scripts/ui/damage_numbers.gd         Floating combat numbers
scripts/components/                  health, hitbox, hurtbox, melee attack, hit flash components
scripts/combat/                      AttackProfile, HitEvent, HitReactionComponent, ImpactFeedbackComponent, Hitstop, WeaponDefinition, WeaponComponent
scripts/vfx/                         ImpactEffect (placeholder), WeaponTrail
scripts/audio/placeholder_sfx.gd     Synthesised stand-in hit/whoosh sounds
resources/combat/                    AttackProfiles: player sword (combo A/B/C, cleave, dash; slash and rising cut unused), greatsword (gs_*), knights (club swing, dash, gs_knight_*)
resources/weapons/                   WeaponDefinitions: sword, club, greatsword
tests/combat_test.gd                 Headless combat checks: godot --headless --path . -s res://tests/combat_test.gd
tests/*_test.gd                      Also dodge, lock_on, enemy, movement, weapon, dungeon_builder, level_generator, population, run and map_pool suites (same command, other file)
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
