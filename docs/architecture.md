# Architecture

## World and camera

- The world is true 3D (Godot 4.7, Forward+ renderer, Jolt physics).
- The camera (`IsoCameraRig`) smoothly follows its target and blends from an
  isometric overview into a third-person view as it zooms in. It is always
  perspective; `zoom` runs 0 (furthest) to 1 (closest):
  - 0 .. `overview_zoom_end` (0.5): the overview. Pitch 35.264° (true
    isometric), a narrow 25° field of view from 41-68 m away, so it looks
    close to the old orthographic view; the visible height at the target
    shrinks from `max_view_height` 20 m to `min_view_height` 10 m (start:
    zoom 0.3 = 14 m). It was 30 m; zooming that far out showed most of a
    level at once.
  - `overview_zoom_end` .. 1: the close-up (smoothstep blend). The distance
    falls exponentially to `close_distance` 3.5 m, the fov widens to 55°, the
    pitch flattens to 12° and the look point rises to `close_look_height`
    1.4 m (the chest): a third-person camera.
  - The wheel steps `zoom` by 0.08 and the rig glides there, at any time.
    Default yaw 45° (`yaw_degrees`).
  - Free look, only while the target stands still (horizontal speed under
    `free_look_max_speed` 0.25 m/s): holding `camera_rotate` (middle mouse)
    and dragging orbits (sideways, 0.3° per physical pixel,
    `screen_relative`) and tilts (up / down, 0.2°/px, -25..+35° around the
    zoom's pitch, final pitch 5..85°). No panning. These are offsets on the
    default view (`get_yaw()`, `get_tilt()`). As soon as the target moves,
    they ease back to zero over
    `return_time` 0.7 s (cubic ease in / out, the yaw the short way round);
    the zoom is kept. Dragging while moving does nothing; dragging while
    standing during the return stops it. `set_yaw()` sets the default and
    drops the free look; `reset_free_look()`.
  - WASD follows the view as it is now (`get_movement_basis()`, the rig's
    yaw including free look): W is up the screen, so walking off from a
    rotated view goes the way it faced, and the walking direction turns
    with the camera while it eases back.
- Walls are 4.2 m tall on every side (`DungeonBuilder.WALL_HEIGHT`) and use
  `shaders/wall_cutout.gdshader`. Each frame the rig sets the global shader
  parameters (project.godot `[shader_globals]`) `cutout_camera`,
  `cutout_target` (player + 1 m), `cutout_radius`, `cutout_front_width` and
  `cutout_stub_height`:
  - Front cutaway: everything on the camera's side of the player (more than
    0.4 m toward the camera, faded in over 0.5 m) within
    `cutout_front_width` of the view line is cut down to
    `cutout_stub_height` (0.5 m). Overview: 40 m (the whole screen: near
    walls read as low dark rims, far walls stay full height); close-up:
    1.6 m (only what stands between the camera and the character).
  - Hole: within `cutout_radius` (2.2 m overview, 1.0 m close up) of the
    camera-to-player line, cut entirely.
  - Pixels are discarded with a dither (walls stay opaque-pass). Faces seen
    from behind (inside a cut wall) draw as dark rock, so cut walls look
    solid. The shader also darkens walls toward the top.
  - Door frames (and the wall over each doorway), wall torches (bracket,
    handle and an emissive flame) and pillars use the same shader with
    other colours, so they are cut with the walls; their lights stay on.
- The directional fill light's `directional_shadow_max_distance` is 150 m
  because the overview camera sits up to ~70 m from the player.
- Gameplay code never depends on the camera except to convert input
  (screen-relative WASD, mouse aim). Simulation stays in world space, which
  keeps a future server-authoritative multiplayer model possible.

## Controls

| Action         | Default            | Behaviour |
|----------------|--------------------|-----------|
| `move_*`       | WASD / arrow keys  | Screen-relative movement; character faces movement direction. |
| `aim` (hold)   | Right mouse        | Character keeps facing the cursor; WASD still moves screen-relative (strafe / walk backwards). With a shield worn it also raises the shield (block). |
| `camera_rotate` (hold) | Middle mouse | While standing still: drag sideways to orbit, up / down to tilt. Eases back when the player moves. |
| `lock_on`      | Q                  | Lock onto the nearest visible enemy within 15 m, or release the lock. While locked the character always faces the target and strafes like `aim`; the lock wins over `aim`. |
| `cycle_target` | Tab                | Next lock target, nearest to farthest, wrapping (locks the nearest if unlocked). |
| `attack`       | Left mouse (hold to repeat) | Light combo: Rising Slash -> Sweep -> Finisher -> Rising Slash... (see Combat feel). |
| `heavy_attack` | E                  | Cleave: slow, committed overhead blow that breaks enemy poise. |
| `dodge`        | Left Shift         | Dodge roll toward the WASD direction (toward the cursor if none held), with i-frames (see Dodge roll). |
| `jump`         | Space              | Jump (see Player movement feel). |
| `sprint` (toggle) | Left Alt        | Toggle sprinting (8 m/s while moving); breaks when you stop, attack, take damage, run out of stamina or die (press again to resume). Faces the movement direction even while aiming / locked on. Light attack while sprinting = Dash Strike. |
| `walk_toggle`  | Left Ctrl          | Toggle walking (1.6 m/s, `Walk_Formal` cycle). |
| `zoom_in/out`  | Mouse wheel        | Zoom; zooming in past the overview blends into a third-person view. |
| `interact`     | F                  | Use what's in reach (a chest, gear on the floor), with a "[F] ..." prompt (see Loot, Equipment). |
| `inventory`    | I                  | Open / close the inventory screen (Escape also closes it); the game keeps running. |
| `toggle_fullscreen` | F11           | Fullscreen (the start-up mode) <-> windowed. |
| `use_flask`    | R                  | Drink a healing flask (see Healing flasks). Shares R with `restart`: drinking needs you alive, restarting dead. |
| `restart`      | R                  | After death (1 s delay): start a new run at level 1 (new seed). |
| `debug_menu`   | F1                 | Toggle the debug panel (debug builds only): spawn / kill enemies, heal, **god mode**, **generate a level** (seed + Generate, or Random level), player appearance and the **Equipment** panel. |
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

## Fog of war

- `FogOfWar` (`scripts/world/fog_of_war.gd`, node `FogOfWar` in Main;
  Main calls `setup(layout)` for every level). Each floor cell is
  unexplored (pitch black: not even the layout), explored (seen before:
  layout and props dim and unlit, no enemies) or in sight, with soft
  transitions. Rooms and corridors are treated alike: a room is never lit
  as a whole, only as far as the circle reaches.
- In sight = the cells in line of sight within `sight_fade` (5 cells,
  10 m) of the player: a cell counts when
  a straight line from the player's exact cell point reaches its centre or
  one of four points near its corners, crossing only floor and no wall
  (`can_step`; a grid walk along the line). So the player sees a cone into
  a room through its door and down a corridor, never through walls. The
  light is full up to `sight_radius` (3.5 cells, 7 m) and fades out
  smoothly (smoothstep) to `sight_fade` (10 m), per pixel from the player's
  position. Recomputed when the player moves `refresh_distance` (0.25
  cells). `refresh()`, `cell_at()`, `light_at()`, `is_visible_at()`,
  `is_explored_at()`, `is_enemy_visible_at()`.
- Explored: every mask texel keeps the brightest light it has had (0..1),
  so explored areas have the same soft edges; `explored` lists the cells
  whose light passed 0.3.
- Enemies (children of Main's `Enemies`) are shown only in line of sight
  within `enemy_sight` (4.5 cells, 9 m) (checked every 0.1 s), which hides
  their health bars and numbers too.
- Drawing: `mask` is a cell-space image (`TEXELS_PER_CELL` 4; R =
  explored 0..1 per texel, G = line of sight per cell), sampled with linear
  filtering. The shader's light = G x falloff(distance to `viewer`); the
  pixel is multiplied by a blend of black, `explored_tint` x max(R, light)
  and white.
  Texels just outside the floor (outer walls) take the brightest state of
  the floor cells within `wall_reach` (0.8 cells), so a lit room's walls
  are lit; interior walls lie on cell edges, so each face takes its own
  side. A full-screen quad on the active camera runs
  `shaders/fog_of_war.gdshader`: each pixel's world position from the depth
  buffer is turned back into a cell point (the warp inverted by 8
  fixed-point steps, waves from `DungeonLayout.warp_waves()`, like
  `DungeonLayout.to_cell()`) and multiplied (blend_mul) by black /
  `explored_tint` (0.34, 0.36, 0.48) / white. It is drawn first among
  transparent things (`render_priority` min), so damage numbers, health
  bars and silhouettes stay on top. The sky / nothing is black.
- Debug menu: "Fog of war" checkbox (`enabled`; off = no darkening, every
  enemy shown).
- `tests/fog_test.gd`: to_cell() round trip; the player's spot lit,
  nothing lit past 10 m, the start room not lit as a whole, far room
  unexplored, mask values, walls lit, quad on the camera; moving lights the
  new place and dims the old; no line of sight through interior walls, the
  corridor lit, cells hidden behind walls from a corridor; the falloff curve and partly explored texels; enemies shown
  exactly by `is_enemy_visible_at()`; the checkbox; a new level starts
  unexplored.

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
  `heal()`, `reset()`. `god_mode` (debug menu checkbox for the player): no
  damage is taken, so hits don't stagger either. Valid from construction, independent of ready order.
- `HurtboxComponent`: `receive_event(event)` applies damage, fills in
  `applied`/`lethal`, then emits `hurt(amount, source)` and
  `hit_received(event)` (only if damage was taken). `last_hit` is set before
  damage so `died` listeners (ragdoll) can read the killing blow.
  `receive_hit(amount, source)` remains for plain damage. While `invulnerable`
  (dodge i-frames) every hit is ignored and `evaded(event)` is emitted
  instead. The hitbox still counts that hurtbox as hit for the activation, so
  a dodged swing cannot land later in the same strike. Then, if its optional
  `guard` (BlockComponent) blocks the hit (try_block()), nothing is applied
  and `blocked(event)` is emitted (see Shield and blocking).
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
- HUD shows the player's health and stamina bars (see Stamina), and
  "Defeated" + "Press R to try again"; `scripts/main/main.gd` (on
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
- `DebugMenu` (`scenes/debug/debug_menu.tscn`): F1 panel with Spawn enemy, God mode,
  Heal player, Kill all enemies and an alive-enemy count; F2 spawns directly.
  "Player appearance" section: body, skin texture, skin tint, hairstyle, hair
  colour, eyebrows, beard and Randomize. It edits a duplicate of the player's
  CharacterAppearance and calls `apply()`; changes are not saved.
  The rows sit in a ScrollContainer whose height `fit_to_screen()` caps to
  the window (re-fitted on resize and when opened), so a small window (the
  default 1152x648) scrolls instead of cutting off the bottom rows.
  "Equipment..." (under Kill all enemies) opens the Equipment panel
  (`EquipmentMenu`, a child of the debug menu placed just left of its
  panel; see Equipment); closing the debug menu closes it too.
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
  beard, eyebrows, and an outfit (see Outfits below). `AppearanceComponent` (node `Appearance`) builds it on the
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

## Equipment

- Slots (`Equipment.SLOTS`): head, neck, shoulders, chest, back (cloak),
  wrists, hands (gloves), legs, feet (boots), ring_1, ring_2, trinket,
  main_hand, off_hand. Item slots are `GearDefinition.Slot` (HEAD, BACK,
  FEET, OFF_HAND, NECK, SHOULDERS, CHEST, WRISTS, HANDS, LEGS, RING,
  TRINKET, MAIN_HAND; appended so saved slot numbers stay valid);
  `Equipment.SLOTS_OF` maps them (RING fits either ring slot).
- Items are `GearDefinition`s (extends ItemDefinition, kind GEAR, picked up
  with the interact key), with `modifiers` (stats while equipped) and
  `describe_modifiers()` ("+4 Armor, +5% Move speed"):
  - `OutfitPieceDefinition` (`scripts/items/outfit_piece_definition.gd`):
    meshes from the Modular Character Outfits models (`outfit`,
    `male_meshes` / `female_meshes`, `cloth_variant`), with
    `hides_body_bones` and `hides_hair`.
  - Model gear (helmet, shield): built by GearBuilder (see Gear).
  - `WeaponDefinition` now extends GearDefinition (slot MAIN_HAND; its
    `display_name` and `model` are the item's; `is_worn_visual()` false:
    the model goes in the hand).
  - Stat-only (no model): neck, rings, trinket.
- `Equipment` (`scripts/items/equipment.gd`, node `Equipment` on the
  player, last so it applies after the others): the single source of
  truth. `equip(item, slot = auto)` returns the previous item (rings fill
  the first free ring slot; an item never goes in a slot it doesn't fit),
  `unequip(slot)`, `get_item(slot)`, `get_items()`, `slot_for()`,
  `slots_for()`, signal `changed(slot, item, previous)`. Every change: the
  worn visual items become the appearance's `gear` (its own duplicate of
  the .tres) and it is re-applied; all modifiers become the CharacterStats
  source `&"gear"` (`STATS_SOURCE`); the main-hand weapon (or
  `default_weapon`, the sword, while empty) is equipped on the
  WeaponComponent; and, `persistent`, the slots are saved to the profile.
- Saving: `PlayerProfile.equipment` (slot -> resource path, profile JSON
  version 2), written by `set_equipment()` on every change and restored on
  ready; a fresh profile starts with `starting_items` (sword, Peasant
  Tunic, Trousers, Shoes). Under test suites and tools the profile doesn't
  persist (`persists()`: no save path), so every new player starts fresh.
- Items (`resources/items/gear/`, generated, small fixed stats): Fantasy
  Helmet (+10 armor), Ranger Hood (+4, hides hair), Amulet of Vigor (+20
  health), Ranger Pauldron (+5), Peasant Tunic (+4), Ranger Jerkin with its
  belts (+10), Ranger Bracers (+3), Peasant Wraps (+5 stamina), Ranger
  Gloves (+3), Peasant Trousers (+4), Ranger Leggings (+7), Peasant Shoes
  (+2), Ranger Boots (+4, +5% move speed), Ring of Endurance (+20 stamina),
  Ring of Might (+10% damage), Swiftness Charm (+8% move speed), Wooden
  Shield (+5); weapons Sword, Club, Greatsword. No cloak yet.
- `ItemCatalog` (`scripts/items/item_catalog.gd`,
  `resources/items/catalog.tres`): every player item; `for_slot()`,
  `pick(rng)`.
- Visuals (`AppearanceComponent`): outfit pieces are attached mesh by mesh
  for the body (`<Male|Female>_<outfit>.gltf`), their skin surfaces (hands,
  `MI_Regular_*`) take the body's skin texture and tint, `cloth_variant`
  swaps the cloth (`OUTFIT_TEXTURES`). The body is cut where any worn
  item's `hides_body_bones` say (the union, sorted, one cached cut per
  body and bone set): tunic = spine, clavicles, upper arms; jerkin = spine,
  clavicles; wraps = forearms, hands, fingers; gloves = whole arms and
  fingers; trousers / leggings = pelvis, thighs, calves; shoes = feet;
  boots = feet and calves. Pieces mix freely; nothing worn shows the body.
- Pickups: gear on the floor is an interactable once landed
  (`Pickup.can_interact()`, prompt "Take <name> (<stats>)", the
  `PickUp_Table` animation); `collect()` equips it when a slot it fits is
  empty (the collector's `equipment`), else puts it in the collector's
  `inventory`; with the bag full it stays and the HUD shows "Bag full"
  (`collect()` returns false).
- Loot: `LootTable.gear` (the catalog) and `gear_chance`: one random item
  on top of the rest. Enemies 6%, chests 40%, bosses 100%.
- Debug Equipment panel (`EquipmentMenu`, `scenes/debug/equipment_menu.tscn`,
  "Equipment..." in the debug menu, replacing the Outfits panel and the
  weapon option): one picker per slot ("None" + the catalog's items that
  fit), `choose(slot, item)`, `get_option(slot)`; follows changes made
  elsewhere.
- `tests/equipment_test.gd`: the starting loadout (and its 10 armor); rings
  and slot rules, stats from the amulet / rings / charm, `changed`; the
  full Ranger set (meshes, hood hides hair, body cut, skin hands, armor
  36), female meshes, mixing; the main hand and the default sword; F on a
  floor item equips it and drops the old one; saving and restoring through
  the profile on disk; gear in loot rolls (~6% from an enemy, every slot
  covered but the cloak); the debug panel.

## Inventory

- `Inventory` (`scripts/items/inventory.gd`, node `Inventory` on the
  player): `capacity` (24) cells, each a GearDefinition or null (gear
  doesn't stack; gold stays in the profile), keeping their place.
  `add()` (first free; false when full), `remove_at()`, `move(from, to)`
  (swap), `item_at()`, `count()`, `is_full()`, `first_free()`,
  `get_cells()`, signal `changed`. With `equipment`: `equip_from(index,
  slot = auto)` (the replaced item takes the cell), `unequip_to(slot,
  index = first free)` (a taken cell swaps only if its item fits the
  slot; false with a full bag), `drop(index)` / `drop_equipped(slot)`
  (a Pickup at the owner's feet, in the level's drop container).
  `persistent`: saved as `PlayerProfile.inventory` (resource path per
  cell, "" for empty; `set_inventory()`), loaded on ready, like
  Equipment.
- Inventory screen (`InventoryScreen`, `scripts/ui/inventory_screen.gd`,
  node in Main, built in code; `scripts/ui/item_slot.gd` per cell):
  "inventory" (I) toggles it, Escape closes it; the game keeps running.
  Left: the 14 equipment slots (two columns), right: the bag (6 x 4),
  stats (`DebugMenu.stats_text()`) and gold. Cells show the item's name
  on a colour per kind (weapons red, shield brown, jewellery gold, trinket
  purple, armour blue; no icons yet). Double-click or right-click: equip
  from the bag / take off to the bag ("Bag full" via HUD.notify()). Drag
  and drop (`can_drop()` / `drop()`): bag <-> bag swaps, bag -> a slot the
  item fits equips there, slot -> bag takes it off (a taken cell swaps if
  its item fits), ring 1 <-> ring 2; dropped outside the window (the
  full-screen backdrop, `drop_to_floor()`) it falls on the floor. Tooltip
  (`tooltip_text_for()`, a RichTextLabel): name, slot, stats; for a bag
  item "Instead of <worn>:" and the stat changes in green / red
  (`compare()`). While open a full-screen backdrop takes every click (no
  attacks, no wheel zoom) and `PlayerController.mouse_blocked` stops right
  mouse from aiming / blocking; the keyboard still moves the player.
- `HUD.notify(text)`: a short message above the interact prompt (HUD is in
  group `HUD.GROUP`, so gameplay code calls it with call_group()).
- Display: the game starts fullscreen (`display/window/size/mode` 3,
  canvas_items stretch, so the 1152x648 layout scales up); F11
  (`Main.toggle_fullscreen()`) switches to windowed and back.
- `tests/inventory_test.gd`: the bag (cells, moving, full), equip_from /
  unequip_to (swaps, refusals, full bag), dropping, saving and restoring
  cells in place, the screen in Main (I / Escape, owns the mouse, cells,
  tooltip comparison, double-click and right-click, every drag rule, drop
  outside, "Bag full"), the fullscreen setting.

## Gear (helmet, shield)

- Assets (Sketchfab, credits and licences in
  `assets/equipment/gear/CREDITS.md`): `helmet_fantasy.glb` (badbanshee,
  CC-BY 4.0), not rigged. The leather boots and the cloak were removed
  (the cloak's licence was non-commercial); the BOOTS and CLOAK rigs below
  are kept for replacement models but have no item or test right now.
- `GearDefinition` (`scripts/items/gear_definition.gd`, extends
  ItemDefinition with kind GEAR, not auto-collected; `.tres` in
  `resources/items/gear/`): `slot` (HEAD / BACK / FEET / OFF_HAND), `model`,
  `anchor_bone`, `fit` (model space -> offset from the anchor bone's rest
  origin, skeleton axes: Y up, facing +Z; fitted to the male body, other
  bodies move with their anchor; with `fit_in_bone_space` the fit is in the
  anchor bone's own rest frame instead, like a weapon in the hand), `rig`, `hides_hair`, `hides_parts`
  (outfit mesh names), `hides_body_bones` (body triangles cut away).
  `CharacterAppearance.gear` holds what is worn (`gear_in(slot)`,
  `set_gear(slot, item)`). Stats come with the character stats step.
- `GearBuilder` (`scripts/characters/gear_builder.gd`, static) turns a
  gear model into meshes skinned to the character's Skeleton3D: the model's
  surfaces are moved into skeleton space by the fit (normals, tangents,
  winding fixed for mirroring), weighted by the rig, given a Skin of named
  binds; cached per gear and body rests (the first build is the slowest,
  later applies reuse the cache).
  - RIGID: all on the anchor (helmet on `Head`, 2.6x, ~3.5 cm clear of the
    skull, hides the hair and an outfit hood).
  - BOOTS: the model is the right boot (turned 180 deg: its steel cap is the
    heel), a mirrored copy goes on the left; weights calf above the ankle
    (0.1-0.2 m blend), toes past the ball, foot between. Boots cut the body's
    feet (`hides_body_bones`) and hide an outfit's feet, so no toe pokes out.
  - CLOAK: `ensure_cloak_bones()` hangs CLOAK_COLUMNS (5) chains of
    CLOAK_JOINTS (4) bones `cloak_<column>_<joint>` from `spine_03`, placed
    on the cloth itself (columns across 80% of the collar, joints from under
    the collar to above the hem, at the cloth's mean depth). Cloth is
    weighted bilinearly to the chains; the top CLOAK_COLLAR (0.12 m) blends
    to `spine_03` so the collar stays on the shoulders. A
    `SpringBoneSimulator3D` ("CloakSpring" under the Skeleton3D, `active`
    only while a cloak is worn) swings the chains: stiffness 8, drag 0.8,
    gravity 5, radius 0.05, colliding with capsules on both thighs and
    calves, the pelvis and `spine_02`. Measured on the player (cloth angle
    from hanging straight down): ~12 deg idle, ~38 deg running 6 m/s,
    ~52 deg sprinting 8 m/s, back to rest within 2.5 s of stopping; it
    follows a roll and the ragdoll without stretching. The cloak is fitted
    behind the back (about 3 cm clear at the shoulders, 6 cm at the calves,
    tilted 3 deg back).
  - Note: the simulated pose only exists during the skeleton's update; read
    cloak bones inside `Skeleton3D.skeleton_updated`.
- `AppearanceComponent` builds model gear after the body and outfit
  pieces, applies its hides (cut body via `_cut_body()`), and turns the
  cloak simulation on / off. Creatures wear no gear.
- `tests/gear_test.gd`: the helmet item and slot; worn mesh, hair hidden,
  skin bound to `Head`; on the female body; taken off; the Equipment
  panel's head picker.

## Mutant boss (level 5)

- Assets: `assets/characters/mutant/Mutant.fbx` (Mixamo "Warrok W
  Kurniawan", royalty-free for games) and `mutant_animations.res`, built
  by `tools/build_mutant_library.gd` from the Mixamo FBX downloads in
  `D:/AetherRPG/mutant` (same skeleton: no retargeting; only the animation
  data is kept): Idle, Walk (Strut Walking, in place, reference speed
  0.98 m/s), Swipe, JumpAttack (in place), Roar, Flex, Dance (Hip Hop
  Dancing, looping), Dying. The tool prints when each hand moves fastest
  (the hit moments: swipe ~1.25 s, the leap's slam ~1.67 s, both mostly
  the left hand).
- `scenes/enemies/enemy_mutant.tscn`: the knight's components on the
  Mixamo model (no ragdoll or appearance: death plays `Mutant/Dying`); the
  AnimationPlayer gets the library as "Mutant"; the claw hitbox rides
  `mixamorig_LeftHand`. `resources/enemies/mutant.tres` (slow strut
  1.6 m/s, detection 15 m), `resources/weapons/mutant_claws.tres` (Swipe
  2.6 m reach, Leap from 4.5–9 m: knockdown), `resources/combat/mutant_*.tres`.
- `MutantBoss` (`scripts/enemies/mutant_boss.gd`): the first time the
  controller starts chasing (the player entered its arena) it plays Roar or
  Flex at random, held in place facing the player
  (`EnemyController.hold(seconds)`); when the player dies from its hit
  (`last_hit.source`), it holds forever and dances.
- `EnemyController.hold(seconds)` / `release_hold()` / `is_held()`:
  stands still facing the target, no chasing or attacks.
- Level 5: `LevelPool.level_bosses` (`{5: mutant_boss.tres}`) replaces the
  default boss on that level only; "Warrok the Mutant", x10 health.
- `tests/mutant_test.gd`: level 5's boss and level 10's, the clips, the
  intro hold, landing hits, the dance only for its own kills, the death.

## Monsters (Bestiary)

- Assets: Quaternius "Bestiary - Dungeon Monsters Kit" (Standard, the free
  part: Imp and Puglin) in `assets/characters/monsters/`: `Imp.glb`,
  `Puglin.glb` (textures embedded, extracted by the import), the 2nd / 3rd
  colour textures, the licence. The models carry no animations; they are
  rigged to the Universal skeleton (55 of its bones: no pinkies or toe
  tips), which the pack meant for the Universal Animation Library, i.e.
  the clips the game already has. Each one's weapon (Imp mace, Puglin
  stick) is part of its mesh, skinned to the right hand.
- `CharacterAppearance.creature` ("Imp" / "Puglin", `CREATURES` with the
  colour names: Imp Crimson / Bile / Frost, Puglin Moss / Blood / Deep) and
  `creature_variant` (-1 = random). `AppearanceComponent` then wears the
  creature model instead of a body (no hair or outfit): its bone rests
  become the rig's proportions like a body's, and `Skeleton3D.motion_scale`
  is set to the creature's pelvis height / the animation pelvis height, so
  the human-authored pelvis bob and crouches scale to the creature's legs
  (without it the 0.93 m Puglin's feet sank into the floor). The random
  colour is rolled per character (`_creature_variant`), not written into
  the appearance resource the enemies of a type share.
- Enemy scenes `enemy_imp.tscn` / `enemy_puglin.tscn` inherit
  `enemy_knight.tscn` (same AI, combat, bars, ragdoll, drops) and override
  stats, appearance, weapon (no random weapons), loot, body / hurtbox
  capsules, bar and damage-number heights and `eye_height`. Weapons
  (`resources/weapons/imp_weapon.tres`, `puglin_weapon.tres`) have no model
  (the mesh has it): a hitbox fitted to the weapon's bind-pose box in hand
  space and one swing (`resources/combat/imp_swing.tres`,
  `puglin_swing.tres`, the `Sword_Attack` clip like the club).

  | | Imp | Puglin |
  |---|---|---|
  | Height (head bone) | 1.68 m (1.38) | 0.93 m (0.65) |
  | Health / poise / knockback x | 45 / 18 / 1.1 | 26 / 6 / 1.4 |
  | Speed / turn | 4.2 / 12 | 4.6 / 14 |
  | Swing: damage, wind-up, recovery | 13, 0.55 s, 0.75 s | 7, 0.45 s, 0.6 s |
  | Reach | 1.6 m | 1.25 m |
  | Stamina / regen | 55 / 9 | 40 / 10 |
  | Body capsule / hurtbox (r x h) | 0.38 x 1.7 / 0.4 x 1.7 | 0.35 x 1.0 / 0.42 x 1.4 |
  | Roster cost, first level, gold | 2, 1, 4-7 | 1, 1, 2-4 |

  The Puglin's hurtbox reaches above its 0.93 m model so the player's
  waist-high swings still connect (the light combo lands 3 of 3).
- Both are in the dungeon roster (`resources/encounters/knights.tres`,
  entries `imp.tres` / `puglin.tres`); at cost 1 Puglins are the most
  common enemy (29 level-2 layouts: 268 Puglins, 152 Imps, 144 club
  knights; tune with `cost` / `min_level`). Debug F2 spawns a random
  knight, Imp or Puglin (`EnemySpawner.enemy_scenes`).
- `tests/monster_test.gd`: model and per-monster random colour, health and
  reach, no extra weapon model, standing head height, idling at its own
  scale with feet on the floor, chasing and swinging (`Sword_Attack`) and
  hitting the player for its damage, the player's combo hitting a Puglin,
  an imp's gold, the roster placing both.

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
- Player: the weapon is the main-hand item (Equipment; the sword to start
  and while the main hand is empty); the debug Equipment panel swaps it.
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

- `EnemyStats` resource (`scripts/enemies/enemy_stats.gd`, extends
  StatBlock) holds per-type numbers; one `.tres` per enemy type in
  `resources/enemies/`. Its core stats (health, stamina, regen, armor) go
  through the enemy's `CharacterStats` node `Stats` (see Character stats);
  its enemy defaults (60 hp, 60 stamina, 8/s) are set in `_init()`.
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
- Top speed (`_top_speed()`): `sprint_speed` 8 m/s while the sprint toggle
  (`sprint_toggled`) is on and moving (`is_sprinting`, false while
  attacking, staggered or rolling). The toggle breaks (`_stop_sprint()`)
  when movement input ends while sprinting (it can be switched on while
  standing, ready for the first step), when an attack starts (after picking
  the dash attack), on any damage taken (`HealthComponent.damaged`; a dodged
  hit doesn't count), on exhaustion and on death. Otherwise `walk_speed` 1.6 m/s with the walk toggle on
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

## Shield and blocking

- Asset: `assets/equipment/shield/Shield_Wooden.gltf` with the kit's trim
  textures (Quaternius Fantasy Props MegaKit, CC0; licence file alongside).
  Round, ~0.62 m, face +Z, origin on the vertical grip.
- `ShieldDefinition` (`scripts/items/shield_definition.gd`, extends
  GearDefinition; slot OFF_HAND, anchor `hand_l`, `fit_in_bone_space`):
  `block_angle` (arc in front that blocks, 140 deg), `stamina_per_damage`
  (1.5). `resources/items/gear/shield_wooden.tres`; its fit puts the grip in
  the left palm, upright and facing forward in the guard pose (computed from
  `UAL2/Idle_Shield`'s hand pose). Built by GearBuilder (RIGID on `hand_l`)
  and equipped like any gear (the Equipment panel's "Off hand" picker, or
  picked up).
- `BlockComponent` (`scripts/components/block_component.gd`, node `Block`
  on the player): finds the worn shield (`appearance`, refreshed on
  `applied`). The owner sets `raised`; `is_guarding()` = raised, a shield
  worn and stamina not exhausted. `try_block(event)` (asked by
  `HurtboxComponent.guard`): blocks when guarding and the attacker (its
  position, else `-event.direction`) is within half the arc of the body's
  facing; costs `amount * stamina_per_damage` stamina, no damage, no
  stagger; feedback: ImpactEffect at the contact, placeholder clang (hit
  sound pitched up), 0.05 s hitstop, small camera shake, "Block" from
  DamageNumbers; emits `blocked`. A hit costing more than the stamina left
  drains it to 0 (exhausted, so the shield drops until stamina recovers),
  emits `guard_broken` and lands in full.
- `GuardPoseModifier` (`scripts/characters/guard_pose_modifier.gd`,
  SkeletonModifier3D created by BlockComponent as the Skeleton3D's first
  child, before the ragdoll / cloak modifiers): samples `UAL2/Idle_Shield` at
  0.6 s for `clavicle_l` and every bone below it (arm, hand, fingers) and
  sets those local rotations while `raised`, blended through `influence` at
  10/s. The legs and torso keep playing locomotion, so the character can
  run with the shield up. The AnimationPlayer has no layers; this is the
  upper-body overlay.
- Player rules: holding `aim` (right mouse) with a shield worn raises it
  while free to act (not attacking, rolling, drinking, interacting or
  staggered; those lower it until they end). Facing and movement are the
  aiming ones (cursor or locked target, strafe speeds: full speed straight
  ahead, 0.55-0.65 sideways / backwards). Raising it ends a sprint.
  `PlayerController.is_guarding` makes CharacterAnimator play
  `guard_idle_animation` (`UAL2/Idle_Shield`) when standing still.
- Known gaps: the flask is drunk with the left hand, so the shield stays in
  that hand during a drink; enemies don't carry shields or react to being
  blocked.
- `tests/block_test.gd`: the item; right mouse without a shield only aims;
  guard up / arm raised / guard stance / sprint ended / running with it up /
  lowered on release; front and 45 deg hits blocked for stamina, side and
  back hits land; guard break; attacking and rolling lower it; a real
  knight's swing blocked; the panel's Off hand picker.

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

## Character stats

- Core stats (`CharacterStats.Stat`): MAX_HEALTH, MAX_STAMINA,
  STAMINA_REGEN, DAMAGE (multiplier, base 1), ARMOR, MOVE_SPEED
  (multiplier, base 1).
- `StatBlock` (`scripts/stats/stat_block.gd`): base `max_health`,
  `max_stamina`, `stamina_regen`, `armor`. The player's is
  `resources/stats/player_stats.tres` (100 / 100 / 30 / 0); `EnemyStats`
  extends it.
- `StatModifier` (`scripts/stats/stat_modifier.gd`): `stat`, `kind` (FLAT /
  PERCENT / MULTIPLY), `value`; `StatModifier.make()` for code. Final value
  = (base + FLATs) x (1 + PERCENTs) x MULTIPLYs, never below 0.
- `CharacterStats` (`scripts/stats/character_stats.gd`, node `Stats` on the
  player and the enemy knight scene): `base`, modifiers by source
  (`set_modifiers(source, list)`, `remove_modifiers()`, `get_modifiers()`),
  `get_value(stat)`, `get_base_value()`, `stats_changed`. `recalculate()`
  pushes MAX_HEALTH -> `HealthComponent.max_health` (rounded; full stays
  full, otherwise clamped), MAX_STAMINA / STAMINA_REGEN -> StaminaComponent,
  DAMAGE -> `MeleeAttackComponent.damage_scale`, ARMOR ->
  `HurtboxComponent.damage_reduction` = armor / (armor + 100) (50 armor:
  33% less). The hurtbox applies it after dodge and block checks; a hit
  always does at least 1. MOVE_SPEED is read by the controllers: the
  player's `_top_speed()` (run, sprint, walk; weapon speed overrides are
  scaled too) and the enemy's `stats.move_speed`.
- Gear: `GearDefinition.modifiers`; the player's Equipment sets them as
  source `&"gear"` on every change (see Equipment).
- Debug menu: the player's final stats at the top of the panel
  (`DebugMenu.stats_text()`).
- `tests/stats_test.gd`: modifier maths and pushes; the player's base;
  gear armor reducing a hit, removed with the gear; max health and +20%
  move speed on the real player; enemy bases (defaults, the imp's .tres),
  elite x2 health / x1.5 damage, enemy armor.

## Stamina

- `StaminaComponent` (`scripts/components/`, node `Stamina` on the player and
  enemies): `max_stamina`, `current_stamina`, `regen_rate` per second after
  `regen_delay` seconds without spending. `spend(amount)` pays for an action
  (refused while `can_act()` is false); `drain(amount)` is the per-tick cost
  of sprinting. Signals: `stamina_changed(current, maximum)`, `exhausted`,
  `recovered`. `infinite` (debug) makes everything free.
- Exhaustion: an action is allowed whenever stamina is above 0 and the owner
  isn't exhausted, even if it costs more than what's left (the pool bottoms
  out at 0). Reaching 0 sets `is_exhausted`: no attacks, dodges or sprint
  until it regenerates to `recover_threshold` (25%) of the maximum.
- Who pays: `MeleeAttackComponent.stamina` (each attack pays
  `AttackProfile.stamina_cost` on start/chain; `can_afford()`),
  `DodgeComponent.stamina` (`stamina_cost` per roll; `is_ready()` is false
  while exhausted, so a roll never cancels an attack's recovery it can't
  follow up), and the player's sprint (`sprint_stamina_per_second`, 15/s;
  exhaustion turns `sprint_toggled` off). Jumping is free.
- Costs (`stamina_cost` in `resources/combat/`): light swings 12 by default
  (combo finisher 16), Cleave 28, Dash Strike 20; greatsword chain 14–22,
  Whirlwind 30, Slide Strike 26, Leaping Slam 32; dodge 18. Knights: club
  swing 15, knight dash 22, greatsword slash 18 / leap 26.
- Player: 100 stamina, 30/s regen after 0.6 s (component defaults).
- Enemies (through their CharacterStats): `EnemyStats.max_stamina` (60) and `stamina_regen` (8/s, after
  0.8 s). An exhausted enemy within `attack_range` holds its ground facing
  the target instead of swinging, and won't dash, until it recovers — a
  punish window. Elite multipliers don't scale stamina.
- UI: the HUD's yellow `StaminaBar` under the health bar (dimmed while
  exhausted); enemies get a thin yellow `WorldStaminaBar` under their health
  bar, hidden at full stamina, faded while exhausted.

## Healing flasks

- `FlaskComponent` (`scripts/components/`, node `Flask` on the player):
  `max_charges` 3, each drink restores `heal_fraction` 35% of max health
  (`heal_amount()`, 35 at 100 max). A drink is a committed action of
  `duration` 1.1 s; the health comes back at `heal_time` 0.6 s, and only
  then is the charge spent. `cancel()` before that (stagger, death) wastes
  the time but keeps the charge. `can_drink()`: a charge left, not already
  drinking, alive and hurt (a drink at full health is refused). Charges
  refill whenever the run moves to a new level (`GameRun.level_changed`,
  `refill_on_new_level`). Signals: `charges_changed(current, maximum)`,
  `started`, `drank(amount)`, `interrupted`.
- Player (`PlayerController.request_flask()`, "use_flask" = R): buffered for
  `input_buffer_time`, starts when grounded and not attacking, rolling,
  staggered or already drinking. While drinking the character stands still
  with its facing locked, and doesn't attack, roll, jump or sprint (those
  presses still buffer); starting a drink ends sprinting. A staggering hit
  or death cancels it.
- Animation: the asset library has no drinking clip; `UAL2/Consume` (a
  palm-up "use an item" gesture, fitted to 1.1 s) stands in. A small
  glowing flask (`LeftHand/FlaskProp`, a BoneAttachment3D on `hand_l` in
  player.tscn) shows in the raised hand only while drinking (`prop`).
- Feedback: the HUD's `FlaskLabel` ("Flasks 2 / 3 [R]", dimmed at 0) above
  the health bar; `DamageNumbers` pops a green "+35" on `healed` (for every
  character with damage numbers).
- `tests/flask_test.gd`: heal amount and timing, rooted, one charge, no
  attack / roll during it, refused at full health / no charges, a real
  staggering hit interrupts it and keeps the charge, refill on a new
  level, R bound to both actions, the HUD label.

## Gold and pick-ups

- `PlayerProfile` (`scripts/run/player_profile.gd`, autoload "Profile";
  scripts reach it with `PlayerProfile.current()`, like GameRun): what the
  player keeps across runs and play sessions. Now `gold` (`add_gold()`,
  never below 0; signal `gold_changed(total, delta)`); the inventory joins
  it later. Saved as JSON to `save_path` (`user://profile.json`) on every
  change, loaded on start. When a script runs as the main loop (`-s`: the
  test suites and tools) the autoload neither saves nor loads, so tests
  never touch the real save. Unlike RunState nothing in it resets on death
  or a new run.
- `ItemDefinition` (`scripts/items/item_definition.gd`, `.tres` in
  `resources/items/`): `id`, `display_name`, `kind` (CURRENCY / GEAR),
  `auto_collect`. `gold.tres` is the first.
- `Pickup` (`scripts/items/pickup.gd`, Area3D on the `interactable` layer,
  group `pickups`): an item and an `amount` lying in the world, built in
  code (currency: a spinning, bobbing gold coin, slightly emissive;
  anything else: a placeholder glowing sack until gear has models). `launch(from, velocity, floor_y)` pops it out in an arc (no
  physics body; one small bounce). After `collect_delay` 0.45 s an
  `auto_collect` item within `magnet_radius` 3.5 m (horizontal) of the
  player flies to their chest, accelerating 4 -> 16 m/s, and is collected
  within 0.5 m: currency goes to the profile, a placeholder "ching" plays
  (`PlaceholderSfx.coin()`), `collected(pickup, collector)` is emitted. Gear
  will wait for the interact key (later step).
- `DropComponent` (`scripts/items/drop_component.gd`, node `Drops` on the
  knight): on `health.died` rolls its `loot` table for `level` and hands
  the result to `LootSpawner` (a ring from 1 m up). Pickups go into the
  first node of group `drop_container` (Main's current level, so they are
  freed with it), else next to the owner. `rng_seed` (0 = random) makes
  drops repeatable. Main gives each spawned enemy its `EnemyEntry.loot`,
  the level and a seed from the level seed, level and spawn index; enemies
  spawned by other means (debug F2) keep the scene's club-knight table.
- HUD: `GoldLabel` ("Gold N") under the level title, pulsing on each gain.
- `tests/gold_test.gd`: save / load / floor at 0 on a scratch profile file,
  a drop's coins (count, total, pop, landing, seeded), coins wait out of
  reach then fly in and add to the profile, no coin behind a wall, Main's
  per-entry gold and seeds, the HUD label.

## Loot

- `LootTable` / `LootEntry` (`scripts/items/`, `.tres` in
  `resources/loot/`): every `guaranteed` entry drops on its own `chance`;
  then `rolls` picks are made from `weighted` by `weight`, with
  `nothing_weight` the share of a pick that gives nothing. An entry's
  `amount` (x..y) grows by `per_level` (a fraction per level above the
  first). `roll(rng, level)` returns `[[item, amount], ...]`, one line per
  item; `LootTable.gold_only(low, high)` builds a quick table. Items are
  fixed (no rarity tiers or rolled stats). Until gear exists (equipment
  step) the tables hold only gold:

  | Table | Drops |
  |---|---|
  | `club_knight` | 3-6 gold, +15%/level |
  | `greatsword_knight` | 6-10 gold, +15%/level |
  | `warden_boss` | 60-80 gold |
  | `chapter_boss` | 120-150 gold |
  | `chest` | 15-30 gold +20%/level, and 1 in 3 a bonus 10-20 (+20%/level) |

- `LootSpawner` (`scripts/items/loot_spawner.gd`, static): turns a roll
  into Pickups popping out from a point: currency as coins of up to 5
  (at most 8 per line), anything else one pickup per line; in a ring or a
  fan (`direction`, `spread`). A throw that a ray says would cross a wall
  (world layer) is shortened to land 0.4 m in front of it.
- `Interactor` (`scripts/components/interactor_component.gd`, node
  `Interactor` on the player): every tick focuses the nearest node of group
  `interactables` within `reach` 1.8 m (horizontal) whose `can_interact()`
  is true (`focus`, signal `focus_changed`). `try_interact()` plays the
  target's `interact_animation()` fitted to `duration` 1.1 s (`is_busy()`
  meanwhile) and calls `interact(player)`. An interactable is any Node3D in
  the group with `can_interact()`, `interact_prompt()`, `interact(by)` and
  optionally `interact_animation()`. Disabled on death.
- Player: "interact" (F) is buffered like the other presses (0.3 s) and
  used when free on the floor (not attacking, rolling, staggered,
  drinking); the character turns to the target and is committed for the
  interaction like a drink (no moving, attacking, rolling, jumping;
  sprint ends). A staggering hit cancels the animation (what already
  happened stays).
- `Chest` (`scripts/items/chest.gd`, a StaticBody3D): the `chest` prop.
  DungeonBuilder builds it with its lid under a `Lid` hinge at the back top
  edge and sets `level` (the layout's) and `rng_seed` (from the layout seed,
  level and chest index), so a level's chests always hold the same.
  `interact()` opens it once: the opener plays `UAL2/Chest_Open`, the lid
  swings back 105 deg (from 0.3 s), and at 0.7 s `loot`
  (`resources/loot/chest.tres`) is thrown out of the front (the lock side,
  local +Z) in a +-55 deg fan. Then it leaves the interactables group.
- HUD: `InteractPrompt` ("[F]  Open chest", bottom centre) while something
  is in focus.
- `tests/loot_test.gd`: chance and weight odds over thousands of rolls,
  per-level growth, seeded rolls, the shipped tables drop their own
  amounts; a built chest is focused in reach, F turns the player to it,
  plays the clip, keeps them still, opens the lid, throws the level-4 gold
  out of the front and the player collects it; it can't be reused; no use
  out of reach, mid-swing (the press expires) or dead; the HUD prompt.

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
- Curvature (step 7): levels are planned on the straight grid but built
  bent. Nothing in cell space changes (rooms, props, spawns, walking,
  RoomAnalysis); only where things land in the world and the shape of the
  walls.
  - `DungeonLayout.curvature` (0..1, default 1) and `curvature_seed()` (the
    level seed, else the map path, else the outline). `to_world()` applies
    `warp()`: per world axis three sine waves along random directions,
    base wavelength 12-20 cells, amplitude 0.55-0.9 cells, capped so the
    warp's slope stays under `WARP_MAX_SLOPE` 0.3 (it never folds; a
    passage is squeezed to 70% at the very worst). `warp_rotation()` turns
    props with the walls. Everything that goes cell -> world (builder, Main's
    spawns, tests) already goes through `to_world()`.
  - `DungeonBuilder` smooths the outline in cell space before warping it:
    every corner becomes an arc (radius 0.7-1.7 cells x curvature, at most
    0.45 of the shorter neighbouring edge), except within 1 cell of a door
    or an interior wall's end; a corner whose arc cuts into the floor keeps
    `MIN_PASSAGE` 0.8 cells to the wall across (measured along its
    bisector), so a corridor bend is never pinched below the navmesh
    agent's width; straight runs are cut into 0.5-cell pieces
    (so the warp bends them); then the outline is pushed outward (never into
    a room) by up to 0.32 cells in two waves along the wall (3.6 and 1.7
    cells), fading out near doors and partition ends: hewn rock.
    `smoothed_outline(layout)` returns it (tests).
  - Floor: whole cells away from the walls, 0.2-cell squares near them,
    reaching 0.15 cells under the wall; UV = the unbent grid position (m),
    which `shaders/dungeon_floor.gdshader` uses for flagstones (1.25 x
    0.85 m, shifted rows, tinted, grooved mortar), so the courses curve
    with the rooms. Walls: inner face on the outline, outer face 0.6 m
    out, a top; partitions centred on their line with end caps. Floor and
    walls are each one mesh with one `ConcavePolygonShape3D` (both sides
    solid), which the navmesh bakes from.
  - Blocking props are pushed straight out of a rounded corner until their
    footprint (`PROP_RADIUS`) clears the wall. Torches go every 5 cells of
    outline on stretches that bend less than 25°, clear of doors.
  - Door frames: posts and lintel at `DOOR_HEIGHT` 3 m between the warped
    ends of the gap, and wall over the doorway up to the wall top.
  - Atmosphere: ambient 0.4, fill light 0.32, stronger SSAO (radius 1.6,
    intensity 2.5) and glow: the torches carry the light.
  - Cost: dungeon_01 builds in ~0.14 s (was 0.013 s), generated levels in
    ~0.2 s; the bake is unchanged (~0.02 s). `tests/dungeon_builder_test.gd`
    test 4: warp moves points, is seeded, never squeezes past the cap; the
    outline curves (vs 4 headings at curvature 0); a corner crate is moved
    clear; the curved level bakes and is walkable.
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
    (poise, knockback / detection), the `Visual` scale, its own copies of
    the body and hurtbox capsules, health bar / damage numbers height, nav
    agent size, reach (`attack_range`, dash ranges), root-motion lunge, and
    the ragdoll's death throw (÷ size). Health and damage are MULTIPLY
    modifiers (source `&"elite"`) on its CharacterStats, which push
    `max_health` and `MeleeAttackComponent.damage_scale`. Bosses are elite knights until they get their own
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
- Floor and walls: meshes with trimesh colliders built along the smoothed,
  warped outline (see Levels, Curvature); walls 4.2 m on the void side of
  the outline, all full height (the camera orbits; the wall shader cuts
  them away on the camera's side of the player). Torches every 5 cells of
  outline.
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
assets/characters/outfits/           Modular Character Outfits - Fantasy: Peasant / Ranger, male and female (CC0)
assets/characters/monsters/          Bestiary - Dungeon Monsters Kit: Imp, Puglin (CC0)
assets/equipment/gear/               Helmet (CC-BY); CREDITS.md
assets/equipment/shield/             Wooden shield + trim textures (Quaternius Fantasy Props MegaKit, CC0)
resources/items/gear/                Equippable items (outfit pieces, helmet, shield, amulet, rings, charm); resources/items/catalog.tres lists them with the weapons
resources/characters/                CharacterAppearance .tres files
(unused)                             knight_rig.tscn, build_knight_rig.gd, knight_post_import.gd, assets/characters/knight/
assets/equipment/                    Weapon and armour FBX meshes
scenes/camera/iso_camera_rig.tscn    Follow camera: overview -> third-person zoom, orbit
scenes/ui/hud.tscn                   Player health bar, "Defeated" + restart hint
scenes/debug/debug_menu.tscn         F1 debug panel
scenes/debug/outfit_menu.tscn        Outfits panel (opened from the debug panel)
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
scripts/world/fog_of_war.gd          FogOfWar: unexplored / explored / visible cells, enemy hiding (+ shaders/fog_of_war.gdshader)
scripts/run/run_state.gd             RunState autoload (class GameRun): the current run
scripts/run/player_profile.gd        Profile autoload (class PlayerProfile): gold (later inventory), kept across runs, saved
scripts/items/                       ItemDefinition, GearDefinition, OutfitPieceDefinition, ShieldDefinition, Equipment, Inventory, ItemCatalog, Pickup, DropComponent, LootTable / LootEntry, LootSpawner, Chest
scripts/ui/inventory_screen.gd       InventoryScreen (I) + item_slot.gd (one cell)
resources/items/                     ItemDefinitions (gold)
resources/loot/                      LootTables (enemies, bosses, chests)
scripts/ui/level_fade.gd             LevelFade: fade + level title over level swaps
scripts/world/prop_scatter.gd        PropScatter: route reservation + prop rules
scripts/world/encounter_planner.gd   EncounterPlanner: enemy budget and placement
scripts/world/enemy_roster.gd        EnemyRoster / enemy_entry.gd EnemyEntry: data for the planner
resources/encounters/                Rosters and enemy entries
scripts/ui/damage_numbers.gd         Floating combat numbers
scripts/components/                  health, stamina, flask, interactor, hitbox, hurtbox, melee attack, dodge, block, hit flash components
scripts/combat/                      AttackProfile, HitEvent, HitReactionComponent, ImpactFeedbackComponent, Hitstop, WeaponDefinition, WeaponComponent
scripts/vfx/                         ImpactEffect (placeholder), WeaponTrail
scripts/audio/placeholder_sfx.gd     Synthesised stand-in hit/whoosh sounds
resources/combat/                    AttackProfiles: player sword (combo A/B/C, cleave, dash; slash and rising cut unused), greatsword (gs_*), knights (club swing, dash, gs_knight_*)
resources/weapons/                   WeaponDefinitions: sword, club, greatsword
tests/combat_test.gd                 Headless combat checks: godot --headless --path . -s res://tests/combat_test.gd
tests/*_test.gd                      Also camera, dodge, lock_on, enemy, movement, weapon, dungeon_builder, level_generator, population, run and map_pool suites (same command, other file), plus stamina_test.gd
tests/lock_on_test.gd                Headless lock-on / attack-direction checks (same command, lock_on_test.gd)
scripts/player/player_controller.gd
scripts/player/lock_on_component.gd  Enemy lock-on (Q / Tab) and target marker
scenes/enemies/enemy_knight.tscn     Melee enemy (ash-skinned humanoid + club)
scenes/enemies/enemy_imp.tscn        Imp (inherits the knight scene)
scenes/enemies/enemy_puglin.tscn     Puglin (inherits the knight scene)
scripts/enemies/                     enemy_controller.gd, enemy_stats.gd
scripts/stats/                       StatBlock, StatModifier, CharacterStats (core stats + modifiers)
resources/stats/                     player_stats.tres (the player's base StatBlock)
resources/enemies/                   EnemyStats and enemy CharacterAppearance .tres files
resources/navigation/                Baked navmeshes
shaders/billboard_bar.gdshader
shaders/wall_cutout.gdshader         Walls, door frames, torches, pillars: cut away on the camera side of the player
shaders/dungeon_floor.gdshader       Flagstone floor (UV = unbent grid position, so it curves with the level)
scripts/ui/world_health_bar.gd
scripts/ui/world_stamina_bar.gd      Enemy stamina bar (same billboard shader, yellow fill)
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
