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
      midi_player_pid: nil,
      available_synthdefs: [],
      available_node_types: available_node_types,
      virtual_conn: nil
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

  def load_parameter_defaults do
    GenServer.call(__MODULE__, :load_parameter_defaults)
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

  def play_synth_with_current_data(device_name, current_synth_data) do
    GenServer.call(__MODULE__, {:play_synth_with_current_data, device_name, current_synth_data})
  end

  def play_midi_file_with_current_data(midi_file_path, current_synth_data) do
    GenServer.call(__MODULE__, {:play_midi_file_with_current_data, midi_file_path, current_synth_data})
  end

  def get_connection_values(connection_list) do
    GenServer.call(__MODULE__, {:get_connection_values, connection_list})
  end

  # Server callbacks

  def handle_call({:load_synth, synth_data}, _from, %{available_node_types: synths} = state) do
    try do

      {nodes, connections, dims} = Modsynth.specs_to_data(synths, synth_data)

      # Log the structure of the nodes for debugging
      Logger.debug("Nodes structure: #{inspect(nodes)}")
      Logger.debug("Connections structure: #{inspect(connections)}")

      new_state = %{state |
        current_synth: %{
          filename: "", # temp_filename,
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

  def handle_call(:stop_synth, _from, %{current_synth: nil} = state) do
    {:reply, {:error, "No synth loaded"}, state}
  end

  def handle_call(:stop_synth, _from, %{midi_player_pid: pid} = state) do
    try do
      # Stop the synth using group_free (as seen in the Scenic example)
      ScClient.group_free(1)
      if !is_nil(pid) do
        MidiPlayer.stop(pid)
      end
      MidiInClient.stop_midi()
      new_state = %{state | synth_running: false, midi_player_pid: nil}
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

  def handle_call(:load_parameter_defaults, _from, state) do
    try do
      parameter_defaults = load_parameter_defaults_from_csv()
      {:reply, {:ok, parameter_defaults}, state}
    catch
      error ->
        Logger.error("Error loading parameter defaults: #{inspect(error)}")
        {:reply, {:error, "Error loading parameter defaults: #{inspect(error)}"}, state}
    end
  end

  def handle_call(:get_available_node_types, _from, state) do
    {:reply, {:ok, state.available_node_types}, state}
  end

  def handle_call(:get_midi_ports, _from, state) do
    try do
      # Create virtual output port only if it doesn't exist
      virtual_conn = case state.virtual_conn do
        nil ->
          Logger.info("Creating new virtual MIDI connection")
          Midiex.create_virtual_output("virtual")
        existing_conn ->
          Logger.info("Reusing existing virtual MIDI connection")
          existing_conn
      end

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

      # Update state with the virtual connection
      new_state = %{state | virtual_conn: virtual_conn}

      {:reply, {:ok, {formatted_ports, port_map_with_virtual}}, new_state}
    catch
      error ->
        Logger.error("Error getting MIDI ports: #{inspect(error)}")
        {:reply, {:error, "Error getting MIDI ports: #{inspect(error)}"}, state}
    end
  end

  def handle_call({:play_synth_with_device, _device_name}, _from, %{current_synth: nil} = state) do
    {:reply, {:error, "No synth loaded"}, state}
  end

  def handle_call({:play_synth_with_device, device_name}, _from, %{current_synth: synth,
                                                                   available_node_types: synths} = state) do
    try do
      Modsynth.specs_to_data(synths, synth.data)
      |> Modsynth.play(device_name)

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

  def handle_call({:play_midi_file, midi_file_path}, _from, %{current_synth: synth,
                                                              virtual_conn: virtual_conn,
                                                              available_node_types: synths} = state) do
    try do
      # Ensure virtual connection exists (create if needed)
      virtual_conn = case virtual_conn do
        nil ->
          Logger.info("Creating virtual MIDI connection for MIDI file playback")
          Midiex.create_virtual_output("virtual")
        existing_conn ->
          Logger.info("Reusing existing virtual MIDI connection")
          existing_conn
      end

      # Use Modsynth.play with virtual device
      Modsynth.specs_to_data(synths, synth.data)
      |> Modsynth.play("virtual")

      pid = MidiPlayer.play(midi_file_path, synth: virtual_conn)
      MidiPlayer.notify_when_play_done(pid)
      new_state = %{state | synth_running: true, midi_player_pid: pid, virtual_conn: virtual_conn}
      {:reply, {:ok, "Synth started with MIDI file: #{midi_file_path}"}, new_state}
    catch
      error ->
        Logger.error("Error playing MIDI file #{midi_file_path}: #{inspect(error)}")
        {:reply, {:error, "Error playing MIDI file: #{inspect(error)}"}, state}
    end
  end

  def handle_call({:play_synth_with_current_data, device_name, current_synth_data}, _from, %{available_node_types: synths} = state) do
    try do
      # Use current synth data instead of stored data
      {input_control_list, _node_map, connection_list} = Modsynth.specs_to_data(synths, current_synth_data)
      |> Modsynth.play(device_name)

      new_state = %{state | synth_running: true}
      {:reply, {:ok, {"Synth started with device: #{device_name}", input_control_list, connection_list}}, new_state}
    catch
      error ->
        Logger.error("Error playing synth with device #{device_name}: #{inspect(error)}")
        {:reply, {:error, "Error playing synth: #{inspect(error)}"}, state}
    end
  end

  def handle_call({:play_midi_file_with_current_data, midi_file_path, current_synth_data}, _from, %{virtual_conn: virtual_conn, available_node_types: synths} = state) do
    try do
      # Ensure virtual connection exists (create if needed)
      virtual_conn = case virtual_conn do
        nil ->
          Logger.info("Creating virtual MIDI connection for STrack playback")
          Midiex.create_virtual_output("virtual")
        existing_conn ->
          Logger.info("Reusing existing virtual MIDI connection")
          existing_conn
      end

      # Use current synth data instead of stored data
      {input_control_list, _node_map, connection_list} = Modsynth.specs_to_data(synths, current_synth_data)
      |> Modsynth.play("virtual")

      pid = MidiPlayer.play(midi_file_path, synth: virtual_conn)
      MidiPlayer.notify_when_play_done(pid)
      new_state = %{state | synth_running: true, midi_player_pid: pid, virtual_conn: virtual_conn}
      {:reply, {:ok, {"Synth started with STrack data", input_control_list, connection_list}}, new_state}
    catch
      error ->
        Logger.error("Error playing MIDI file #{midi_file_path}: #{inspect(error)}")
        {:reply, {:error, "Error playing MIDI file: #{inspect(error)}"}, state}
    end
  end

  def handle_call({:get_connection_values, connection_list}, _from, state) do
    if state.synth_running do
      try do
        connection_values = Modsynth.get_all_connection_values(connection_list)
        {:reply, {:ok, connection_values}, state}
      catch
        error ->
          Logger.error("Error getting connection values: #{inspect(error)}")
          {:reply, {:error, "Error getting connection values: #{inspect(error)}"}, state}
      end
    else
      {:reply, {:error, "Synth not running"}, state}
    end
  end

  def handle_info(:midi_play_done, state) do
    ScClient.group_free(1)
    MidiInClient.stop_midi()
    # Update state to reflect that synth is no longer running but preserve synth data
    new_state = %{state | synth_running: false, midi_player_pid: nil}
    {:noreply, new_state}
  end

  # Private helper functions

  defp load_parameter_defaults_from_csv() do
    # Load default parameters from sc_em directory
    default_csv_path = Path.join(["..", "sc_em", "sc_def_default_input_settings.csv"])
    default_params = parse_parameter_csv(default_csv_path)

    # Load user overrides from ~/.modsynth directory
    user_csv_path = Path.expand("~/.modsynth/sc_def_input_settings.csv")
    user_params = if File.exists?(user_csv_path) do
      parse_parameter_csv(user_csv_path)
    else
      %{}
    end

    # Merge user parameters over defaults
    Map.merge(default_params, user_params)
  end

  defp parse_parameter_csv(csv_path) do
    case File.read(csv_path) do
      {:ok, content} ->
        content
        |> String.split("\n", trim: true)
        |> Enum.drop(1)  # Skip header row
        |> Enum.reduce(%{}, fn line, acc ->
          case String.split(line, ",", trim: true) do
            [sc_def_name, control_name, current_val, min_val, max_val] ->
              # Convert string values to floats, handling both integers and floats
              current = parse_numeric(current_val)
              min = parse_numeric(min_val)
              max = parse_numeric(max_val)
              
              # Store nested by sc_def_name then control_name
              param_info = %{val: current, min: min, max: max}
              
              case Map.get(acc, sc_def_name) do
                nil ->
                  Map.put(acc, sc_def_name, %{control_name => param_info})
                existing_params ->
                  updated_params = Map.put(existing_params, control_name, param_info)
                  Map.put(acc, sc_def_name, updated_params)
              end
            _ ->
              # Skip malformed lines
              acc
          end
        end)
      {:error, reason} ->
        Logger.warning("Could not read parameter CSV file #{csv_path}: #{inspect(reason)}")
        %{}
    end
  end

  defp parse_numeric(str) do
    case Float.parse(str) do
      {value, _} -> value
      :error ->
        case Integer.parse(str) do
          {value, _} -> value / 1.0  # Convert to float
          :error -> 0.0  # Default fallback
        end
    end
  end

end
