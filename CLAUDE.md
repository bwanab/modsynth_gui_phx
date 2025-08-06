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

---

# Module GUI Rationalization Plan

**Objective**: Eliminate const/cc-in modules by integrating parameter controls directly into modules as adjustable knobs with preset ranges.

## Current Architecture Analysis

### Pain Points Identified
1. **Screen Clutter**: Simple modules like `adsr-env` require 4 additional const nodes for attack/decay/sustain/release parameters
2. **Setup Overhead**: Each const/cc-in node requires manual min/max/current value configuration  
3. **Repetitive Work**: Similar parameter ranges need to be set repeatedly across projects
4. **Cognitive Load**: Users must manage many small modules instead of focusing on core synthesis logic

### Current System Dependencies

**Backend (../sc_em/lib/modsynth.ex):**
- `is_external_control/1` (line 343-350): Identifies only const/cc-in/midi-in as controllable
- Control setup (line 252-268): Creates `InputControl` records only for external control modules
- MIDI handling (line 280-311): Special cc-in gain logic for CC2/CC7 volume control
- Parameter extraction relies on `Modsynth.get_synth_vals/1` reading compiled synthdefs

**Frontend:**
- Node Info dialogs provide parameter editing for const/cc-in only
- `ControlKnob` JavaScript hook handles real-time value adjustment
- Visual styling distinguishes const (orange) vs cc-in (purple) modules
- Connection system routes to specific parameter ports

## Proposed New Architecture

### 1. Integrated Parameter Controls
**Replace**: Separate const/cc-in modules for each parameter  
**With**: Direct knob controls on each module for adjustable parameters

**Example - Current adsr-env setup:**
```
[const] -> [adsr-env.attack]
[const] -> [adsr-env.decay] 
[const] -> [adsr-env.sustain]
[const] -> [adsr-env.release]
```

**Example - New adsr-env setup:**
```
[adsr-env] with 4 integrated knobs: attack, decay, sustain, release
```

### 2. Parameter Preset System
Create comprehensive parameter defaults based on SuperCollider documentation and practical experience:

**ADSR Envelope:**
- attack: 0.01-2.0s (default: 0.1s)
- decay: 0.01-2.0s (default: 0.2s) 
- sustain: 0.0-1.0 (default: 0.7)
- release: 0.01-5.0s (default: 1.0s)

**Filters:**
- freq: 20-20000Hz (default: 1000Hz)
- res: 0.1-10.0 (default: 1.0)
- gain: 0.0-2.0 (default: 1.0)

**Oscillators:**
- freq: 20-20000Hz (default: 440Hz)
- amp: 0.0-1.0 (default: 0.5)
- phase: 0.0-2π (default: 0.0)

### 3. amp vs gain Module Resolution
**Problem**: Current amp module serves dual purposes (fixed gain + MIDI control)  
**Solution**: Create distinct modules

**amp module**: Keep current behavior - fixed gain control only
```supercollider
SynthDef("amp", {arg in = 0, out_audio = 0, gain = 0.5;
    Out.ar(out_audio, In.kr(gain) * In.ar(in));
}).writeDefFile(~dir);
```

**gain module**: New module with integrated MIDI CC2/CC7 handling
```supercollider  
SynthDef("gain", {arg in = 0, out_audio = 0, gain = 0.5;
    var midi_gain = \gain_cc.kr(gain); // MIDI CC2/CC7 control
    Out.ar(out_audio, midi_gain * In.ar(in));
}).writeDefFile(~dir);
```

## Implementation Plan

### Phase 1: Backend Foundation
**Files to modify:**
- `../sc_em/lib/modsynth.ex`
- `../sc_em/sc_defs/modsynth-synths.sc`

**Changes:**
1. **Parameter Preset System**
   - Create `get_parameter_presets/1` function returning default min/max/current values per module
   - Add preset data structure: `%{module_name => %{param_name => {min, max, default}}}`

2. **Update Control Logic**
   - Modify `is_external_control/1` to handle inline parameters
   - Update control setup to create `InputControl` records for inline module parameters
   - Extend node data structure to store parameter values: `%{param_name => {current, min, max}}`

3. **Create gain Module**
   - Add new synthdef with integrated MIDI handling
   - Migrate cc-in gain logic to gain module
   - Update MIDI message routing

### Phase 2: Frontend Integration
**Files to modify:**
- `lib/modsynth_gui_phx_web/live/synth_editor_live.ex`
- `assets/js/synth_canvas.js`
- Node creation/editing templates

**Changes:**
1. **Node Rendering**
   - Add knob rendering for modules with adjustable parameters
   - Integrate `ControlKnob` hooks directly into module displays
   - Update visual layout to accommodate inline controls

2. **JSON Schema Extension**
   - Extend node format: `%{id, type, x, y, params: %{param_name => {val, min, max}}}`
   - Update save/load logic to handle inline parameters
   - Remove const/cc-in node dependencies

3. **UI Updates**
   - Modify node creation dialog to initialize parameters with presets
   - Update node info dialog for inline parameter editing
   - Add right-click context menu for MIDI assignment (future enhancement)

### Phase 3: Data Migration
**No backward compatibility concerns** - tag current version for reference

**Migration approach:**
1. Tag current system: `git tag v1-const-cc-in-modules`
2. Convert existing example JSON files to new format
3. Update documentation and examples
4. Remove const/cc-in module definitions

### Phase 4: Testing & Validation
**Test scenarios:**
1. **Parameter Control**: Verify all module parameters adjust correctly
2. **MIDI Integration**: Test gain module CC2/CC7 handling
3. **Audio Quality**: Ensure no audio degradation from architecture changes
4. **Performance**: Validate rendering performance with inline knobs
5. **Complex Networks**: Test with existing synthesizer examples

**Test files:**
- All `../sc_em/examples/*.json` networks
- MIDI controller integration
- Real-time parameter adjustment during playback

## Technical Specifications

### Parameter Storage Format
**Old format (const module):**
```json
{
  "id": 4,
  "type": "const", 
  "x": 100, "y": 200,
  "val": 0.1, "min_val": 0.01, "max_val": 2.0
}
```

**New format (inline parameters):**
```json
{
  "id": 1,
  "type": "adsr-env",
  "x": 300, "y": 200,
  "params": {
    "attack": {"val": 0.1, "min": 0.01, "max": 2.0},
    "decay": {"val": 0.2, "min": 0.01, "max": 2.0},
    "sustain": {"val": 0.7, "min": 0.0, "max": 1.0},
    "release": {"val": 1.0, "min": 0.01, "max": 5.0}
  }
}
```

### Backend API Changes
**New functions needed:**
- `get_parameter_presets/1` - Return parameter defaults for module type
- `create_inline_controls/2` - Create InputControl records for inline parameters  
- `update_inline_parameter/4` - Update parameter value with validation

**Modified functions:**
- `is_external_control/1` - Handle inline parameter identification
- `setup_controls/1` - Process both external and inline controls
- `handle_midi_message/3` - Route to appropriate control (gain module vs inline params)

### Frontend Component Changes
**New JavaScript hooks:**
- `InlineParameterKnob` - Handle knob rendering and interaction within modules
- `ModuleParameterManager` - Manage parameter state and MIDI assignment

**Modified components:**
- Node rendering: Add parameter knob layout
- Connection system: Handle both input ports and parameter controls
- Save/load: Process new JSON format

## Future Enhancements

### MIDI Assignment Interface
**Right-click parameter assignment:**
1. Right-click any parameter knob
2. Select "Assign MIDI CC..."
3. Choose CC number and MIDI device
4. Store assignment in node parameters
5. Route MIDI messages to assigned parameters

### Advanced Parameter Features
- **Parameter linking**: Link multiple parameters for coordinated control
- **Parameter automation**: Record/playback parameter changes
- **Parameter groups**: Organize related parameters (e.g., all filter params)
- **Custom parameter ranges**: User-defined min/max overrides

### Performance Optimizations
- **Lazy knob rendering**: Only render visible knobs
- **Parameter caching**: Cache parameter calculations
- **Batch parameter updates**: Group related parameter changes

## Risk Assessment & Mitigation

### Technical Risks
**Risk**: Complex modules become visually cluttered  
**Mitigation**: Collapsible parameter sections, smart knob sizing

**Risk**: Performance impact from many rendered knobs  
**Mitigation**: Lazy rendering, canvas optimization, parameter batching

**Risk**: MIDI handling regression  
**Mitigation**: Comprehensive MIDI testing, gradual migration of gain functionality

### User Experience Risks  
**Risk**: Users confused by changed workflow  
**Mitigation**: Clear documentation, example networks, migration guide

**Risk**: Loss of fine-grained control over parameter ranges  
**Mitigation**: Editable parameter ranges, preset override capability

## Success Metrics

### Usability Improvements
- **Setup time reduction**: Measure time to create complex networks (target: 50% faster)
- **Screen space efficiency**: Count of UI elements for equivalent networks (target: 60% fewer)
- **User satisfaction**: Feedback on workflow simplification

### Technical Validation
- **Audio quality**: No degradation in synthesized output
- **Performance**: No regression in real-time parameter adjustment
- **MIDI functionality**: Full compatibility with existing MIDI workflows
- **Reliability**: No crashes or audio dropouts during parameter changes

This comprehensive plan addresses the identified pain points while maintaining system functionality and providing a clear implementation roadmap.