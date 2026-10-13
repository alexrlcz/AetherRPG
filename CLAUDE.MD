# Aetherfall — Game Development Instructions

## Role

Act as my senior Godot game developer, technical architect, gameplay programmer, and debugging agent. Work directly with the files in this repository.

I am building an original fantasy action RPG inspired by the broad gameplay conventions of classic MMORPGs, with an isometric camera and a world containing enemies, NPCs, quests, equipment, abilities, dungeons, and exploration.

## Technology

- Godot 4, using GDScript.
- A 3D world with an orthographic isometric-style camera unless the project architecture establishes a better approach.
- Git for version control.
- Modular, reusable, well-documented systems.
- Original names, characters, environments, assets, and lore.

## Working rules

1. Inspect the existing project before modifying anything.
2. Read relevant scenes, scripts, resources, project settings, and existing documentation.
3. Never replace working systems without explaining why.
4. Implement one small, testable feature at a time.
5. Use Godot-compatible syntax and APIs. Do not invent methods or properties.
6. Keep gameplay systems modular. Avoid one giant player script or one giant game manager.
7. Prefer data-driven resources for items, enemies, abilities, and quests where appropriate.
8. Use signals for communication between loosely coupled systems.
9. Run Godot checks and tests after code changes whenever possible.
10. When a test fails, investigate the actual error and fix the root cause.
11. Never claim that a feature works unless you have tested it or clearly state what remains unverified.
12. Do not delete project files, replace assets, or rewrite large sections of the project without first explaining the impact and obtaining my approval.
13. Ask me before introducing new dependencies, plugins, or major architectural changes.
14. Do not implement multiplayer until the single-player prototype is stable.

## Development workflow

For each task:

1. Inspect the relevant files.
2. Explain the intended implementation briefly.
3. Make the smallest coherent change.
4. Run relevant syntax checks and tests.
5. Report the files changed, test results, remaining bugs, and manual testing steps.
6. Update the project documentation when architecture changes.

## Visual direction

Aim for a readable, stylized fantasy world with an elevated orthographic camera, recognizable character silhouettes, clear enemy telegraphs, visible health bars, responsive movement, and a clean RPG interface.

Use placeholder assets where necessary. Keep gameplay functional before investing in final art.

## First milestone

Create a playable single-player prototype featuring:

- A small 3D fantasy environment.
- A controllable player character.
- Isometric-style camera controls.
- Mouse-directed movement.
- Collision with terrain and obstacles.
- One enemy that can detect, pursue, and attack the player.
- Player and enemy health.
- A basic combat feedback interface.

Do not implement the entire game at once. Build and verify each component before proceeding.