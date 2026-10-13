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

## Layout

```
scenes/main/main.tscn            Entry scene: arena + player + camera rig
scenes/world/test_arena.tscn     Prototype arena (ground, walls, obstacles, lighting)
scenes/player/player.tscn        CharacterBody3D with placeholder capsule
scenes/camera/iso_camera_rig.tscn
scripts/player/player_controller.gd
scripts/camera/iso_camera_rig.gd
```

Planned (not yet implemented): health/hitbox/hurtbox components, enemy AI with
NavigationRegion3D, HUD, data-driven stat resources.
