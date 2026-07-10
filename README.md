# Claude Settings Manager

Claude Settings Manager is a native macOS desktop app for managing Claude Code settings.json profiles from a single window. It helps switch between different Claude Code configurations without manually editing ~/.claude/settings.json.

## Features

- Manage multiple Claude Code settings profiles.
- Select, edit, save, activate, and launch profiles from one window.
- Edit JSON through a structured GUI instead of raw text.
- Add, update, and delete JSON fields.
- Supports string, bool, array, and object values.
- Nested object editing with child key and value rows.
- Array editing with independent item type and value controls.
- JSON preview panel for checking generated output.
- Normalizes smart quotes and avoids visible escaped slash characters in the editor.

## Build

Run this from the repository root:

    swift build

The local development app bundle is generated under dist/Claude Settings Manager.app. Build artifacts such as dist and .build are intentionally excluded from git.

## Usage

1. Open Claude Settings Manager.app.
2. Select a profile from the left sidebar.
3. Edit settings in the structured JSON editor.
4. Use Add Field, Create Object, Create Array, Add Child, or Add Array Item depending on the JSON structure.
5. Review the generated JSON in the preview panel.
6. Save or activate the selected profile.

## JSON Editing Model

Objects are key and value groups. Use object children for named settings such as env variables.

Arrays are ordered item groups. Use array items for ordered values without keys.

## Repository

https://github.com/mabocoglu/claude-settings-manager
