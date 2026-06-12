# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

MergeGame is a Godot 4 merge-style game. 7×9 grid, drag to merge same-level items, click launchers to spawn items. All items driven by JSON config tables.

## Design Document

See `docs/设计文档.md` for full architecture, config schemas, signal map, and implementation phases.

## Key Architecture

- **All UI is Control-based** (no Node2D/Sprite2D) — items use TextureRect, replace textures for re-skinning
- **Config-driven**: `config/items.json` defines all items with weighted spawns, `config/game_config.json` for game parameters, `config/initial_setup.json` for starting board layout
- **Autoload singletons** (in initialization order): ConfigDatabase → GridManager → GameState → MergeService → SaveManager
- **Single merge, no chain reaction** — one drag-drop triggers one merge
- **Input handling**: GridView uses `_input()` for drag-and-drop across the full game area

## Project Structure

```
MergeGame/
├── config/          # JSON config tables
├── autoload/        # 5 autoloaded singletons
├── scenes/
│   ├── Main.tscn    # Root scene
│   ├── grid/        # GridView, GridCell
│   ├── items/       # GridItem (TextureRect)
│   ├── ui/          # TopBar, BottomPanel, Overlay
│   └── effects/     # Merge/Spawn effects (not yet created)
├── scripts/utils/   # Constants, GridUtils
├── docs/            # Design documentation
├── assets/          # Art/audio (to be added)
└── tests/           # Unit tests (not yet created)
```

## Godot Conventions

- **Language**: GDScript (`.gd` files)
- **Naming**: snake_case for variables/functions, PascalCase for enums and class names
- **Indentation**: tabs (Godot default)
- **Strict typing**: Never use `var x := dict.get(...)` because `Dictionary.get()` returns `Variant`, which triggers "variable type inferred from Variant" error in strict mode. Always annotate explicitly: `var x: Type = dict.get(...)`.

## Commands

```bash
# Open / run project
godot4 --path .
```

## Development Notes

- All items defined in `config/items.json`. To add a new item: add entry to `regular` or `launcher` array with numeric ID.
- Launcher spawn tables use `spawns: [{id, weight}]` — weights are relative, not percentages.
- To replace art: set `icon` path in items.json to a texture in `assets/` directory.
- Save data uses `user://` path. High score auto-saves.
