defmodule ModsynthGuiPhxWeb.SynthEditorLive do
  use ModsynthGuiPhxWeb, :live_view
  alias ModsynthGuiPhx.FileManager

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {user_files, example_files} = FileManager.list_synth_files()

    Logger.info("LiveView mount - User files: #{inspect(user_files)}")
    Logger.debug("LiveView mount - Example files: #{inspect(example_files)}")

    # Combine and sort all files alphabetically by name (mixed categories)
    all_files = (user_files ++ example_files)
                |> Enum.sort_by(fn file -> file.name end)

    socket =
      socket
      |> assign(:user_files, user_files)
      |> assign(:example_files, example_files)
      |> assign(:all_files, all_files)
      |> assign(:current_synth, nil)
      |> assign(:current_filename, nil)
      |> assign(:nodes, [])
      |> assign(:connections, [])
      |> assign(:selected_node, nil)
      |> assign(:canvas_size, %{width: 2400, height: 1600})
      |> assign(:viewport_size, %{width: 1200, height: 800})
      |> assign(:show_file_browser, false)
      |> assign(:new_filename, "")
      |> assign(:warnings, [])
      |> assign(:connection_mode, %{active: false, from_node: nil, from_port: nil})
      |> assign(:context_menu, %{visible: false, x: 0, y: 0, node_id: nil})
      |> assign(:node_info_modal, %{visible: false, node: nil})
      |> assign(:node_creation_menu, %{visible: false, x: 0, y: 0, svg_x: 0, svg_y: 0, available_types: []})
      |> assign(:play_menu, %{visible: false, midi_ports: [], port_map: %{}, selected_port: nil})
      |> assign(:midi_file_path, "")
      |> assign(:midi_file_suggestions, [])
      |> assign(:mode, :edit)  # :edit or :run
      |> assign(:input_control_list, [])
      |> assign(:connection_list, [])
      |> assign(:node_config_modal, %{visible: false, node_type: nil, svg_x: 0, svg_y: 0})

    {:ok, socket}
  end

  @impl true
  def handle_event("toggle_file_browser", _, socket) do
    {:noreply, assign(socket, :show_file_browser, !socket.assigns.show_file_browser)}
  end

  def handle_event("viewport_resize", %{"width" => width, "height" => height}, socket) do
    # Update viewport size based on window size, accounting for header and margins
    viewport_width = max(800, width - 40)  # Minimum width with padding
    viewport_height = max(600, height - 120)  # Minimum height accounting for header

    {:noreply, assign(socket, :viewport_size, %{width: viewport_width, height: viewport_height})}
  end


  def handle_event("load_file", %{"path" => path}, socket) do
    case FileManager.load_synth_file(path) do
      {:ok, data} ->
        # Load the synth into the SynthManager to get enriched node data
        case ModsynthGuiPhx.SynthManager.load_synth(data) do
          {:ok, message} ->
            # Get the enriched node data from SynthManager
            case ModsynthGuiPhx.SynthManager.get_current_synth_data() do
              {:ok, synth_data} ->
                # Convert the enriched nodes map to a list format compatible with the UI
                enriched_nodes = convert_modsynth_nodes_to_ui_format(synth_data.nodes, data["nodes"])

                # Convert parameter-based connections to port-based connections
                raw_connections = data["connections"] || []
                port_connections = convert_connections_to_port_format(raw_connections, enriched_nodes)

                # Extract filename from path for display
                filename = Path.basename(path)

                socket =
                  socket
                  |> assign(:current_synth, data)
                  |> assign(:current_filename, filename)
                  |> assign(:nodes, enriched_nodes)
                  |> assign(:connections, port_connections)
                  |> assign(:show_file_browser, false)
                  |> assign(:warnings, [])
                  |> put_flash(:info, message)

                {:noreply, socket}

              {:error, reason} ->
                {:noreply, put_flash(socket, :error, "Failed to get enriched synth data: #{reason}")}
            end

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Failed to load synth: #{reason}")}
        end

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to load file: #{reason}")}
    end
  end

  def handle_event("save_file", %{"filename" => filename}, socket) do
    if filename != "" do
      # Convert port-based connections back to parameter-based format for saving
      param_connections = convert_connections_to_param_format(socket.assigns.connections, socket.assigns.nodes)

      # Convert enriched nodes back to original format for saving
      original_nodes = convert_enriched_nodes_to_original_format(socket.assigns.nodes)

      synth_data = %{
        "nodes" => original_nodes,
        "connections" => param_connections,
        "frame" => socket.assigns.canvas_size,
        "master_vol" => 0.3
      }

      case FileManager.save_synth_file(filename, synth_data) do
        {:ok, _path} ->
          {user_files, _example_files} = FileManager.list_synth_files()

          # Update all_files when user files change
          all_files = (user_files ++ socket.assigns.example_files)
                      |> Enum.sort_by(fn file -> file.name end)

          socket =
            socket
            |> assign(:user_files, user_files)
            |> assign(:all_files, all_files)
            |> assign(:current_filename, filename)
            |> assign(:new_filename, "")
            |> put_flash(:info, "File saved successfully")

          {:noreply, socket}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to save file: #{reason}")}
      end
    else
      {:noreply, put_flash(socket, :error, "Please enter a filename")}
    end
  end

  def handle_event("update_filename", %{"filename" => filename}, socket) do
    {:noreply, assign(socket, :new_filename, filename)}
  end

  def handle_event("node_moved", %{"id" => id, "x" => x, "y" => y}, socket) do
    updated_nodes =
      Enum.map(socket.assigns.nodes, fn node ->
        if node["id"] == id do
          Map.merge(node, %{"x" => x, "y" => y})
        else
          node
        end
      end)

    {:noreply, assign(socket, :nodes, updated_nodes)}
  end

  def handle_event("select_node", %{"id" => id}, socket) do
    {:noreply, assign(socket, :selected_node, id)}
  end

  def handle_event("clear_selection", _, socket) do
    socket =
      socket
      |> assign(:selected_node, nil)
      |> assign(:context_menu, %{visible: false, x: 0, y: 0, node_id: nil})
      |> assign(:node_creation_menu, %{visible: false, x: 0, y: 0, svg_x: 0, svg_y: 0, available_types: []})

    {:noreply, socket}
  end

  def handle_event("show_play_menu", _, socket) do
    # Load MIDI ports when showing the play menu
    case ModsynthGuiPhx.SynthManager.get_midi_ports() do
      {:ok, {midi_ports, port_map}} ->
        play_menu = %{
          visible: true,
          midi_ports: midi_ports,
          port_map: port_map,
          selected_port: if(length(midi_ports) > 0, do: List.first(midi_ports) |> elem(1), else: nil)
        }

        # Initialize MIDI file path and suggestions when showing the menu
        initial_suggestions = get_path_suggestions("")

        socket = socket
        |> assign(:play_menu, play_menu)
        |> assign(:midi_file_path, "")
        |> assign(:midi_file_suggestions, initial_suggestions)

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to get MIDI ports: #{reason}")}
    end
  end

  def handle_event("hide_play_menu", _, socket) do
    play_menu = %{socket.assigns.play_menu | visible: false}
    {:noreply, assign(socket, :play_menu, play_menu)}
  end

  def handle_event("select_midi_port", %{"port" => port}, socket) do
    play_menu = %{socket.assigns.play_menu | selected_port: String.to_atom(port)}
    {:noreply, assign(socket, :play_menu, play_menu)}
  end

  def handle_event("play_with_device", _, socket) do
    selected_port = socket.assigns.play_menu.selected_port
    port_map = socket.assigns.play_menu.port_map

    case Map.get(port_map, selected_port) do
      nil ->
        {:noreply, put_flash(socket, :error, "No MIDI device selected")}

      %{name: device_name} ->
        # Create current synth data from LiveView state
        current_synth_data = create_current_synth_data(socket)
        
        case ModsynthGuiPhx.SynthManager.play_synth_with_current_data(device_name, current_synth_data) do
          {:ok, {message, input_control_list, connection_list}} ->
            socket = socket
            |> put_flash(:info, message)
            |> assign(:play_menu, %{socket.assigns.play_menu | visible: false})
            |> assign(:mode, :run)
            |> assign(:input_control_list, input_control_list)
            |> assign(:connection_list, connection_list)
            {:noreply, socket}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, reason)}
        end
    end
  end

  def handle_event("update_midi_file_path", %{"path" => path}, socket) do
    suggestions = get_path_suggestions(path)
    socket = socket
    |> assign(:midi_file_path, path)
    |> assign(:midi_file_suggestions, suggestions)
    {:noreply, socket}
  end

  def handle_event("select_midi_file_suggestion", %{"path" => path}, socket) do
    # Check if the selected item is a directory by looking at the current suggestions
    current_suggestions = socket.assigns.midi_file_suggestions || []
    selected_suggestion = Enum.find(current_suggestions, fn s -> s.path == path end)

    # If it's a directory, append "/" and show directory contents
    # If it's a file, just set the path
    final_path = if selected_suggestion && selected_suggestion.is_directory do
      if String.ends_with?(path, "/"), do: path, else: "#{path}/"
    else
      path
    end

    suggestions = get_path_suggestions(final_path)
    socket = socket
    |> assign(:midi_file_path, final_path)
    |> assign(:midi_file_suggestions, suggestions)
    {:noreply, socket}
  end

  def handle_event("play_with_midi_file", _, socket) do
    midi_file_path = socket.assigns.midi_file_path

    if String.trim(midi_file_path) == "" do
      {:noreply, put_flash(socket, :error, "Please enter a MIDI file path")}
    else
      # Create current synth data from LiveView state
      current_synth_data = create_current_synth_data(socket)
      
      case ModsynthGuiPhx.SynthManager.play_midi_file_with_current_data(midi_file_path, current_synth_data) do
        {:ok, {message, input_control_list, connection_list}} ->
          socket = socket
          |> put_flash(:info, message)
          |> assign(:play_menu, %{socket.assigns.play_menu | visible: false})
          |> assign(:mode, :run)
          |> assign(:input_control_list, input_control_list)
          |> assign(:connection_list, connection_list)
          {:noreply, socket}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, reason)}
      end
    end
  end

  def handle_event("stop_synth", _, socket) do
    case ModsynthGuiPhx.SynthManager.stop_synth() do
      {:ok, message} ->
        socket = socket
        |> put_flash(:info, message)
        |> assign(:mode, :edit)
        |> assign(:input_control_list, [])
        |> assign(:connection_list, [])
        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}
    end
  end


  def handle_event("port_clicked", %{"node_id" => node_id, "port_type" => port_type, "port_index" => port_index}, socket) do
    node_id = String.to_integer(node_id)
    port_index = String.to_integer(port_index)

    connection_mode = socket.assigns.connection_mode

    cond do
      # First click - start connection from output port
      !connection_mode.active and port_type == "output" ->
        socket =
          socket
          |> assign(:connection_mode, %{
            active: true,
            from_node: node_id,
            from_port: port_index
          })
          |> put_flash(:info, "Connection started - click an input port to complete")

        {:noreply, socket}

      # Second click - complete connection to input port
      connection_mode.active and port_type == "input" ->
        case create_connection(socket, connection_mode.from_node, connection_mode.from_port, node_id, port_index) do
          {:ok, updated_socket} ->
            socket =
              updated_socket
              |> assign(:connection_mode, %{active: false, from_node: nil, from_port: nil})
              |> put_flash(:info, "Connection created successfully")

            {:noreply, socket}

          {:error, reason} ->
            socket =
              socket
              |> assign(:connection_mode, %{active: false, from_node: nil, from_port: nil})
              |> put_flash(:error, reason)

            {:noreply, socket}
        end

      # Cancel connection mode
      connection_mode.active ->
        socket =
          socket
          |> assign(:connection_mode, %{active: false, from_node: nil, from_port: nil})
          |> put_flash(:info, "Connection cancelled")

        {:noreply, socket}

      # Invalid start (trying to start from input port)
      true ->
        {:noreply, put_flash(socket, :error, "Connections must start from output ports (right side of nodes)")}
    end
  end

  def handle_event("connection_delete", %{"connection_id" => connection_id}, socket) do
    connection_index = String.to_integer(connection_id)

    updated_connections = List.delete_at(socket.assigns.connections, connection_index)

    socket =
      socket
      |> assign(:connections, updated_connections)
      |> put_flash(:info, "Connection deleted successfully")

    {:noreply, socket}
  end

  def handle_event("show_context_menu", %{"node_id" => node_id, "x" => x, "y" => y}, socket) do
    # node_id is already an integer from JavaScript
    socket =
      socket
      |> assign(:context_menu, %{
        visible: true,
        x: x,
        y: y,
        node_id: node_id
      })

    {:noreply, socket}
  end

  def handle_event("hide_context_menu", _, socket) do
    socket =
      socket
      |> assign(:context_menu, %{visible: false, x: 0, y: 0, node_id: nil})

    {:noreply, socket}
  end

  def handle_event("context_delete_node", %{"node_id" => node_id}, socket) do
    # node_id may come as string from template or integer from JS
    node_id = if is_binary(node_id), do: String.to_integer(node_id), else: node_id

    # Remove the node from the nodes list
    updated_nodes = Enum.reject(socket.assigns.nodes, &(&1["id"] == node_id))

    # Remove any connections that reference this node
    updated_connections =
      Enum.reject(socket.assigns.connections, fn conn ->
        conn["from_node"]["id"] == node_id || conn["to_node"]["id"] == node_id
      end)

    socket =
      socket
      |> assign(:nodes, updated_nodes)
      |> assign(:connections, updated_connections)
      |> assign(:selected_node, nil)
      |> assign(:connection_mode, %{active: false, from_node: nil, from_port: nil})
      |> assign(:context_menu, %{visible: false, x: 0, y: 0, node_id: nil})
      |> put_flash(:info, "Node deleted successfully")

    {:noreply, socket}
  end

  def handle_event("context_show_info", %{"node_id" => node_id}, socket) do
    # node_id may come as string from template or integer from JS
    node_id = if is_binary(node_id), do: String.to_integer(node_id), else: node_id
    node = Enum.find(socket.assigns.nodes, &(&1["id"] == node_id))

    socket =
      socket
      |> assign(:context_menu, %{visible: false, x: 0, y: 0, node_id: nil})
      |> assign(:node_info_modal, %{visible: true, node: node})

    {:noreply, socket}
  end

  def handle_event("close_node_info", _, socket) do
    socket =
      socket
      |> assign(:node_info_modal, %{visible: false, node: nil})

    {:noreply, socket}
  end

  def handle_event("show_node_creation_menu", %{"x" => x, "y" => y, "svg_x" => svg_x, "svg_y" => svg_y}, socket) do
    case ModsynthGuiPhx.SynthManager.get_available_node_types() do
      {:ok, node_types} ->
        # Convert the node types map to a sorted list for the menu
        available_types =
          Map.keys(node_types)
          |> Enum.sort()
          |> Enum.map(fn name ->
            {params, bus_type} = node_types[name]
            %{name: name, params: params, bus_type: bus_type}
          end)

        socket =
          socket
          |> assign(:node_creation_menu, %{
            visible: true,
            x: x,
            y: y,
            svg_x: svg_x,
            svg_y: svg_y,
            available_types: available_types
          })

        {:noreply, socket}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to get available node types: #{reason}")}
    end
  end

  def handle_event("hide_node_creation_menu", _, socket) do
    socket =
      socket
      |> assign(:node_creation_menu, %{visible: false, x: 0, y: 0, svg_x: 0, svg_y: 0, available_types: []})

    {:noreply, socket}
  end

  def handle_event("create_node", %{"node_type" => node_type}, socket) do
    # Check if this node type needs configuration
    if node_type in ["const", "cc-in"] do
      # Show configuration modal for const and cc-in nodes
      svg_x = socket.assigns.node_creation_menu.svg_x
      svg_y = socket.assigns.node_creation_menu.svg_y
      
      socket = socket
      |> assign(:node_config_modal, %{
        visible: true,
        node_type: node_type,
        svg_x: svg_x,
        svg_y: svg_y
      })
      |> assign(:node_creation_menu, %{visible: false, x: 0, y: 0, svg_x: 0, svg_y: 0, available_types: []})
      
      {:noreply, socket}
    else
      # Create node immediately for other types
      create_node_immediately(socket, node_type, nil, nil, nil, nil)
    end
  end

  def handle_event("update_node_value", %{"node_id" => node_id, "value" => value}, socket) do
    node_id = if is_binary(node_id), do: String.to_integer(node_id), else: node_id
    new_value = cond do
      is_number(value) -> value
      is_binary(value) ->
        case Float.parse(value) do
          {val, _} -> val
          :error -> 0.0
        end
      true -> 0.0
    end

    updated_nodes = Enum.map(socket.assigns.nodes, fn node ->
      if node["id"] == node_id and node["name"] in ["const", "cc-in"] do
        # Clamp value to min/max range
        min_val = node["min_val"] || 0.0
        max_val = node["max_val"] || 10.0
        clamped_value = max(min_val, min(max_val, new_value))

        Map.put(node, "val", clamped_value)
      else
        node
      end
    end)

    socket = assign(socket, :nodes, updated_nodes)
    
    # If in run mode, send the value to SuperCollider in real-time
    if socket.assigns.mode == :run do
      send_parameter_to_supercollider(socket, node_id, new_value)
    end

    {:noreply, socket}
  end

  def handle_event("hide_node_config_modal", _, socket) do
    socket = assign(socket, :node_config_modal, %{visible: false, node_type: nil, svg_x: 0, svg_y: 0})
    {:noreply, socket}
  end

  def handle_event("create_configured_node", params, socket) do
    %{
      "node_type" => node_type,
      "val" => val_str,
      "min_val" => min_val_str,
      "max_val" => max_val_str,
      "control" => control
    } = params
    
    # Parse values
    val = parse_float(val_str)
    min_val = parse_float(min_val_str)
    max_val = parse_float(max_val_str)
    
    # Validate ranges
    cond do
      min_val >= max_val ->
        {:noreply, put_flash(socket, :error, "Minimum value must be less than maximum value")}
      
      val < min_val || val > max_val ->
        {:noreply, put_flash(socket, :error, "Initial value must be between minimum and maximum values")}
      
      true ->
        create_node_immediately(socket, node_type, val, min_val, max_val, control)
    end
  end

  defp create_connection(socket, from_node_id, from_port, to_node_id, to_port) do
    # Validate that nodes exist
    from_node = Enum.find(socket.assigns.nodes, &(&1["id"] == from_node_id))
    to_node = Enum.find(socket.assigns.nodes, &(&1["id"] == to_node_id))

    cond do
      !from_node ->
        {:error, "Source node not found"}

      !to_node ->
        {:error, "Destination node not found"}

      from_node_id == to_node_id ->
        {:error, "Cannot connect a node to itself"}

      connection_exists?(socket.assigns.connections, from_node_id, from_port, to_node_id, to_port) ->
        {:error, "Connection already exists"}

      true ->
        new_connection = %{
          "from_node" => %{"id" => from_node_id, "port" => from_port},
          "to_node" => %{"id" => to_node_id, "port" => to_port}
        }

        updated_connections = [new_connection | socket.assigns.connections]

        {:ok, assign(socket, :connections, updated_connections)}
    end
  end

  defp connection_exists?(connections, from_node_id, from_port, to_node_id, to_port) do
    Enum.any?(connections, fn conn ->
      conn["from_node"]["id"] == from_node_id &&
      conn["from_node"]["port"] == from_port &&
      conn["to_node"]["id"] == to_node_id &&
      conn["to_node"]["port"] == to_port
    end)
  end

  defp convert_modsynth_nodes_to_ui_format(modsynth_nodes, original_nodes) do
    # Convert the map of Modsynth.Node structs to the UI format
    # Keep the original UI data but enrich it with parameter information
    Enum.map(original_nodes, fn ui_node ->
      enriched_node = case Map.get(modsynth_nodes, ui_node["id"]) do
        nil ->
          # Fallback to original node if not found in modsynth data
          ui_node

        modsynth_node ->
          # Enrich UI node with parameter information from Modsynth.Node
          Map.put(ui_node, "parameters", modsynth_node.parameters)
      end

      # Add min/max ranges for const and cc-in nodes
      add_node_ranges(enriched_node)
    end)
  end

  defp add_node_ranges(%{"name" => "const"} = node) do
    current_val = node["val"] || 5.0  # Default value if none exists

    # For existing const nodes: 0 to 2x current value
    # For new nodes without a value: 0 to 10
    {min_val, max_val} = if node["val"] do
      {0.0, current_val * 2.0}
    else
      {0.0, 10.0}
    end

    node
    |> Map.put("min_val", min_val)
    |> Map.put("max_val", max_val)
    |> Map.put("val", current_val)  # Ensure val is set
  end

  defp add_node_ranges(%{"name" => "cc-in"} = node) do
    current_val = node["val"] || 64.0  # Default MIDI value (0-127 range)

    # For cc-in nodes: default MIDI range 0-127
    # For new nodes without a value: 0 to 127
    {min_val, max_val} = if node["val"] do
      {0.0, 127.0}
    else
      {0.0, 127.0}
    end

    node
    |> Map.put("min_val", min_val)
    |> Map.put("max_val", max_val)
    |> Map.put("val", current_val)  # Ensure val is set
  end

  defp add_node_ranges(node), do: node

  defp convert_enriched_nodes_to_original_format(enriched_nodes) do
    # Remove the enriched parameters field added during loading to restore the original format
    # Keep min_val and max_val as they are used for knob ranges in const widgets
    Enum.map(enriched_nodes, fn node ->
      Map.delete(node, "parameters")
    end)
  end

  defp convert_connections_to_port_format(connections, nodes) do
    require Logger
    Logger.debug("Converting #{length(connections)} connections to port format")

    Enum.map(connections, fn conn ->
      Logger.debug("Original connection: #{inspect(conn)}")

      # Find the from and to nodes
      from_node = Enum.find(nodes, &(&1["id"] == conn["from_node"]["id"]))
      to_node = Enum.find(nodes, &(&1["id"] == conn["to_node"]["id"]))

      if from_node && to_node do
        # Get port information for both nodes
        from_ports = get_node_ports(from_node)
        to_ports = get_node_ports(to_node)

        # Find the port indices based on parameter names
        from_param = conn["from_node"]["param_name"]
        to_param = conn["to_node"]["param_name"]

        from_port_index = Enum.find_index(from_ports.outputs, &(&1 == from_param)) || 0
        to_port_index = Enum.find_index(to_ports.inputs, &(&1 == to_param)) || 0

        Logger.debug("Param mapping: #{from_param} -> port #{from_port_index}, #{to_param} -> port #{to_port_index}")

        # Convert to port-based format
        converted = %{
          "from_node" => %{"id" => conn["from_node"]["id"], "port" => from_port_index},
          "to_node" => %{"id" => conn["to_node"]["id"], "port" => to_port_index}
        }

        Logger.debug("Converted connection: #{inspect(converted)}")
        converted
      else
        Logger.warning("Could not find nodes for connection: #{inspect(conn)}")
        # Fallback to original format if nodes not found
        conn
      end
    end)
  end

  defp convert_connections_to_param_format(connections, nodes) do
    require Logger
    Logger.debug("Converting #{length(connections)} connections to parameter format")

    Enum.map(connections, fn conn ->
      Logger.debug("Port-based connection: #{inspect(conn)}")

      # Find the from and to nodes
      from_node = Enum.find(nodes, &(&1["id"] == conn["from_node"]["id"]))
      to_node = Enum.find(nodes, &(&1["id"] == conn["to_node"]["id"]))

      if from_node && to_node do
        # Get port information for both nodes
        from_ports = get_node_ports(from_node)
        to_ports = get_node_ports(to_node)

        # Get the port indices
        from_port_index = conn["from_node"]["port"] || 0
        to_port_index = conn["to_node"]["port"] || 0

        # Convert port indices back to parameter names
        from_param = Enum.at(from_ports.outputs, from_port_index) || "out"
        to_param = Enum.at(to_ports.inputs, to_port_index) || "in"

        Logger.debug("Port mapping: port #{from_port_index} -> #{from_param}, port #{to_port_index} -> #{to_param}")

        # Convert to parameter-based format
        converted = %{
          "from_node" => %{"id" => conn["from_node"]["id"], "name" => from_node["name"], "param_name" => from_param},
          "to_node" => %{"id" => conn["to_node"]["id"], "name" => to_node["name"], "param_name" => to_param}
        }

        Logger.debug("Converted connection: #{inspect(converted)}")
        converted
      else
        Logger.warning("Could not find nodes for connection: #{inspect(conn)}")
        # Fallback to original format if nodes not found
        conn
      end
    end)
  end

  defp get_node_ports(node) do
    # Try to get parameter information from the enriched node data
    case Map.get(node, "parameters") do
      nil ->
        # Fallback to name-based mapping if no parameter data available
        get_node_ports_fallback(node["name"])

      parameters ->
        # Debug logging to understand the parameter structure
        require Logger
        Logger.debug("Parameters structure for node #{node["name"]}: #{inspect(parameters)}")

        # Extract input and output parameter names from the Modsynth.Node parameters
        # Parameters can be in different formats, handle both tuples and lists
        all_param_names = Enum.map(parameters, fn
          {param_name, _param_spec} when is_binary(param_name) -> param_name
          [param_name, _param_value] when is_binary(param_name) -> param_name
          param_name when is_binary(param_name) -> param_name
          other ->
            Logger.warning("Unknown parameter format: #{inspect(other)}")
            nil
        end)
        |> Enum.reject(&is_nil/1)

        # Separate inputs and outputs based on naming convention
        # Outputs use "out_" prefix (out_audio, out_freq, out_val, out_1, out_2, etc.)
        # Inputs use descriptive names (in, freq, gain, cutoff, etc.)
        output_params = Enum.filter(all_param_names, fn name ->
          String.starts_with?(name, "out_")
        end)

        input_params = Enum.reject(all_param_names, fn name ->
          String.starts_with?(name, "out_")
        end)

        # Ensure we have at least one output
        final_outputs = if Enum.empty?(output_params) do
          ["out"]
        else
          output_params
        end

        Logger.debug("Extracted ports - inputs: #{inspect(input_params)}, outputs: #{inspect(final_outputs)}")

        %{inputs: input_params, outputs: final_outputs}
    end
  end

  defp get_node_ports_fallback(node_name) do
    case node_name do
      # Oscillators
      "saw-osc" -> %{inputs: ["freq"], outputs: ["out_audio"]}
      "square-osc" -> %{inputs: ["freq", "width"], outputs: ["out_audio"]}
      "s_sin-osc" -> %{inputs: ["freq"], outputs: ["out_audio"]}
      "sin-vco" -> %{inputs: ["freq"], outputs: ["out_control"]}

      # Filters
      "moog-filt" -> %{inputs: ["in", "cutoff", "lpf_res"], outputs: ["out_audio"]}
      "bp-filt" -> %{inputs: ["in", "freq", "q"], outputs: ["out_audio"]}
      "lp-filt" -> %{inputs: ["in", "cutoff"], outputs: ["out_audio"]}
      "hp-filt" -> %{inputs: ["in", "cutoff"], outputs: ["out_audio"]}

      # Amplifiers
      "amp" -> %{inputs: ["in", "gain"], outputs: ["out_audio"]}

      # Envelopes
      "adsr-env" -> %{inputs: ["in", "attack", "decay", "sustain", "release", "gate"], outputs: ["out_audio"]}
      "perc-env" -> %{inputs: ["in", "attack", "release", "gate"], outputs: ["out_audio"]}

      # Effects
      "freeverb" -> %{inputs: ["in", "wet_dry", "room_size", "dampening"], outputs: ["out_audio"]}
      "echo" -> %{inputs: ["in", "delay_time", "decay_time"], outputs: ["out_audio"]}

      # Utilities
      "const" -> %{inputs: ["in"], outputs: ["out_val"]}
      "c-splitter" -> %{inputs: ["in"], outputs: ["out_1", "out_2"]}
      "a-splitter" -> %{inputs: ["in", "pos", "lev"], outputs: ["out_1", "out_2"]}
      "pct-add" -> %{inputs: ["in", "gain"], outputs: ["out_control"]}
      "c-scale" -> %{inputs: ["in", "in_lo", "in_hi", "out_lo", "out_hi"], outputs: ["out_control"]}
      "mult" -> %{inputs: ["in", "gain"], outputs: ["out_audio"]}
      "val-add" -> %{inputs: ["in", "val"], outputs: ["out_control"]}

      # Input/Output
      "midi-in" -> %{inputs: ["note"], outputs: ["out_freq"]}
      "midi-in-note" -> %{inputs: ["note"], outputs: ["out_note"]}
      "audio-out" -> %{inputs: ["b1", "b2"], outputs: []}
      "audio-in" -> %{inputs: [], outputs: ["out_audio"]}
      "cc-in" -> %{inputs: ["in"], outputs: ["out_val"]}
      "rand-in" -> %{inputs: ["lo", "hi", "trig"], outputs: ["out_val"]}

      # Control
      "note-freq" -> %{inputs: ["note"], outputs: ["out_freq"]}

      # Default fallback
      _ -> %{inputs: ["in"], outputs: ["out_audio"]}
    end
  end

  @impl true
  @spec render(any()) :: Phoenix.LiveView.Rendered.t()
  def render(assigns) do
    ~H"""
    <div id="main-container" class="h-screen bg-gray-900 text-white overflow-hidden" phx-hook="ViewportResize">
      <!-- Header -->
      <div class="bg-gray-800 p-2 flex items-center justify-between border-b border-gray-700">
        <div class="flex items-center space-x-4">
          <h1 class="text-xl font-bold">Modular Synthesizer Editor</h1>
          <%= if @current_filename do %>
            <div class="flex items-center space-x-2 px-3 py-1 bg-blue-600 rounded-full">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path>
              </svg>
              <span class="text-sm font-medium"><%= @current_filename %></span>
            </div>
          <% end %>
          <%= if @connection_mode.active do %>
            <div class="flex items-center space-x-2 px-3 py-1 bg-orange-600 rounded-full">
              <div class="w-2 h-2 bg-white rounded-full animate-pulse"></div>
              <span class="text-sm font-medium">Connection Mode - Click input port to connect</span>
            </div>
          <% end %>
          
          <!-- Mode Indicator -->
          <div class={[
            "flex items-center space-x-2 px-3 py-1 rounded-full",
            if(@mode == :run, do: "bg-green-600", else: "bg-gray-600")
          ]}>
            <div class={[
              "w-2 h-2 rounded-full",
              if(@mode == :run, do: "bg-white animate-pulse", else: "bg-gray-300")
            ]}></div>
            <span class="text-sm font-medium">
              <%= if @mode == :run, do: "RUN MODE - Live parameters", else: "EDIT MODE" %>
            </span>
          </div>
        </div>

        <div class="flex items-center space-x-4">
          <button
            phx-click="toggle_file_browser"
            class="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded text-sm"
          >
            <%= if @show_file_browser, do: "Hide Files", else: "Load File" %>
          </button>

          <div class="text-xs text-gray-400">
            Canvas: <%= @canvas_size.width %>×<%= @canvas_size.height %> |
            Nodes: <%= length(@nodes) %> |
            Connections: <%= length(@connections) %>
          </div>

          <div class="flex items-center space-x-2">
            <div class="relative">
              <button
                phx-click="show_play_menu"
                class="px-4 py-2 bg-green-600 hover:bg-green-700 rounded text-sm flex items-center space-x-1"
                disabled={@current_synth == nil}
              >
                <span>Play</span>
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 9l-7 7-7-7"></path>
                </svg>
              </button>

              <%= if @play_menu.visible do %>
                <div class="absolute left-0 mt-1 w-80 bg-white rounded-md shadow-lg z-50 border border-gray-200">
                  <div class="p-4 space-y-4">
                    <div class="flex justify-between items-center">
                      <h3 class="text-lg font-semibold text-gray-800">Play Options</h3>
                      <button phx-click="hide_play_menu" class="text-gray-500 hover:text-gray-700">
                        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                        </svg>
                      </button>
                    </div>

                    <div class="space-y-3">
                      <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">Play with Device</label>
                        <div class="flex space-x-2">
                          <select
                            phx-change="select_midi_port"
                            name="port"
                            class="flex-1 px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                          >
                            <%= for {name, key} <- @play_menu.midi_ports do %>
                              <option value={key} selected={key == @play_menu.selected_port}><%= name %></option>
                            <% end %>
                          </select>
                          <button
                            phx-click="play_with_device"
                            class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-md text-sm"
                          >
                            Play
                          </button>
                        </div>
                      </div>

                      <div>
                        <label class="block text-sm font-medium text-gray-700 mb-2">Play MIDI File</label>
                        <div class="flex space-x-2 relative">
                          <div class="flex-1 relative">
                            <input
                              type="text"
                              placeholder="Enter MIDI file path..."
                              value={@midi_file_path}
                              phx-change="update_midi_file_path"
                              name="path"
                              class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500"
                            />
                            <%= if length(@midi_file_suggestions) > 0 do %>
                              <div class="absolute top-full left-0 right-0 bg-white border border-gray-300 rounded-md shadow-lg mt-1 max-h-40 overflow-y-auto z-10">
                                <%= for suggestion <- @midi_file_suggestions do %>
                                  <div
                                    phx-click="select_midi_file_suggestion"
                                    phx-value-path={suggestion.path}
                                    class="px-3 py-2 hover:bg-gray-100 cursor-pointer flex items-center"
                                  >
                                    <%= if suggestion.is_directory do %>
                                      <svg class="w-4 h-4 mr-2 text-blue-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 7v10a2 2 0 002 2h14a2 2 0 002-2V9a2 2 0 00-2-2h-5l-2-2H5a2 2 0 00-2 2z"></path>
                                      </svg>
                                    <% else %>
                                      <svg class="w-4 h-4 mr-2 text-green-500" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19V6l12-3v13M9 19c0 1.105-.895 2-2 2s-2-.895-2-2 .895-2 2-2 2 .895 2 2zm12-3c0 1.105-.895 2-2 2s-2-.895-2-2 .895-2 2-2 2 .895 2 2z"></path>
                                      </svg>
                                    <% end %>
                                    <span class="text-sm text-gray-800"><%= suggestion.display_name %></span>
                                  </div>
                                <% end %>
                              </div>
                            <% end %>
                          </div>
                          <button
                            phx-click="play_with_midi_file"
                            class="px-4 py-2 bg-purple-600 hover:bg-purple-700 text-white rounded-md text-sm"
                          >
                            Play
                          </button>
                        </div>
                        <p class="text-xs text-gray-500 mt-1">
                          Tip: Type to see available MIDI files and folders. Use ".." to go up a directory.
                        </p>
                      </div>
                    </div>
                  </div>
                </div>
              <% end %>
            </div>

            <button
              phx-click="stop_synth"
              class="px-4 py-2 bg-red-600 hover:bg-red-700 rounded text-sm"
              disabled={@current_synth == nil}
            >
              Stop
            </button>
          </div>

          <div class="flex items-center space-x-2">
            <form phx-submit="save_file" class="flex items-center space-x-2">
              <input
                type="text"
                name="filename"
                placeholder="Enter filename"
                value={@new_filename}
                phx-change="update_filename"
                class="px-3 py-1 bg-gray-700 rounded text-sm"
              />
              <button
                type="submit"
                class="px-4 py-2 bg-green-600 hover:bg-green-700 rounded text-sm"
              >
                Save
              </button>
            </form>
          </div>
        </div>
      </div>

      <!-- Main Content -->
      <div class="flex" style={"height: calc(100vh - 60px)"}>
        <!-- File Browser Sidebar -->
        <div class={["transition-all duration-300 bg-gray-800 overflow-hidden", if(@show_file_browser, do: "w-64", else: "w-0")]}>
          <div class="p-4 h-full overflow-y-auto">
            <h3 class="text-lg font-semibold mb-4">Files</h3>

            <!-- All Files (Combined and Sorted) -->
            <div class="space-y-1 overflow-y-auto" style="max-height: calc(100vh - 140px);">
              <%= for file <- @all_files do %>
                <button
                  phx-click="load_file"
                  phx-value-path={file.path}
                  class="w-full text-left px-2 py-1 text-sm hover:bg-gray-700 rounded flex items-center justify-between"
                >
                  <span class="flex-1 truncate"><%= file.name %></span>
                  <span class={[
                    "text-xs px-2 py-0.5 rounded-full ml-2 flex-shrink-0",
                    if(file.category == "User", do: "bg-blue-600 text-blue-100", else: "bg-green-600 text-green-100")
                  ]}>
                    <%= if file.category == "User", do: "user", else: "example" %>
                  </span>
                </button>
              <% end %>
            </div>
          </div>
        </div>

        <!-- Canvas Area -->
        <div class="flex-1 relative overflow-auto" id="canvas-container">
          <svg
            id="synth-canvas"
            class="bg-gray-900"
            width={@canvas_size.width}
            height={@canvas_size.height}
            viewBox={"0 0 #{@canvas_size.width} #{@canvas_size.height}"}
            phx-hook="SynthCanvas"
            phx-click="clear_selection"
            phx-click-away="hide_context_menu"
          >
            <!-- Grid Pattern -->
            <defs>
              <pattern id="grid" width="20" height="20" patternUnits="userSpaceOnUse">
                <path d="M 20 0 L 0 0 0 20" fill="none" stroke="#374151" stroke-width="1" opacity="0.3"/>
              </pattern>
            </defs>
            <rect width="100%" height="100%" fill="url(#grid)" />

            <!-- Connections -->
            <%= for {connection, index} <- Enum.with_index(@connections) do %>
              <.connection_cable
                connection={connection}
                nodes={@nodes}
                connection_id={index}
              />
            <% end %>

            <!-- Nodes -->
            <%= for node <- @nodes do %>
              <.synth_node
                node={node}
                selected={@selected_node == node["id"]}
                connection_mode={@connection_mode}
              />
            <% end %>
          </svg>
        </div>
      </div>

      <!-- Context Menu -->
      <%= if @context_menu.visible do %>
        <div
          class="absolute bg-gray-800 border border-gray-600 rounded-lg shadow-lg z-50 py-2 min-w-40"
          style={"left: #{@context_menu.x}px; top: #{@context_menu.y}px;"}
          phx-click-away="hide_context_menu"
        >
          <button
            phx-click="context_show_info"
            phx-value-node_id={@context_menu.node_id}
            class="w-full text-left px-4 py-2 text-sm text-white hover:bg-gray-700 flex items-center"
          >
            <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 16h-1v-4h-1m1-4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z"></path>
            </svg>
            Node Info
          </button>
          <hr class="border-gray-600 my-1" />
          <button
            phx-click="context_delete_node"
            phx-value-node_id={@context_menu.node_id}
            class="w-full text-left px-4 py-2 text-sm text-red-400 hover:bg-red-900 hover:text-red-300 flex items-center"
            onclick="return confirm('Are you sure you want to delete this node and all its connections?')"
          >
            <svg class="w-4 h-4 mr-2" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>
            </svg>
            Delete Node
          </button>
        </div>
      <% end %>

      <!-- Node Creation Menu -->
      <%= if @node_creation_menu.visible do %>
        <div
          class="absolute bg-gray-800 border border-gray-600 rounded-lg shadow-lg z-50 py-2 max-w-xs max-h-96 overflow-y-auto"
          style={"left: #{@node_creation_menu.x}px; top: #{@node_creation_menu.y}px;"}
          phx-click-away="hide_node_creation_menu"
        >
          <div class="px-4 py-2 text-xs text-gray-400 border-b border-gray-600">
            Create New Node
          </div>
          <%= for node_type <- @node_creation_menu.available_types do %>
            <button
              phx-click="create_node"
              phx-value-node_type={node_type.name}
              class="w-full text-left px-4 py-2 text-sm text-white hover:bg-gray-700 flex items-center justify-between"
            >
              <span class="font-mono"><%= node_type.name %></span>
              <span class="text-xs text-gray-400">
                <%= case node_type.bus_type do %>
                  <% :audio -> %>🎵
                  <% :control -> %>🎛️
                  <% _ -> %>⚡
                <% end %>
              </span>
            </button>
          <% end %>
        </div>
      <% end %>

      <!-- Node Info Modal -->
      <%= if @node_info_modal.visible && @node_info_modal.node do %>
        <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50" phx-click="close_node_info">
          <div class="bg-gray-800 border border-gray-600 rounded-lg shadow-xl max-w-md w-full mx-4" phx-click="phx-click-away">
            <!-- Modal Header -->
            <div class="flex items-center justify-between p-4 border-b border-gray-600">
              <h3 class="text-lg font-semibold text-white">
                <%= String.upcase(@node_info_modal.node["name"]) %> - Node <%= @node_info_modal.node["id"] %>
              </h3>
              <button
                phx-click="close_node_info"
                class="text-gray-400 hover:text-white"
              >
                <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                </svg>
              </button>
            </div>

            <!-- Modal Content -->
            <div class="p-4 space-y-4">
              <!-- Basic Info -->
              <div>
                <h4 class="text-sm font-medium text-gray-300 mb-2">Basic Information</h4>
                <div class="bg-gray-900 rounded p-3 text-sm">
                  <div class="grid grid-cols-2 gap-2">
                    <div><span class="text-gray-400">ID:</span> <%= @node_info_modal.node["id"] %></div>
                    <div><span class="text-gray-400">Type:</span> <%= @node_info_modal.node["name"] %></div>
                    <div><span class="text-gray-400">X:</span> <%= @node_info_modal.node["x"] || 0 %></div>
                    <div><span class="text-gray-400">Y:</span> <%= @node_info_modal.node["y"] || 0 %></div>
                  </div>
                  <%= if @node_info_modal.node["val"] do %>
                    <div class="mt-2"><span class="text-gray-400">Value:</span> <%= @node_info_modal.node["val"] %></div>
                  <% end %>
                  <%= if @node_info_modal.node["control"] do %>
                    <div class="mt-2"><span class="text-gray-400">Control:</span> <%= @node_info_modal.node["control"] %></div>
                  <% end %>
                </div>
              </div>

              <!-- Ports Information -->
              <div>
                <h4 class="text-sm font-medium text-gray-300 mb-2">Ports</h4>
                <div class="bg-gray-900 rounded p-3 text-sm">
                  <% ports = get_node_ports(@node_info_modal.node) %>
                  <div class="grid grid-cols-2 gap-4">
                    <div>
                      <div class="text-green-400 font-medium mb-1">Inputs</div>
                      <%= if Enum.empty?(ports.inputs) do %>
                        <div class="text-gray-500 italic">None</div>
                      <% else %>
                        <%= for {input, index} <- Enum.with_index(ports.inputs) do %>
                          <div class="font-mono text-xs">
                            <span class="text-gray-400"><%= index %>:</span> <%= input %>
                          </div>
                        <% end %>
                      <% end %>
                    </div>
                    <div>
                      <div class="text-orange-400 font-medium mb-1">Outputs</div>
                      <%= if Enum.empty?(ports.outputs) do %>
                        <div class="text-gray-500 italic">None</div>
                      <% else %>
                        <%= for {output, index} <- Enum.with_index(ports.outputs) do %>
                          <div class="font-mono text-xs">
                            <span class="text-gray-400"><%= index %>:</span> <%= output %>
                          </div>
                        <% end %>
                      <% end %>
                    </div>
                  </div>
                </div>
              </div>

              <!-- Raw Parameters (if available) -->
              <%= if Map.get(@node_info_modal.node, "parameters") do %>
                <div>
                  <h4 class="text-sm font-medium text-gray-300 mb-2">Raw Parameters</h4>
                  <div class="bg-gray-900 rounded p-3 text-xs font-mono max-h-32 overflow-y-auto">
                    <%= inspect(@node_info_modal.node["parameters"], pretty: true) %>
                  </div>
                </div>
              <% end %>
            </div>

            <!-- Modal Footer -->
            <div class="flex justify-end p-4 border-t border-gray-600">
              <button
                phx-click="close_node_info"
                class="px-4 py-2 bg-gray-600 hover:bg-gray-700 text-white rounded"
              >
                Close
              </button>
            </div>
          </div>
        </div>
      <% end %>
      
      <!-- Node Configuration Modal -->
      <%= if @node_config_modal.visible do %>
        <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50" phx-click="hide_node_config_modal">
          <div class="bg-gray-800 border border-gray-600 rounded-lg shadow-xl max-w-md w-full mx-4" phx-click="phx-click-away">
            <!-- Modal Header -->
            <div class="flex items-center justify-between p-4 border-b border-gray-600">
              <h3 class="text-lg font-semibold text-white">
                Configure <%= String.upcase(@node_config_modal.node_type) %> Node
              </h3>
              <button
                phx-click="hide_node_config_modal"
                class="text-gray-400 hover:text-white"
              >
                <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                  <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12"></path>
                </svg>
              </button>
            </div>

            <!-- Modal Content -->
            <form phx-submit="create_configured_node" class="p-4 space-y-4">
              <input type="hidden" name="node_type" value={@node_config_modal.node_type} />
              
              <!-- Initial Value -->
              <div>
                <label class="block text-sm font-medium text-gray-300 mb-2">Initial Value</label>
                <input
                  type="number"
                  name="val"
                  step="0.1"
                  value={if @node_config_modal.node_type == "const", do: "5.0", else: "64.0"}
                  class="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-md text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                  required
                />
              </div>

              <!-- Minimum Value -->
              <div>
                <label class="block text-sm font-medium text-gray-300 mb-2">Minimum Value</label>
                <input
                  type="number"
                  name="min_val"
                  step="0.1"
                  value={if @node_config_modal.node_type == "const", do: "0.0", else: "0.0"}
                  class="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-md text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                  required
                />
              </div>

              <!-- Maximum Value -->
              <div>
                <label class="block text-sm font-medium text-gray-300 mb-2">Maximum Value</label>
                <input
                  type="number"
                  name="max_val"
                  step="0.1"
                  value={if @node_config_modal.node_type == "const", do: "10.0", else: "127.0"}
                  class="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-md text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                  required
                />
              </div>

              <!-- Control Type (for cc-in nodes) -->
              <%= if @node_config_modal.node_type == "cc-in" do %>
                <div>
                  <label class="block text-sm font-medium text-gray-300 mb-2">MIDI Control Type</label>
                  <select
                    name="control"
                    class="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded-md text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
                  >
                    <option value="">None</option>
                    <option value="note">Note</option>
                    <option value="gain">Gain</option>
                  </select>
                </div>
              <% else %>
                <input type="hidden" name="control" value="" />
              <% end %>

              <!-- Modal Footer -->
              <div class="flex justify-end space-x-3 pt-4 border-t border-gray-600">
                <button
                  type="button"
                  phx-click="hide_node_config_modal"
                  class="px-4 py-2 bg-gray-600 hover:bg-gray-700 text-white rounded"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  class="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded"
                >
                  Create Node
                </button>
              </div>
            </form>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  def synth_node(assigns) do
    # Determine node color based on type
    node_color = case assigns.node["name"] do
      "midi-in" -> "#EC4899"      # Pink for MIDI input
      "piano-in" -> "#EC4899"     # Pink for piano input
      "audio-in" -> "#EC4899"     # Pink for audio input
      "audio-out" -> "#EC4899"    # Pink for audio output
      name when name in ["saw-osc", "square-osc", "sine-osc"] -> "#F59E0B"  # Orange for oscillators
      name when name in ["moog-filt", "lp-filt", "hp-filt"] -> "#10B981"   # Green for filters
      name when name in ["amp", "perc-env", "release"] -> "#8B5CF6"        # Purple for amplifiers/envelopes
      name when name in ["const", "slider-ctl", "cc-in"] -> "#6B7280"      # Gray for controls
      name when name in ["reverb", "echo", "delay"] -> "#3B82F6"           # Blue for effects
      _ -> "#4B5563"  # Default gray
    end

    # Get port information for this node
    ports = get_node_ports(assigns.node)
    max_ports = max(length(ports.inputs), length(ports.outputs))
    node_height = max(80, 40 + max_ports * 20)  # Dynamic height based on port count

    assigns = assign(assigns, :node_color, node_color)
    assigns = assign(assigns, :ports, ports)
    assigns = assign(assigns, :node_height, node_height)

    ~H"""
    <g
      id={"node-#{@node["id"]}"}
      class="cursor-move"
      phx-click="select_node"
      phx-value-id={@node["id"]}
      transform={"translate(#{@node["x"] || 0}, #{@node["y"] || 0})"}
    >
      <!-- Node Shadow -->
      <rect
        x="2" y="2"
        width="140"
        height={@node_height}
        rx="8"
        fill="rgba(0,0,0,0.3)"
      />

      <!-- Node Body -->
      <rect
        width="140"
        height={@node_height}
        rx="8"
        fill={if @selected, do: "#1F2937", else: "#374151"}
        stroke={if @selected, do: "#60A5FA", else: "#4B5563"}
        stroke-width="2"
      />

      <!-- Node Header -->
      <rect
        width="140"
        height="20"
        rx="8"
        fill={@node_color}
      />
      <rect
        y="12"
        width="140"
        height="8"
        fill={@node_color}
      />

      <!-- Node Label -->
      <text
        x="70"
        y="14"
        text-anchor="middle"
        dominant-baseline="middle"
        class="text-xs font-bold fill-white"
      >
        <%= String.upcase(@node["name"]) %>
      </text>

      <!-- Node ID -->
      <text
        x="70"
        y="32"
        text-anchor="middle"
        dominant-baseline="middle"
        class="text-xs fill-gray-300"
      >
        ID: <%= @node["id"] %>
      </text>

      <!-- Const and CC-in Node Knob and Value Display -->
      <%= if @node["name"] in ["const", "cc-in"] do %>
        <.control_knob node={@node} />
      <% else %>
        <!-- Parameter/Control Display for non-const nodes -->
        <%= if @node["control"] do %>
          <text
            x="70"
            y={@node_height - 15}
            text-anchor="middle"
            dominant-baseline="middle"
            class="text-xs fill-gray-300"
          >
            <%= @node["control"] %>
          </text>
        <% end %>

        <%= if @node["val"] do %>
          <text
            x="70"
            y={@node_height - 5}
            text-anchor="middle"
            dominant-baseline="middle"
            class="text-xs fill-yellow-400"
          >
            <%= @node["val"] %>
          </text>
        <% end %>
      <% end %>

      <!-- Input Jacks (Left Side) -->
      <%= for {input_name, index} <- Enum.with_index(@ports.inputs) do %>
        <g
          phx-click="port_clicked"
          phx-value-node_id={@node["id"]}
          phx-value-port_type="input"
          phx-value-port_index={index}
          class="cursor-pointer"
          style="pointer-events: all;"
        >
          <circle cx="8" cy={45 + index * 20} r="6" fill="#2D3748" stroke="#4A5568" stroke-width="2" class="input-jack" />
          <circle
            cx="8"
            cy={45 + index * 20}
            r="3"
            fill={if @connection_mode.active, do: "#EF4444", else: "#10B981"}
            class="input-port"
          />
          <%= if @connection_mode.active do %>
            <circle cx="8" cy={45 + index * 20} r="8" fill="none" stroke="#EF4444" stroke-width="2" opacity="0.7" />
          <% end %>
          <!-- Port Label -->
          <text
            x="18"
            y={45 + index * 20 + 1}
            text-anchor="start"
            dominant-baseline="middle"
            class="text-xs fill-gray-300 font-mono"
          >
            <%= input_name %>
          </text>
        </g>
      <% end %>

      <!-- Output Jacks (Right Side) -->
      <%= for {output_name, index} <- Enum.with_index(@ports.outputs) do %>
        <g
          phx-click="port_clicked"
          phx-value-node_id={@node["id"]}
          phx-value-port_type="output"
          phx-value-port_index={index}
          class="cursor-pointer"
          style="pointer-events: all;"
        >
          <circle cx="132" cy={45 + index * 20} r="6" fill="#2D3748" stroke="#4A5568" stroke-width="2" class="output-jack" />
          <circle
            cx="132"
            cy={45 + index * 20}
            r="3"
            fill={if @connection_mode.active && @connection_mode.from_node == @node["id"] && @connection_mode.from_port == index, do: "#10B981", else: "#F59E0B"}
            class="output-port"
          />
          <%= if !@connection_mode.active do %>
            <circle cx="132" cy={45 + index * 20} r="8" fill="none" stroke="#60A5FA" stroke-width="1" opacity="0.5" />
          <% end %>
          <!-- Port Label -->
          <text
            x="122"
            y={45 + index * 20 + 1}
            text-anchor="end"
            dominant-baseline="middle"
            class="text-xs fill-gray-300 font-mono"
          >
            <%= output_name %>
          </text>
        </g>
      <% end %>

      <!-- LED indicator -->
      <circle cx="125" cy="15" r="2" fill={if @selected, do: "#10B981", else: "#374151"} />

      <!-- Screws (hardware aesthetic) -->
      <circle cx="15" cy="25" r="1" fill="#6B7280" />
      <circle cx="125" cy="25" r="1" fill="#6B7280" />
      <circle cx="15" cy="65" r="1" fill="#6B7280" />
      <circle cx="125" cy="65" r="1" fill="#6B7280" />
    </g>
    """
  end

  def connection_cable(assigns) do
    from_node = Enum.find(assigns.nodes, &(&1["id"] == assigns.connection["from_node"]["id"]))
    to_node = Enum.find(assigns.nodes, &(&1["id"] == assigns.connection["to_node"]["id"]))

    if from_node && to_node do
      # Calculate port positions based on port index
      from_port = assigns.connection["from_node"]["port"] || 0
      to_port = assigns.connection["to_node"]["port"] || 0

      # Output ports are on the right side (x=132), input ports on left (x=8)
      # Ports start at y=45 and are spaced 20px apart
      from_x = (from_node["x"] || 0) + 132
      from_y = (from_node["y"] || 0) + 45 + (from_port * 20)
      to_x = (to_node["x"] || 0) + 8
      to_y = (to_node["y"] || 0) + 45 + (to_port * 20)

      # Create a curved path for the cable (more realistic patch cable look)
      control_x1 = from_x + 60
      control_y1 = from_y
      control_x2 = to_x - 60
      control_y2 = to_y

      path = "M #{from_x} #{from_y} C #{control_x1} #{control_y1} #{control_x2} #{control_y2} #{to_x} #{to_y}"

      # Determine cable color based on connection type
      cable_color = case {from_node["name"], to_node["name"]} do
        {from, _to} when from in ["midi-in", "piano-in"] -> "#EC4899"  # Pink for MIDI
        {from, _to} when from in ["saw-osc", "square-osc", "sine-osc"] -> "#F59E0B"  # Orange for audio
        {from, _to} when from in ["moog-filt", "lp-filt", "hp-filt"] -> "#10B981"  # Green for processed audio
        {from, _to} when from in ["const", "slider-ctl", "cc-in"] -> "#6B7280"  # Gray for control signals
        _ -> "#EF4444"  # Default red
      end

      assigns = assign(assigns, :path, path)
      assigns = assign(assigns, :cable_color, cable_color)

      ~H"""
      <g
        phx-click="connection_delete"
        phx-value-connection_id={@connection_id}
        class="cursor-pointer"
        style="pointer-events: all;"
      >
        <!-- Cable Shadow -->
        <path
          d={@path}
          fill="none"
          stroke="rgba(0,0,0,0.3)"
          stroke-width="5"
          stroke-linecap="round"
          transform="translate(1,1)"
        />

        <!-- Main Cable -->
        <path
          d={@path}
          fill="none"
          stroke={@cable_color}
          stroke-width="4"
          stroke-linecap="round"
          class="connection-cable"
        />

        <!-- Cable Highlight -->
        <path
          d={@path}
          fill="none"
          stroke="rgba(255,255,255,0.3)"
          stroke-width="1"
          stroke-linecap="round"
          class="connection-highlight"
        />

        <!-- Invisible wider area for easier clicking -->
        <path
          d={@path}
          fill="none"
          stroke="transparent"
          stroke-width="12"
          stroke-linecap="round"
          class="connection-clickarea"
        />
      </g>
      """
    else
      ~H""
    end
  end

  defp control_knob(assigns) do
    # Calculate knob position and size based on available space
    assigns = assign(assigns, :knob_center_x, 70)
    assigns = assign(assigns, :knob_center_y, 55)
    assigns = assign(assigns, :knob_radius, 12)

    # Calculate current angle based on value (0-270 degrees for better visual feedback)
    current_val = case assigns.node["val"] do
      nil -> 0.0
      val when is_number(val) -> val / 1.0
      _ -> 0.0
    end
    assigns = assign(assigns, :current_val, current_val)
    min_val = case assigns.node["min_val"] do
      nil -> 0.0
      val when is_number(val) -> val / 1.0
      _ -> 0.0
    end
    max_val = case assigns.node["max_val"] do
      nil -> 10.0
      val when is_number(val) -> val / 1.0
      _ -> 10.0
    end
    assigns = assign(assigns, :min_val, min_val)
    assigns = assign(assigns, :max_val, max_val)

    # Normalize value to 0-1 range, then map to 0-270 degrees
    normalized_val = if assigns.max_val > assigns.min_val do
      (assigns.current_val - assigns.min_val) / (assigns.max_val - assigns.min_val)
    else
      0.0
    end

    angle_degrees = normalized_val * 270
    angle_radians = angle_degrees * :math.pi() / 180

    # Calculate indicator line endpoint
    assigns = assign(assigns, :indicator_x, assigns.knob_center_x + (assigns.knob_radius - 2) * :math.cos(angle_radians - :math.pi() / 2))
    assigns = assign(assigns, :indicator_y, assigns.knob_center_y + (assigns.knob_radius - 2) * :math.sin(angle_radians - :math.pi() / 2))

    # Different colors for different node types
    knob_color = case assigns.node["name"] do
      "const" -> "#F59E0B"  # Orange for const
      "cc-in" -> "#8B5CF6"  # Purple for cc-in
      _ -> "#F59E0B"  # Default orange
    end
    assigns = assign(assigns, :knob_color, knob_color)

    ~H"""
    <!-- Control Node Knob -->
    <g class="control-knob">
      <!-- Knob Background Circle -->
      <circle
        cx={@knob_center_x}
        cy={@knob_center_y}
        r={@knob_radius}
        fill="#374151"
        stroke="#6B7280"
        stroke-width="1"
      />

      <!-- Knob Track (shows full range) -->
      <circle
        cx={@knob_center_x}
        cy={@knob_center_y}
        r={@knob_radius - 3}
        fill="none"
        stroke="#4B5563"
        stroke-width="2"
        stroke-dasharray="2,2"
        opacity="0.5"
      />

      <!-- Value Indicator Line -->
      <line
        x1={@knob_center_x}
        y1={@knob_center_y}
        x2={@indicator_x}
        y2={@indicator_y}
        stroke={@knob_color}
        stroke-width="2"
        stroke-linecap="round"
      />

      <!-- Interactive Area for Dragging -->
      <circle
        id={"control-knob-#{@node["id"]}"}
        cx={@knob_center_x}
        cy={@knob_center_y}
        r={@knob_radius + 5}
        fill="transparent"
        phx-hook="ControlKnob"
        data-node-id={@node["id"]}
        data-current-val={@current_val}
        data-min-val={@min_val}
        data-max-val={@max_val}
        style="cursor: pointer;"
      />

      <!-- Current Value Display -->
      <text
        x={@knob_center_x}
        y={@knob_center_y + @knob_radius + 15}
        text-anchor="middle"
        dominant-baseline="middle"
        class="text-xs fill-yellow-400"
      >
        <%= Float.round(@current_val, 2) %>
      </text>
      
      <!-- Node Type Label -->
      <text
        x={@knob_center_x}
        y={@knob_center_y + @knob_radius + 28}
        text-anchor="middle"
        dominant-baseline="middle"
        class="text-xs fill-gray-400"
      >
        <%= if @node["name"] == "cc-in", do: "CC", else: "CONST" %>
      </text>
    </g>
    """
  end

  # Private helper functions

  defp parse_float(str) do
    case Float.parse(str || "0") do
      {val, _} -> val
      :error -> 0.0
    end
  end

  defp create_node_immediately(socket, node_type, val, min_val, max_val, control) do
    # Find the next available node ID
    next_id = case socket.assigns.nodes do
      [] -> 1
      nodes -> (Enum.map(nodes, & &1["id"]) |> Enum.max()) + 1
    end

    # Get the SVG coordinates from the node creation menu or config modal
    {svg_x, svg_y} = if socket.assigns.node_config_modal.visible do
      {socket.assigns.node_config_modal.svg_x, socket.assigns.node_config_modal.svg_y}
    else
      {socket.assigns.node_creation_menu.svg_x, socket.assigns.node_creation_menu.svg_y}
    end

    # Create the new node with provided or default values
    base_node = %{
      "id" => next_id,
      "name" => node_type,
      "x" => svg_x - 70,  # Center the node on the click position
      "y" => svg_y - 40,
      "val" => val || cond do
        node_type == "const" -> 5.0  # Default value for const nodes
        node_type == "cc-in" -> 64.0  # Default MIDI value for cc-in nodes
        true -> nil
      end,
      "control" => control
    }

    # Add custom ranges if provided, otherwise use defaults
    new_node = if min_val && max_val do
      base_node
      |> Map.put("min_val", min_val)
      |> Map.put("max_val", max_val)
    else
      add_node_ranges(base_node)
    end

    # Add enriched node data from available types
    case ModsynthGuiPhx.SynthManager.get_available_node_types() do
      {:ok, node_types} ->
        case Map.get(node_types, node_type) do
          {params, _bus_type} ->
            enriched_node = Map.put(new_node, "parameters", params)
            updated_nodes = [enriched_node | socket.assigns.nodes]

            socket =
              socket
              |> assign(:nodes, updated_nodes)
              |> assign(:node_creation_menu, %{visible: false, x: 0, y: 0, svg_x: 0, svg_y: 0, available_types: []})
              |> assign(:node_config_modal, %{visible: false, node_type: nil, svg_x: 0, svg_y: 0})
              |> put_flash(:info, "#{String.upcase(node_type)} node created")

            {:noreply, socket}

          nil ->
            {:noreply, put_flash(socket, :error, "Unknown node type: #{node_type}")}
        end

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create node: #{reason}")}
    end
  end

  defp send_parameter_to_supercollider(socket, node_id, value) do
    # Find the input control for this node
    input_control = Enum.find(socket.assigns.input_control_list, fn ic ->
      ic.node_id == node_id
    end)
    
    if input_control do
      try do
        ScClient.set_control(input_control.sc_id, input_control.control_name, value)
        Logger.debug("Set control for node #{node_id}: #{input_control.sc_id}.#{input_control.control_name} = #{value}")
      catch
        error ->
          Logger.error("Failed to set control for node #{node_id}: #{inspect(error)}")
      end
    else
      Logger.warning("No input control found for node #{node_id}")
    end
  end

  defp create_current_synth_data(socket) do
    # Convert port-based connections back to parameter-based format
    param_connections = convert_connections_to_param_format(socket.assigns.connections, socket.assigns.nodes)
    
    # Convert enriched nodes back to original format
    original_nodes = convert_enriched_nodes_to_original_format(socket.assigns.nodes)
    
    # Create synth data structure compatible with backend
    %{
      "nodes" => original_nodes,
      "connections" => param_connections,
      "frame" => socket.assigns.canvas_size,
      "master_vol" => 0.3
    }
  end

  defp get_configured_midi_directories do
    # Get the semicolon-delimited list from configuration and split it
    midi_dirs_string = Application.get_env(:modsynth_gui_phx, :midi_directories, "../sc_em/midi;deps/midifile/test")

    midi_dirs_string
    |> String.split(";")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp get_path_suggestions(path) do
    case String.trim(path) do
      "" ->
        # Show helpful starting directories from configuration when path is empty
        configured_dirs = get_configured_midi_directories()
        |> Enum.map(fn dir ->
          %{name: dir, path: dir, is_directory: true, is_midi: false, display_name: "#{dir}/"}
        end)

        current_dir = [%{name: ".", path: ".", is_directory: true, is_midi: false, display_name: "./"}]

        current_dir ++ configured_dirs ++ list_directory_contents(".")

      path ->
        # Determine if this is a directory path or file path
        if String.ends_with?(path, "/") do
          # Directory path - show contents of this directory
          list_directory_contents(path)
        else
          # File path - show completions based on the parent directory
          case Path.split(path) do
            [filename] ->
              # Just a filename, search in current directory and configured MIDI directories
              current_dir_matches = list_directory_contents(".")
              |> Enum.filter(fn item -> String.starts_with?(item.name, filename) end)

              # Also check configured MIDI directories
              configured_midi_dirs = get_configured_midi_directories()
              midi_dir_matches = Enum.flat_map(configured_midi_dirs, fn midi_dir ->
                if File.exists?(midi_dir) do
                  list_directory_contents(midi_dir)
                  |> Enum.filter(fn item -> String.starts_with?(item.name, filename) end)
                  |> Enum.map(fn item -> %{item | path: Path.join(midi_dir, item.name)} end)
                else
                  []
                end
              end)

              current_dir_matches ++ midi_dir_matches

            path_parts ->
              # Has directory components
              parent_dir = Path.join(Enum.slice(path_parts, 0..-2//1))
              filename = List.last(path_parts)

              list_directory_contents(parent_dir)
              |> Enum.filter(fn item -> String.starts_with?(item.name, filename) end)
          end
        end
    end
  end

  defp list_directory_contents(dir_path) do
    case File.ls(dir_path) do
      {:ok, files} ->
        files
        |> Enum.map(fn file ->
          full_path = Path.join(dir_path, file)
          case File.stat(full_path) do
            {:ok, stat} ->
              is_dir = stat.type == :directory
              is_midi = String.ends_with?(String.downcase(file), [".mid", ".midi"])

              %{
                name: file,
                path: full_path,
                is_directory: is_dir,
                is_midi: is_midi,
                display_name: if(is_dir, do: "#{file}/", else: file)
              }

            {:error, _} ->
              %{
                name: file,
                path: full_path,
                is_directory: false,
                is_midi: false,
                display_name: file
              }
          end
        end)
        |> Enum.filter(fn item ->
          # Show directories and MIDI files
          item.is_directory || item.is_midi
        end)
        |> Enum.sort_by(fn item -> {!item.is_directory, item.name} end)
        |> Enum.take(50)  # Limit to 50 suggestions to show more MIDI files

      {:error, _} ->
        []
    end
  end
end
