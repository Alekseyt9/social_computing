# Adaptive Social Immersive Sim

An experimental single-player **social immersive sim** built with Godot 4. The
player is not an overseer managing society from above, but an ordinary
participant in a living social world. Goals are achieved through connections,
trust, information, reputation, favors, and organizations.

The first vertical slice revolves around gaining access to a private **Aurora**
party. There is no single predefined solution: the player must investigate
relationships, negotiate, help people, and discover alternative social paths.

[![Three social paths to the private Aurora party](docs/diagrams/aurora-social-paths.svg)](docs/diagrams/aurora-social-paths.svg)

## Gameplay Loop

The player does not press an abstract persuasion button. They learn why someone
is unwilling to help, change the relationship or circumstances, and try a new
path.

[![Social Immersive Sim gameplay loop](docs/diagrams/gameplay-loop.svg)](docs/diagrams/gameplay-loop.svg)

## Core Principles

- world state and character knowledge are stored separately;
- NPC decisions are computed by a deterministic simulation, not by an LLM;
- the **Social Renderer** turns a structured decision into natural dialogue;
- Groq controls only the wording and cannot change world state;
- agent detail adapts from population groups down to active NPCs;
- the simulation runs headlessly and is reproducible from a seed.

```text
World → Social Simulation → NPC Decision → Communicative Act
      → Social Renderer → LLM or template → Player-visible dialogue
```

[![Social Rendering architecture](docs/diagrams/social-rendering-pipeline.svg)](docs/diagrams/social-rendering-pipeline.svg)

### Adaptive Detail

As entities become more relevant to the player and the current situation,
aggregates refine into individual agents. In the other direction, detail is
coarsened without losing important history or persistent identity.

[![Adaptive social simulation levels](docs/diagrams/adaptive-simulation-levels.svg)](docs/diagrams/adaptive-simulation-levels.svg)

## Current Prototype

Implemented so far:

- deterministic `SimulationWorld` core;
- the player, 20 NPCs, an Office, a Cafe, and an Apartment;
- models for people, organizations, relationships, facts, knowledge, and events;
- separation between canonical truth and information available to the player;
- the Aurora scenario with several potential social routes;
- `AskAbout`, `AskFavor`, and guarded preconditions for `AskIntroduction`;
- a deterministic Decision Engine with a numerical explanation of its reasons;
- Disclosure, CommunicativeAct, and a local template renderer;
- Groq rendering for regular dialogue with semantic validation and fallback;
- a top-down 2D district with solid buildings, a following camera, and moving NPCs;
- proximity dialogue: walk up to a character and press `E` to talk or introduce yourself;
- a walking-skeleton interface and headless tests.

The next milestone covers trust-changing actions, unlocking
`AskIntroduction`, an NPC decision debug inspector, and a map of relationships
known to the player.

## Project Structure

```text
game/core/        deterministic simulation and world models
game/llm/         isolated Groq provider
game/world/       2D map, player controller, and NPC movement
game/ui/          in-world HUD and conversation panel
game/tests/       headless and integration tests
docs/             near-term development plan
scripts/          local launcher with environment variables
```

Full technical specification: [adaptive_social_immersive_sim_codex_spec.md](adaptive_social_immersive_sim_codex_spec.md).

## Running the Project

Requires Godot 4.7+.

For a double-click launch, open the `game` folder and run `START_GAME.cmd`. It
automatically loads the local `.env` through the main launch script.

Controls: `WASD` or the arrow keys to walk, `E` to start or close a nearby
conversation, and `Esc` to close the dialogue panel. The camera follows the
player; buildings and the edge of the district block movement.

The simplest way to start the game from PowerShell at the repository root is:

```powershell
.\scripts\run-godot.ps1
```

Open the project in the editor:

```powershell
.\scripts\run-godot.ps1 -Editor
```

In the editor, press **F6** to run the current scene or **F5** to run the full
project. Groq is optional: without an API key, the game uses the local template
renderer.

Direct launch without the helper script:

```powershell
godot --path ./game
godot --editor --path ./game
```

Run the deterministic simulation test:

```powershell
godot_console --headless --path ./game --script res://tests/headless_test.gd
godot_console --headless --path ./game --script res://tests/world_scene_test.gd
```

## Groq API

Copy the example configuration and add your key only to the local `.env` file:

```powershell
Copy-Item .env.example .env
.\scripts\run-godot.ps1 -Editor
```

```dotenv
GROQ_API_KEY=gsk_...
GROQ_MODEL=openai/gpt-oss-20b
```

The `.env` file is listed in `.gitignore`; a real API key must never be committed
to Git or included in logs or messages. Run the live integration test with:

```powershell
godot --headless --path ./game --script res://tests/groq_integration_test.gd
```
