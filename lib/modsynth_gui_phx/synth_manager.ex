defmodule ModsynthGuiPhx.SynthManager do
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    # Initialize available node types from Modsynth
    available_node_types = try do
      Modsynth.init()
    rescue
      error ->
        Logger.error("Failed to initialize Modsynth: #{inspect(error)}")
        %{}
    end

    {:ok, %{
      current_synth: nil,
      synth_running: false,
      available_synthdefs: [],
      available_node_types: available_node_types
    }}
  end

  # Client API

  def load_synth(synth_data) do
    GenServer.call(__MODULE__, {:load_synth, synth_data})
  end

  def play_synth do
    GenServer.call(__MODULE__, :play_synth)
  end

  def stop_synth do
    GenServer.call(__MODULE__, :stop_synth)
  end

  def get_available_synthdefs do
    GenServer.call(__MODULE__, :get_available_synthdefs)
  end

  def get_synth_status do
    GenServer.call(__MODULE__, :get_synth_status)
  end

  def get_current_synth_data do
    GenServer.call(__MODULE__, :get_current_synth_data)
  end

  def get_available_node_types do
    GenServer.call(__MODULE__, :get_available_node_types)
  end

  def get_midi_ports do
    GenServer.call(__MODULE__, :get_midi_ports)
  end

  def play_synth_with_device(device_name) do
    GenServer.call(__MODULE__, {:play_synth_with_device, device_name})
  end

  def play_midi_file(midi_file_path) do
    GenServer.call(__MODULE__, {:play_midi_file, midi_file_path})
  end

  # Server callbacks

  def handle_call({:load_synth, synth_data}, _from, state) do
    try do
      # Save the synth data temporarily to load it
      temp_filename = "/tmp/temp_synth_#{:rand.uniform(1000)}.json"
      json_data = Jason.encode!(synth_data)
      File.write!(temp_filename, json_data)

      # Use Modsynth.look to validate and parse the synth
      {nodes, connections, dims} = Modsynth.look(temp_filename)
      File.rm(temp_filename)

      # Log the structure of the nodes for debugging
      Logger.info("Nodes structure: #{inspect(nodes)}")
      Logger.info("Connections structure: #{inspect(connections)}")

      new_state = %{state |
        current_synth: %{
          filename: temp_filename,
          nodes: nodes,
          connections: connections,
          dims: dims,
          data: synth_data
        },
        synth_running: false
      }
      {:reply, {:ok, "Synth loaded successfully"}, new_state}
    catch
      error ->
        Logger.error("Error loading synth: #{inspect(error)}")
        {:reply, {:error, "Error loading synth: #{inspect(error)}"}, state}
    end
  end

  def handle_call(:play_synth, _from, %{current_synth: nil} = state) do
    {:reply, {:error, "No synth loaded"}, state}
  end

  def handle_call(:play_synth, _from, %{current_synth: synth} = state) do
    try do
      # Save synth data to a temporary file for playing
      temp_filename = "/tmp/temp_synth_play_#{:rand.uniform(1000)}.json"
      json_data = Jason.encode!(synth.data)
      File.write!(temp_filename, json_data)

      # Use Modsynth.play with default device "AE-30"
      _result = Modsynth.play(temp_filename, "AE-30")

      File.rm(temp_filename)
      new_state = %{state | synth_running: true}
      {:reply, {:ok, "Synth started"}, new_state}
    catch
      error ->
        Logger.error("Error playing synth: #{inspect(error)}")
        {:reply, {:error, "Error playing synth: #{inspect(error)}"}, state}
    end
  end

  def handle_call(:stop_synth, _from, %{current_synth: nil} = state) do
    {:reply, {:error, "No synth loaded"}, state}
  end

  def handle_call(:stop_synth, _from, %{current_synth: _synth} = state) do
    try do
      # Stop the synth using group_free (as seen in the Scenic example)
      ScClient.group_free(1)
      new_state = %{state | synth_running: false}
      {:reply, {:ok, "Synth stopped"}, new_state}
    catch
      error ->
        Logger.error("Error stopping synth: #{inspect(error)}")
        {:reply, {:error, "Error stopping synth: #{inspect(error)}"}, state}
    end
  end

  def handle_call(:get_available_synthdefs, _from, state) do
    try do
      # Get available synthdefs from sc_em using the circuit directory
      circuit_dir = Application.get_env(:sc_em, :circuit_dir, "../sc_em/examples")
      synthdefs = case File.ls(circuit_dir) do
        {:ok, files} ->
          files
          |> Enum.filter(&String.ends_with?(&1, ".json"))
          |> Enum.map(&String.replace(&1, ".json", ""))

        {:error, _reason} ->
          Logger.error("Could not read circuit directory: #{circuit_dir}")
          []
      end

      new_state = %{state | available_synthdefs: synthdefs}
      {:reply, {:ok, synthdefs}, new_state}
    catch
      error ->
        Logger.error("Error getting synthdefs: #{inspect(error)}")
        {:reply, {:error, "Error getting synthdefs: #{inspect(error)}"}, state}
    end
  end

  def handle_call(:get_synth_status, _from, state) do
    status = %{
      synth_loaded: state.current_synth != nil,
      synth_running: state.synth_running,
      available_synthdefs: length(state.available_synthdefs)
    }
    {:reply, {:ok, status}, state}
  end

  def handle_call(:get_current_synth_data, _from, %{current_synth: nil} = state) do
    {:reply, {:error, "No synth loaded"}, state}
  end

  def handle_call(:get_current_synth_data, _from, %{current_synth: synth} = state) do
    {:reply, {:ok, synth}, state}
  end

  def handle_call(:get_available_node_types, _from, state) do
    {:reply, {:ok, state.available_node_types}, state}
  end

  def handle_call(:get_midi_ports, _from, state) do
    try do
      # Create virtual output port
      virtual_conn = Midiex.create_virtual_output("virtual")

      # Get all available MIDI ports and filter for input devices, excluding virtual
      ports = Midiex.ports() 
      |> Enum.filter(fn p -> p.direction == :input end)
      |> Enum.reject(fn p -> p.name == "virtual" end)

      # Format ports for dropdown: [{display_name, atom_key}, ...]
      formatted_ports = Enum.map(ports, fn p -> {p.name, String.to_atom(p.name)} end)

      # Create port map: %{atom_key => port_struct}
      port_map = Enum.map(ports, fn p -> {String.to_atom(p.name), p} end) |> Map.new()
      
      # Keep virtual device in port map for MIDI file playback but don't include in dropdown
      port_map_with_virtual = Map.put(port_map, :virtual, %{name: "virtual", connection: virtual_conn})

      {:reply, {:ok, {formatted_ports, port_map_with_virtual}}, state}
    catch
      error ->
        Logger.error("Error getting MIDI ports: #{inspect(error)}")
        {:reply, {:error, "Error getting MIDI ports: #{inspect(error)}"}, state}
    end
  end

  def handle_call({:play_synth_with_device, _device_name}, _from, %{current_synth: nil} = state) do
    {:reply, {:error, "No synth loaded"}, state}
  end

  def handle_call({:play_synth_with_device, device_name}, _from, %{current_synth: synth} = state) do
    try do
      # Save synth data to a temporary file for playing
      temp_filename = "/tmp/temp_synth_play_#{:rand.uniform(1000)}.json"
      json_data = Jason.encode!(synth.data)
      File.write!(temp_filename, json_data)

      # Use Modsynth.play with specified device
      Logger.debug("##############################################playing #{device_name}")
      _result = Modsynth.play(temp_filename, device_name)

      File.rm(temp_filename)
      new_state = %{state | synth_running: true}
      {:reply, {:ok, "Synth started with device: #{device_name}"}, new_state}
    catch
      error ->
        Logger.error("Error playing synth with device #{device_name}: #{inspect(error)}")
        {:reply, {:error, "Error playing synth: #{inspect(error)}"}, state}
    end
  end

  def handle_call({:play_midi_file, _midi_file_path}, _from, %{current_synth: nil} = state) do
    {:reply, {:error, "No synth loaded"}, state}
  end

  def handle_call({:play_midi_file, midi_file_path}, _from, %{current_synth: synth} = state) do
    try do
      # Save synth data to a temporary file for playing
      temp_filename = "/tmp/temp_synth_play_#{:rand.uniform(1000)}.json"
      json_data = Jason.encode!(synth.data)
      File.write!(temp_filename, json_data)

      # Use Modsynth.play with virtual device
      _result = Modsynth.play(temp_filename, "virtual")

      # TODO: Add MIDI file playback functionality
      # This would need to be implemented based on the MidiPlayer module
      # from the reference implementation

      File.rm(temp_filename)
      new_state = %{state | synth_running: true}
      {:reply, {:ok, "Synth started with MIDI file: #{midi_file_path}"}, new_state}
    catch
      error ->
        Logger.error("Error playing MIDI file #{midi_file_path}: #{inspect(error)}")
        {:reply, {:error, "Error playing MIDI file: #{inspect(error)}"}, state}
    end
  end

end
