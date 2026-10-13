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
| `zoom_in/out`  | Mouse wheel        | Orthographic zoom. |

## Physics layers

| # | Name           | Used by |
|---|----------------|---------|
| 1 | world          | Ground, walls, obstacles |
| 2 | player         | Player body |
| 3 | enemy          | Enemy bodies |
| 4 | player_hurtbox | Areas that receive damage on the player |
| 5 | enemy_hurtbox  | Areas that receive damage on enemies |
| 6 | interactable   | NPCs, loot, objects |

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

## Layout

```
scenes/main/main.tscn                Entry scene: arena + player + camera rig + HUD
scenes/world/test_arena.tscn         Prototype arena (ground, walls, obstacles, lighting, hazards)
scenes/world/hazards/spike_trap.tscn Test hazard: 10 damage/s to the player
scenes/player/player.tscn            CharacterBody3D, placeholder capsule, health, hurtbox
scenes/camera/iso_camera_rig.tscn
scenes/ui/hud.tscn                   Player health bar, "Defeated" message
scripts/components/                  health, hitbox, hurtbox components
scripts/player/player_controller.gd
scripts/camera/iso_camera_rig.gd
scripts/ui/hud.gd
```

Planned (not yet implemented): enemy AI with NavigationRegion3D, player attack,
floating combat text, restart after death, data-driven stat resources.
