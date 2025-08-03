# Modular Synthesizer GUI

A Phoenix LiveView application that provides a unified interface for creating and editing modular synthesizer networks with integrated script-based music composition capabilities using SuperCollider as the audio engine.

## User Documentation

### Overview

The Modular Synthesizer GUI is a web-based unified programming environment for creating modular synthesizer patches and algorithmic music compositions. It features a tabbed interface that seamlessly integrates visual synthesis with script-based composition. It allows you to:

**Visual Synthesizer Editor:**
- Create synthesizer networks by connecting various audio modules (oscillators, filters, envelopes, etc.)
- Load and save synthesizer patches
- Real-time parameter control with visual feedback
- Edit/Run mode switching with context-sensitive controls

**STrack Script Editor:**
- Write algorithmic music compositions in Elixir-like syntax
- Real-time code execution with error validation
- Musical helper functions for arpeggios, chord progressions, and sequences
- File management with user scripts and examples

**Unified Playback:**
- Play creations using MIDI devices or MIDI files
- Shared synthesizer state between visual and script workflows
- Cross-format compatibility and live integration

![Main interface showing unified tabbed interface with both Synth Editor and Script Editor tabs, demonstrating the seamless integration](screenshots/main-interface.png)

### Installation and Setup

#### Prerequisites

- Elixir 1.14+ and Erlang/OTP 25+
- SuperCollider 3.12+ with the `sc3-plugins` package
- A MIDI device or MIDI files for playback (optional)



#### Quick Start

Note that this project doesn't define an internal version of supercollider - it must be managed by the user. This has advantages and disadvantages from the user perspective and
might be changed in the future.

1. Clone the repository and navigate to the project directory


2. Install dependencies:
   ```bash
   mix setup
   ```
3. Run SuperCollider and boot the server.
4. Start the Phoenix server:
   ```bash
   mix phx.server
   ```
5. Open your browser and visit [`localhost:4000`](http://localhost:4000)

### Interface Guide

#### Main Canvas

The main canvas is where you create and edit your synthesizer networks. It features:

- **Grid background** for visual alignment
- **Zoom and pan capabilities** for working with large patches
- **Node placement** by right-clicking to open the creation menu
- **Connection system** for linking nodes together

![Clean canvas showing grid background with right-click menu displaying available node types](screenshots/canvas-with-menu.png)

#### Node Types and Categories

**Oscillators** (Orange)
- `saw-osc` - Sawtooth wave oscillator
- `square-osc` - Square wave oscillator with pulse width control
- `s_sin-osc` - Sine wave oscillator
- `sin-vco` - Sine wave VCO for control signals

**Filters** (Green)
- `moog-filt` - Moog-style low-pass filter with resonance
- `bp-filt` - Band-pass filter
- `lp-filt` - Low-pass filter
- `hp-filt` - High-pass filter

**Envelopes & Amplifiers** (Purple)
- `adsr-env` - ADSR envelope generator
- `perc-env` - Percussive envelope generator
- `amp` - Amplifier with gain control

**Effects** (Blue)
- `freeverb` - Reverb effect
- `echo` - Echo/delay effect

**Utilities** (Gray)
- `const` - Constant value generator with knob control
- `c-splitter` - Control signal splitter
- `a-splitter` - Audio signal splitter
- `mult` - Signal multiplier

**I/O** (Pink)
- `midi-in` - MIDI input for frequency control
- `audio-out` - Audio output (stereo)
- `cc-in` - MIDI CC input

![Canvas showing examples of each node type with different colors and typical connections](screenshots/node-types.png)

#### Creating Connections

1. **Start a connection** by clicking an output port (right side of nodes, orange circles)
2. **Complete the connection** by clicking an input port (left side of nodes, green circles)
3. **Delete connections** by clicking on the cable itself

![Connection process showing clicking output port, connection mode, and completing connection to input port](screenshots/connection-process-1.png)

![Connection process showing clicking output port, connection mode, and completing connection to input port](screenshots/connection-process-2.png)

Port labels show the actual parameter names (freq, gain, cutoff, etc.) making it easy to understand what each connection does.

#### File Management

The file browser provides access to:

- **User files** (blue badges) - Your saved patches
- **Example files** (green badges) - Provided example patches
- **Alphabetical sorting** - Files are mixed and sorted for easy comparison
- **Scrollable list** - Handles large numbers of files

![File browser showing mixed user and example files with blue and green color-coded badges](screenshots/file-browser.png)

To save a patch:
1. Enter a filename in the save field
2. Click "Save"
3. The file will appear in the browser with a blue "user" badge

#### Parameter Control

**Constant (const) Nodes**
- Feature interactive knobs for real-time parameter control
- Display current value and allow precise adjustment
- Automatically set appropriate ranges based on usage

![Close-up of const node showing interactive knob, current value display, and range indicators](screenshots/const-knob-1.png)

![Close-up of const node showing interactive knob, current value display, and range indicators](screenshots/const-knob-2.png)

#### Node Information

Right-click any node to access:
- **Node Info** - View detailed parameter information
- **Delete Node** - Remove the node and all its connections

![Context menu open on a node and node info modal showing detailed parameter information](screenshots/context-menu.png)

### STrack Script Editor

The STrack Script Editor provides algorithmic music composition capabilities using an Elixir-like syntax. Access it through the "Script Editor" tab in the unified interface.

![STrack Script Editor showing Monaco Editor with syntax highlighting, file browser, and example scripts](screenshots/strack-editor.png)

#### Code Editor Features

**Monaco Editor Integration**
- Full Elixir syntax highlighting and error detection
- Real-time code validation with error display
- Auto-completion and code formatting
- Line numbers and code folding

![Monaco Editor showing Elixir syntax highlighting with error markers and auto-completion](screenshots/monaco-editor.png)

#### Script Execution

**Live Code Execution**
1. Write your STrack script in the editor
2. Click "Run Script" to execute and validate
3. View output and any error messages in real-time
4. Scripts integrate directly with the synthesizer backend

![Script execution showing both successful output and error validation with clear feedback](screenshots/script-execution.png)

#### File Management

**Script Organization**
- **User Scripts** - Stored in `~/.modsynth/strack_scripts/`
- **Example Scripts** - Provided examples (simple_note.exs, pachelbel.exs)
- **File Browser** - Easy navigation between scripts
- **Save/Load** - Standard file operations with auto-save

![File browser showing user scripts, example scripts, and new script creation options](screenshots/strack-files.png)

#### Prelude System

**Musical Helper Functions**
- Built-in functions for arpeggios, chord progressions, and sequences
- C-style include functionality for reusable code
- Project-wide prelude (`prelude.exs`) and user-specific prelude (`~/.modsynth/strack_scripts/.prelude.exs`)
- Easy access to common musical patterns and utilities

![Code showing prelude function usage with musical helper functions and include statements](screenshots/prelude-functions.png)

#### Integration with Synthesizer

**Unified Playback**
- Scripts can trigger and control synthesizer networks
- Shared state between visual and script editors
- Real-time parameter control from scripts
- MIDI integration and virtual port creation

![Split view showing script editor controlling synthesizer network with real-time parameter updates](screenshots/unified-integration.png)

### Playback and Performance

The unified interface supports playback for both visual synthesizer patches and STrack script compositions, with shared MIDI routing and audio processing.

#### MIDI Device Playback

1. Click the "Play" button in the header
2. Select a MIDI device from the dropdown
3. Click "Play" to start the synthesizer
4. Use your MIDI device to play notes

![Play menu open showing MIDI device selection dropdown and MIDI file path options](screenshots/play-menu.png)

#### MIDI File Playback

1. Click the "Play" button in the header
2. Enter a path to a MIDI file or browse using the suggestions
3. Click "Play" to start playback
4. The file will play through your synthesizer patch

The path browser provides:
- **Current directory navigation** (type "./" to see current folder)
- **Configured MIDI directories** (pre-configured common locations)
- **Directory traversal** (use ".." to go up)
- **File filtering** (only shows .mid and .midi files)

#### Stop Playback

Click the "Stop" button to halt all audio playback and clean up MIDI connections.

### Configuration

#### Environment Variables

- `MODSYNTH_DIR` - Directory for user files (default: `~/.modsynth`)
- `MODSYNTH_MIDI_DIRS` - Semicolon-delimited list of MIDI directories to search

#### File Locations

**User Data Directories:**
- `~/.modsynth/` - Main user data directory
- `~/.modsynth/strack_scripts/` - User-created STrack scripts
- `~/.modsynth/strack_scripts/.prelude.exs` - User-specific prelude functions

**Project Files:**
- `prelude.exs` - Project-wide helper functions for STrack scripts
- `example_stracks/` - Example STrack scripts (simple_note.exs, pachelbel.exs)

Example:
```bash
export MODSYNTH_MIDI_DIRS="/home/user/midi;/opt/midi;../custom_midi"
```

#### Logger Configuration

The application uses structured logging. Set the log level in `config/config.exs`:

```elixir
config :logger, :console, level: :info
```

### Troubleshooting

**Common Issues:**

1. **No audio output** - Check that SuperCollider is running and audio drivers are configured
2. **MIDI device not found** - Verify MIDI device is connected and recognized by the system
3. **File loading errors** - Check file permissions and JSON syntax
4. **Connection issues** - Ensure you're connecting outputs to inputs (not input to input)

![Examples of error messages and where they appear in the interface](screenshots/error-messages.png)

---

## Technical Documentation

### Architecture Overview

The application consists of several key components:

```
┌─────────────────────────────────────────────────────────────────┐
│                Phoenix LiveView Unified Frontend               │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │  SynthEditorLive │  │STrackCodeEditor │  │   FileManager   │ │
│  │ (Visual Synth)   │  │ (Script Editor) │  │  (File I/O)     │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
│  ┌─────────────────────────────────────────┐                   │
│  │           SynthManager                  │                   │
│  │      (Audio Engine & Backend)           │                   │
│  └─────────────────────────────────────────┘                   │
└─────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                 SuperCollider Backend (sc_em)                   │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │    Modsynth     │  │    ScClient     │  │   MidiPlayer    │ │
│  │  (Core Logic)   │  │  (SC Interface) │  │ (MIDI Playback) │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

### Project Structure

```
modsynth_gui_phx/
├── lib/
│   ├── modsynth_gui_phx/
│   │   ├── application.ex          # Application supervisor
│   │   ├── file_manager.ex         # File operations
│   │   └── synth_manager.ex        # Backend integration
│   └── modsynth_gui_phx_web/
│       ├── live/
│       │   ├── synth_editor_live.ex      # Unified editor (visual + script)
│       │   └── strack_code_editor_live.ex # STrack code editor component
│       ├── components/             # Reusable UI components
│       └── controllers/            # HTTP controllers
├── assets/
│   ├── js/
│   │   ├── app.js                 # Main JavaScript
│   │   └── synth_canvas.js        # Canvas interactions
│   └── css/                       # Styling
├── config/                        # Application configuration
├── prelude.exs                    # Project-wide STrack helper functions
├── example_stracks/               # Example STrack scripts
│   ├── simple_note.exs
│   └── pachelbel.exs
├── ~/.modsynth/                   # User data directory
│   └── strack_scripts/            # User STrack scripts
│       └── .prelude.exs           # User-specific prelude functions
└── ../sc_em/                      # SuperCollider backend
    ├── lib/                       # Core synthesizer logic
    ├── examples/                  # Example synthesizer patches
    └── sc_defs/                   # SuperCollider definitions
```

### Key Components

#### SynthEditorLive (Unified Interface)

**File:** `lib/modsynth_gui_phx_web/live/synth_editor_live.ex`

The main LiveView component that provides the unified tabbed interface:
- Tab-based navigation between Synth Editor and Script Editor
- Canvas rendering and node management for visual synthesis
- Shared state management between visual and script workflows
- Real-time UI updates and user interaction events
- Connection management between nodes

Key functions:
- `mount/3` - Initialize the LiveView with file lists, tab state, and empty synth state
- `handle_event/3` - Process user interactions (clicks, drags, tab switches, etc.)
- `render/1` - Generate the unified interface with tabs, SVG canvas, and script editor

#### STrackCodeEditorLive (Script Editor)

**File:** `lib/modsynth_gui_phx_web/live/strack_code_editor_live.ex`

The STrack script editor component that handles:
- Monaco Editor integration with Elixir syntax highlighting
- Real-time code execution and validation
- Script file management and browser integration
- Prelude system with helper function support
- Integration with synthesizer backend for live playback

Key functions:
- Script execution with error handling and output display
- File operations for user and example scripts
- Prelude function loading and include processing
- Backend integration for live script performance

#### FileManager

**File:** `lib/modsynth_gui_phx/file_manager.ex`

Handles file operations:
- Loading and saving synthesizer patches (JSON format)
- Directory management for user and example files
- File listing with categorization

#### SynthManager

**File:** `lib/modsynth_gui_phx/synth_manager.ex`

GenServer that manages:
- Communication with SuperCollider backend
- MIDI device enumeration and playback
- Synthesizer state management
- Audio playback coordination

#### Canvas JavaScript

**File:** `assets/js/synth_canvas.js`

Handles client-side interactions:
- Node dragging and positioning
- Viewport resizing
- Knob control interactions
- Canvas event handling

### Data Flow

#### Loading a Patch

1. User clicks file in browser → `load_file` event
2. `FileManager.load_synth_file/1` reads JSON
3. `SynthManager.load_synth/1` processes data
4. Backend converts to enriched node format
5. UI updates with new nodes and connections

#### Creating Connections

1. User clicks output port → `port_clicked` event
2. UI enters connection mode
3. User clicks input port → connection validated
4. New connection added to state
5. Canvas re-renders with new cable

#### Playing Audio

1. User selects MIDI device/file → `play_with_device` event
2. `SynthManager` validates current synth
3. Backend loads patch into SuperCollider
4. MIDI routing established
5. Audio playback begins

### Development Setup

#### Prerequisites

- Elixir 1.14+ and Erlang/OTP 25+
- Phoenix 1.7+
- SuperCollider 3.12+ with sc3-plugins
- Node.js (for asset compilation)

#### Development Commands

```bash
# Install dependencies
mix deps.get

# Install Node.js dependencies
npm install --prefix assets

# Start development server
mix phx.server

# Run tests
mix test

# Check compilation
mix compile

# Build assets
mix assets.build
```

#### Code Structure Guidelines

- **LiveView Events**: Use descriptive event names matching user actions
- **State Management**: Keep UI state in socket assigns, audio state in GenServer
- **Error Handling**: Provide user-friendly error messages with flash notifications
- **Logging**: Use structured logging with appropriate levels (debug, info, warn, error)

### API Documentation

#### Phoenix LiveView Events

| Event | Parameters | Description |
|-------|------------|-------------|
| `load_file` | `path` | Load a synthesizer patch from file |
| `save_file` | `filename` | Save current patch to file |
| `node_moved` | `id`, `x`, `y` | Update node position |
| `port_clicked` | `node_id`, `port_type`, `port_index` | Handle port interaction |
| `create_node` | `node_type` | Create new node of specified type |
| `play_with_device` | - | Start playback with selected MIDI device |
| `stop_synth` | - | Stop all audio playback |

#### SynthManager GenServer API

| Function | Parameters | Returns | Description |
|----------|------------|---------|-------------|
| `load_synth/1` | `synth_data` | `{:ok, message}` | Load patch into backend |
| `get_current_synth_data/0` | - | `{:ok, synth_data}` | Get enriched node data |
| `play_synth_with_device/1` | `device_name` | `{:ok, message}` | Start MIDI playback |
| `stop_synth/0` | - | `{:ok, message}` | Stop playback |
| `get_midi_ports/0` | - | `{:ok, {ports, port_map}}` | Get available MIDI devices |

### Configuration Options

#### Application Configuration

**File:** `config/config.exs`

```elixir
# Logger configuration
config :logger, :console, level: :info

# MIDI directories for file browser
config :modsynth_gui_phx, :midi_directories,
  "../sc_em/midi;deps/midifile/test"

# Phoenix configuration
config :modsynth_gui_phx, ModsynthGuiPhxWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [view: ModsynthGuiPhxWeb.ErrorView],
  pubsub_server: ModsynthGuiPhx.PubSub
```

#### Runtime Configuration

**Environment Variables:**
- `MODSYNTH_DIR` - User files directory
- `MODSYNTH_MIDI_DIRS` - MIDI search directories
- `PHX_HOST` - Phoenix server host
- `PORT` - Server port

### Advanced Features

#### Custom Node Types

To add new node types:

1. Add SuperCollider definition to `../sc_em/sc_defs/`
2. Update `../sc_em/lib/modsynth.ex` with parameter definitions
3. Add UI styling in `synth_editor_live.ex` color mapping
4. Add port definitions in `get_node_ports_fallback/1`

#### MIDI Integration

The system supports:
- **Real-time MIDI input** for live performance
- **MIDI file playback** for automated sequences
- **MIDI CC control** for parameter automation
- **Multi-channel MIDI** routing

#### Parameter Mapping

The `parameter_rename_mapping.json` file handles parameter name translations between UI and backend, ensuring compatibility as the backend evolves.

### Testing

#### Running Tests

```bash
# Run all tests
mix test

# Run specific test file
mix test test/modsynth_gui_phx/file_manager_test.exs

# Run tests with coverage
mix test --cover
```

#### Test Structure

- **Unit Tests**: Test individual modules (FileManager, SynthManager)
- **Integration Tests**: Test LiveView interactions
- **End-to-End Tests**: Test complete workflows

### Contributing

#### Code Style

- Follow Elixir style guide
- Use `mix format` for code formatting
- Add documentation for public functions
- Include tests for new features

#### Pull Request Process

1. Create feature branch from `main`
2. Implement changes with tests
3. Update documentation
4. Submit PR with clear description

#### Commit Message Format

```
Brief description of change

Detailed explanation of what was changed and why.
Include any breaking changes or migration notes.

🤖 Generated with [Claude Code](https://claude.ai/code)

Co-Authored-By: Claude <noreply@anthropic.com>
```

### Deployment

#### Production Setup

1. Set production environment variables
2. Configure database (if using persistent storage)
3. Set up reverse proxy (nginx recommended)
4. Configure SSL certificates
5. Set up monitoring and logging

#### Docker Deployment

```dockerfile
FROM elixir:1.14-alpine

# Install build dependencies
RUN apk add --no-cache build-base npm git

# Create app directory
WORKDIR /app

# Copy mix files
COPY mix.exs mix.lock ./
RUN mix deps.get

# Copy source code
COPY . .

# Build application
RUN mix compile
RUN npm install --prefix assets
RUN mix assets.build

EXPOSE 4000
CMD ["mix", "phx.server"]
```

### License

This project is licensed under the MIT License - see the LICENSE file for details.

### Acknowledgments

- Phoenix Framework for the web application foundation
- SuperCollider for the audio engine
- LiveView for real-time UI updates
- The Elixir community for excellent tooling and support
