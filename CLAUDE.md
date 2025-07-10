# Modular Synthesizer GUI Project

This Phoenix LiveView application provides a graphical interface for creating and editing modular synthesizer networks.

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

## Key Features

- Dynamic node connection system with click-to-click interaction
- Port labels showing actual parameter names (freq, gain, in, out, etc.)
- Precise cable routing to specific connection points
- Real-time parameter extraction from backend definitions
- File loading/saving for synthesizer networks
- Integration with SuperCollider for audio playback

## Development Commands

- `mix phx.server` - Start the development server
- `mix compile` - Check compilation
- `mix assets.build` - Build JavaScript/CSS assets

## File Structure

- `lib/modsynth_gui_phx_web/live/synth_editor_live.ex` - Main GUI component
- `lib/modsynth_gui_phx/synth_manager.ex` - Backend integration
- `assets/js/synth_canvas.js` - Canvas interaction handling
- `../sc_em/examples/` - Example synthesizer networks
- `../sc_em/lib/` - Backend synthesizer engine