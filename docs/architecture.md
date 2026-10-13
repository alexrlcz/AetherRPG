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
  Frees itself in non-debug builds (`OS.is_debug_build()`).

## Character visuals and animation

- Model: `assets/characters/knight/KnightCharacter.fbx` (rigged, 12 animations,
  flat-colour materials). Its post-import script
  `tools/import/knight_post_import.gd` bakes the FBX's ×100 armature scale and
  the 0.32 character scale into the skeleton, mesh and animation keys, so every
  node is at scale 1 and the knight is ~1.8 m tall (required for physics).
- `scenes/characters/knight_rig.tscn` = the FBX + ragdoll + `RightHand`
  attachment. It is **generated** by `tools/build_knight_rig.gd` (bone table
  at the top of that file); re-run it instead of hand-editing:
  `godot --headless --path . -s res://tools/build_knight_rig.gd`.
- Player and enemy instance the rig at `Visual/Model`, rotated 180° because
  the FBX faces +Z while gameplay forward is -Z. Weapons are children of
  `RightHand` (bone `Palm.R`) with scale 0.32 because the weapon FBXs are
  still in their original units.
- `CharacterAnimator` (`scripts/characters/`, node `Animator`) is shared by the
  player and enemies. It observes the body's velocity and its HealthComponent:
  idle / run (scaled by speed, reversed when moving against the facing
  direction). Gameplay calls `play_action(anim, speed)` for one-shots such as
  attacks. Idle and run are set to loop at runtime because the FBX import does
  not. `death_animation` is empty because the ragdoll handles death.

## Ragdoll

- 12 `PhysicalBone3D`s (pelvis, abdomen, chest, head, upper/lower arms and
  legs) under `Skeleton3D/PhysicalBoneSimulator3D`, capsule shapes, cone joints
  with swing/twist limits, layer 7 `ragdoll`, mask `world`.
- The feet are IK bones parented to the root, not to the shins.
  `RagdollLimbFollow` (a `SkeletonModifier3D` after the simulator, active only
  while ragdolling) glues `Foot.L/R` to `LowerLeg.L/R_end`.
- `RagdollComponent` (node `Ragdoll`) listens to `HealthComponent.died`: it
  freezes the AnimationPlayer, starts the simulation and gives every bone the
  body's velocity plus a knockback away from the last damage source
  (`knockback_speed`, `knockback_lift`; defaults 3 and 1.5 m/s, enemies use 10
  and 6). `knockback_spin` (rad/s, default 5) adds a backwards flip away from
  the attacker: every bone gets `v + ω × r` about the body centre so the body
  tumbles as one piece; `spin_randomness` varies axis and speed. Corpses stay
  forever.
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
  (within `detection_radius`) -> `ATTACK` (within `attack_range`) and back;
  gives up beyond `lose_interest_radius` or when the target dies. `DEAD`
  disables collision and the hurtbox.
- Attacks go through the enemy's `MeleeAttack` node (`MeleeAttackComponent`),
  configured from `stats` at ready. Facing locks when the wind-up starts so
  the player can sidestep.
- Taking damage while idle switches the enemy to `CHASE` (hit aggro).
- Target = first node in group `player`; aliveness via its `is_dead` property.
- `enemy_knight.tscn`: the knight model recoloured through surface material
  overrides (armour/skin/boots), wielding the Club. Stats:
  `resources/enemies/ashbound_knight.tres`.
- `WorldHealthBar` + `shaders/billboard_bar.gdshader`: camera-facing bar,
  fill via the per-instance shader parameter `ratio`.

## Navigation

- `TestArena/NavigationRegion3D` parents all walkable/blocking static geometry
  (ground, walls, obstacles); hazards stay outside so they don't block paths.
- The navmesh is baked into `resources/navigation/test_arena_navmesh.tres`
  (parses static colliders on layer 1, agent radius 0.5). Re-bake with the
  editor's "Bake NavigationMesh" button after changing the arena.
- The baked mesh sits 0.5 m above the floor, so agents use
  `path_height_offset = 0.5`; without it they never advance past their first
  waypoint.

## Layout

```
scenes/main/main.tscn                Entry scene: arena + player + enemies + camera rig + HUD
scenes/world/test_arena.tscn         Prototype arena (ground, walls, obstacles, lighting, hazards)
scenes/world/hazards/spike_trap.tscn Test hazard: 10 damage/s to the player
scenes/player/player.tscn            CharacterBody3D, knight rig + sword, health, hurtbox, animator, ragdoll
scenes/characters/knight_rig.tscn    GENERATED: knight FBX + ragdoll + hand attachment
scripts/characters/                  character_animator, ragdoll_component, ragdoll_limb_follow, occlusion_silhouette
tools/build_knight_rig.gd            Generates knight_rig.tscn
tools/import/knight_post_import.gd   Bakes the knight FBX to real-world scale on import
assets/characters/knight/            Knight character FBX
assets/equipment/                    Weapon and armour FBX meshes
scenes/camera/iso_camera_rig.tscn
scenes/ui/hud.tscn                   Player health bar, "Defeated" + restart hint
scenes/debug/debug_menu.tscn         F1 debug panel
scripts/main/main.gd                 Restart flow (on the Main node)
scripts/world/enemy_spawner.gd       Random navmesh spawns
scripts/ui/damage_numbers.gd         Floating combat numbers
scripts/components/                  health, hitbox, hurtbox, melee attack, hit flash components
scripts/player/player_controller.gd
scenes/enemies/enemy_knight.tscn     Melee enemy (recoloured knight + club)
scripts/enemies/                     enemy_controller.gd, enemy_stats.gd
resources/enemies/                   EnemyStats .tres files
resources/navigation/                Baked navmeshes
shaders/billboard_bar.gdshader
scripts/ui/world_health_bar.gd
scripts/camera/iso_camera_rig.gd
scripts/ui/hud.gd
```

First milestone complete. Possible next steps: enemy line-of-sight, more enemy
types, equipment, abilities.
