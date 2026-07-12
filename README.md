# Claude Settings Manager

Claude Settings Manager is a native macOS desktop app for managing Claude Code settings.json profiles from a single window. It helps switch between different Claude Code configurations without manually editing ~/.claude/settings.json.

## Features

- Manage multiple Claude Code settings profiles.
- Select, edit, save, activate, and launch profiles from one window.
- Edit JSON through a structured GUI instead of raw text.
- Add, update, and delete JSON fields.
- Supports string, number, bool, null, array, and object values.
- Nested object editing with child key and value rows.
- Array editing with independent item type and value controls.
- JSON preview panel for checking generated output.
- Normalizes smart quotes and avoids visible escaped slash characters in the editor.

## Build

Run this from the repository root:

    swift build

The SwiftPM executable is generated under `.build/debug/ClaudeSettingsManager`. Run tests with:

    swift test

SwiftPM does not create a `.app` bundle by itself. A separate packaging or Xcode archive step is required for distribution. Build artifacts such as `.build`, `dist`, and local `.vscode` settings are intentionally excluded from git.

The app reads and writes profiles under `~/.claude`. Existing files are copied to `~/.claude/backups` before replacement. Invalid JSON, invalid numeric values, and profile names without letters or numbers are rejected instead of being silently rewritten.

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

Unsaved changes are protected when switching profiles, and overwriting an existing named profile requires confirmation. Existing files are backed up before replacement.

## Legacy AppleScript

`ClaudeSettingsManager.applescript` is retained as a lightweight legacy alternative. The SwiftUI application is the primary implementation.

## Repository

https://github.com/mabocoglu/claude-settings-manager
