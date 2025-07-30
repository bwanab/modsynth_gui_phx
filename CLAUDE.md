# Modular Synthesizer GUI Project

This Phoenix LiveView application provides a unified interface for creating and editing modular synthesizer networks with integrated script-based music composition capabilities.

## Project Scope

**Important**: This project includes both the current directory and the adjacent `../sc_em` directory:
- `/Users/bill/src/modsynth_gui_phx` - Phoenix LiveView GUI application
- `/Users/bill/src/sc_em` - SuperCollider backend with synthesizer definitions and examples

The `sc_em` directory contains:
- Node type definitions and parameter specifications
- Example synthesizer networks (JSON files)
- SuperCollider integration and audio engine
- Core synthesizer modules and their implementations

When working on this project, always consider both directories as part of the same system. The GUI depends heavily on the backend for node definitions, parameter information, and audio processing.

## Architecture

The GUI reads synthesizer definitions and parameter information dynamically from the `sc_em` backend using `Modsynth.look()`, ensuring that new node types added to the backend automatically appear in the GUI without requiring frontend code changes.

The application features a **unified tabbed interface** that seamlessly integrates visual synthesizer construction with algorithmic music composition, providing real-time feedback and control over both paradigms.

## Key Features

### Visual Synthesizer Editor
- Dynamic node connection system with click-to-click interaction
- Port labels showing actual parameter names (freq, gain, in, out, etc.)
- Precise cable routing to specific connection points
- Real-time parameter extraction from backend definitions
- Interactive control knobs with drag-to-adjust functionality
- Enhanced Node Info dialog with editable parameters for `const` and `cc-in` nodes
- Real-time bus value display with smart formatting during playback
- Edit/Run mode switching with context-sensitive UI controls

### STrack Script Editor
- Monaco Editor integration with Elixir syntax highlighting
- Real-time code execution and validation with error display
- Prelude script system with C-style include functionality
- File management with user scripts (`~/.modsynth/strack_scripts/`) and examples
- Live script playback integration with synthesizer backend
- Musical helper functions for arpeggios, chord progressions, and sequences

### Unified Interface
- Tab-based navigation between Synth Editor and Script Editor
- Shared synthesizer state and playback controls
- File loading/saving for both synthesizer networks and music scripts
- Integration with SuperCollider for audio playback
- MIDI device support with virtual port creation
- Cross-format compatibility between visual and script-based workflows

## Development Commands

- `mix phx.server` - Start the development server
- `mix compile` - Check compilation
- `mix assets.build` - Build JavaScript/CSS assets

## File Structure

### Core Application
- `lib/modsynth_gui_phx_web/live/synth_editor_live.ex` - Unified editor with both synth and script functionality
- `lib/modsynth_gui_phx/synth_manager.ex` - Backend integration and playback management
- `assets/js/synth_canvas.js` - Canvas interaction handling for visual editor

### Script Editor Components
- `lib/modsynth_gui_phx_web/live/strack_code_editor_live.ex` - STrack code editor LiveView
- `prelude.exs` - Project-wide helper functions for STrack scripts
- `example_stracks/` - Example STrack scripts (simple_note.exs, pachelbel.exs)

### Backend Integration
- `../sc_em/examples/` - Example synthesizer networks
- `../sc_em/lib/` - Backend synthesizer engine

### User Data
- `~/.modsynth/strack_scripts/` - User-created STrack scripts
- `~/.modsynth/strack_scripts/.prelude.exs` - User-specific prelude functions