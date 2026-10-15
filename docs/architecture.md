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
| `attack`       | Left mouse (hold to repeat) | Turns toward the cursor and swings; facing locked and movement at 40% until the swing recovers. |
| `zoom_in/out`  | Mouse wheel        | Orthographic zoom. |
| `restart`      | R                  | After death (1 s delay): reload the level. |
| `debug_menu`   | F1                 | Toggle the debug panel (debug builds only). |
| `debug_spawn_enemy` | F2          | Spawn an enemy at a random walkable point (debug builds only). |

Attack presses are handled as input events (`_unhandled_input`), so clicks on
UI buttons never trigger a swing. A press is queued until a swing starts, so
very short clicks and clicks made mid-swing are not lost.

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
HitboxComponent (Area3D, mask = target hurtbox layer)
   └─ overlaps ─► HurtboxComponent (Area3D on *_hurtbox layer)
                     └─ receive_hit() ─► HealthComponent.take_damage()
                                            └─ signals: health_changed, damaged, healed, died
```

- `HealthComponent` (Node): `max_health`, `current_health`, `take_damage()`,
  `heal()`, `reset()`. Valid from construction, independent of ready order.
- `HurtboxComponent`: forwards hits to its `health`; emits `hurt(amount, source)`.
- `HitboxComponent`: while `active`, hits each overlapping hurtbox once per
  activation, or every `rehit_interval` seconds if > 0 (hazards, DoT zones).
  `source` defaults to the scene owner.
- Teams are decided purely by physics layers: player attacks mask
  `enemy_hurtbox`, enemy attacks and hazards mask `player_hurtbox`.
- UI (`HUD`) only listens to `HealthComponent` signals.
- `MeleeAttackComponent` runs one attack for anyone: wind-up (optional
  ground telegraph grows) -> strike (hitbox live) -> recovery, plus the attack
  animation, sped up so its impact frame (`animation_strike_time`) lands at the
  end of the wind-up. Signals: `started`, `struck`, `finished`. The owner decides
  when to `start()` and what to do with facing/movement while `is_busy()`.
- Player attack: 20 damage, 0.3 s wind-up, `Run_swordAttack` animation,
  `AttackHitbox` masks `enemy_hurtbox`.

## Combat feedback

- `DamageNumbers` (Node3D placed above the head, `scripts/ui/`): on
  `HealthComponent.damaged` spawns a top-level billboard `Label3D` that rises
  and fades. Colour per character (player red, enemies white).
- `HitFlashComponent`: on damage sets a white unshaded `material_overlay` on
  the listed meshes and fades it out (`duration` 0.15 s); surface material
  overrides (enemy recolour) are untouched.
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
  bodies, hairstyles, beard, eyebrows and the 43 animations all share one
  65-bone UE-mannequin-style skeleton (`pelvis`, `spine_01..03`, `hand_r`, ...),
  ~1.82 m tall, metre units, facing +Z.
- `UAL1_Standard.glb` (no root motion) is imported as an **AnimationLibrary**
  (`importer="animation_library"`). Its post-import script
  `tools/import/ual_post_import.gd` removes position tracks except `root` and
  `pelvis`, and all scale tracks: the animations were authored on a mannequin
  with different bone lengths, so only rotations are applied and each body
  keeps its own proportions. `remove_immutable_tracks` is off so constant
  rotation tracks are kept. Godot strips the `_Loop` suffix on import
  (`Idle_Loop` -> `Idle`, `Jog_Fwd_Loop` -> `Jog_Fwd`).
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
  0.6–1.6x, 0.25 s locomotion crossfades. The cycle plays reversed when moving
  against the facing direction, but only while the body's `is_aiming` is true
  (so momentum during a quick turn doesn't moonwalk). Gameplay calls
  `play_action(anim, speed)` for one-shots such as attacks (restarting it if
  it is already playing); `MeleeAttackComponent` calls `stop_action()` when
  recovery ends so the follow-through doesn't block locomotion. Both attacks
  use `Sword_Attack` (blow lands at 0.37 s). `death_animation` is empty
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
scripts/player/player_controller.gd
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
dungeon level generated from a Dungeon Scrawl map. Possible next steps: more
enemy types, equipment, abilities.
