defmodule ModsynthGuiPhxWeb.SynthEditorLive do
  use ModsynthGuiPhxWeb, :live_view
  alias ModsynthGuiPhx.FileManager

  def mount(_params, _session, socket) do
    {user_files, example_files} = FileManager.list_synth_files()
    
    IO.puts("DEBUG: LiveView mount - User files: #{inspect(user_files)}")
    IO.puts("DEBUG: LiveView mount - Example files: #{inspect(example_files)}")
    
    socket =
      socket
      |> assign(:user_files, user_files)
      |> assign(:example_files, example_files)
      |> assign(:current_synth, nil)
      |> assign(:nodes, [])
      |> assign(:connections, [])
      |> assign(:selected_node, nil)
      |> assign(:canvas_size, %{width: 1200, height: 800})
      |> assign(:show_file_browser, false)
      |> assign(:new_filename, "")
      |> assign(:warnings, [])
      |> assign(:connection_mode, %{active: false, from_node: nil, from_port: nil})

    {:ok, socket}
  end

  def handle_event("toggle_file_browser", _, socket) do
    {:noreply, assign(socket, :show_file_browser, !socket.assigns.show_file_browser)}
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
                
                socket =
                  socket
                  |> assign(:current_synth, data)
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
      synth_data = %{
        "nodes" => socket.assigns.nodes,
        "connections" => socket.assigns.connections,
        "frame" => socket.assigns.canvas_size,
        "master_vol" => 0.3
      }
      
      case FileManager.save_synth_file(filename, synth_data) do
        {:ok, _path} ->
          {user_files, _example_files} = FileManager.list_synth_files()
          
          socket =
            socket
            |> assign(:user_files, user_files)
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
    {:noreply, assign(socket, :selected_node, nil)}
  end

  def handle_event("play_synth", _, socket) do
    case ModsynthGuiPhx.SynthManager.play_synth() do
      {:ok, message} ->
        {:noreply, put_flash(socket, :info, message)}
      
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}
    end
  end

  def handle_event("stop_synth", _, socket) do
    case ModsynthGuiPhx.SynthManager.stop_synth() do
      {:ok, message} ->
        {:noreply, put_flash(socket, :info, message)}
      
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, reason)}
    end
  end

  def handle_event("delete_node", %{"id" => id}, socket) do
    node_id = String.to_integer(id)
    
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
      |> put_flash(:info, "Node deleted successfully")
    
    {:noreply, socket}
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
      case Map.get(modsynth_nodes, ui_node["id"]) do
        nil -> 
          # Fallback to original node if not found in modsynth data
          ui_node
        
        modsynth_node ->
          # Enrich UI node with parameter information from Modsynth.Node
          Map.put(ui_node, "parameters", modsynth_node.parameters)
      end
    end)
  end

  defp convert_connections_to_port_format(connections, nodes) do
    require Logger
    Logger.info("Converting #{length(connections)} connections to port format")
    
    Enum.map(connections, fn conn ->
      Logger.info("Original connection: #{inspect(conn)}")
      
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
        
        Logger.info("Param mapping: #{from_param} -> port #{from_port_index}, #{to_param} -> port #{to_port_index}")
        
        # Convert to port-based format
        converted = %{
          "from_node" => %{"id" => conn["from_node"]["id"], "port" => from_port_index},
          "to_node" => %{"id" => conn["to_node"]["id"], "port" => to_port_index}
        }
        
        Logger.info("Converted connection: #{inspect(converted)}")
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
        Logger.info("Parameters structure for node #{node["name"]}: #{inspect(parameters)}")
        
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
        
        # Separate inputs and outputs based on common naming patterns
        # Outputs are typically: out, sig, val, ob1, ob2, freq (when it's from midi/piano inputs)
        # Inputs are typically: in, freq (when it's to oscillators), gain, cutoff, etc.
        output_params = Enum.filter(all_param_names, fn name ->
          name in ["out", "sig", "val", "ob1", "ob2"] or 
          (name == "freq" and node["name"] in ["midi-in", "piano-in", "midi-in2"])
        end)
        
        input_params = Enum.reject(all_param_names, fn name ->
          name in ["out", "sig", "val", "ob1", "ob2"] or 
          (name == "freq" and node["name"] in ["midi-in", "piano-in", "midi-in2"])
        end)
        
        # Ensure we have at least one output
        final_outputs = if Enum.empty?(output_params) do
          ["out"]
        else
          output_params
        end
        
        Logger.info("Extracted ports - inputs: #{inspect(input_params)}, outputs: #{inspect(final_outputs)}")
        
        %{inputs: input_params, outputs: final_outputs}
    end
  end

  defp get_node_ports_fallback(node_name) do
    case node_name do
      # Oscillators
      "saw-osc" -> %{inputs: ["freq"], outputs: ["sig"]}
      "square-osc" -> %{inputs: ["freq", "width"], outputs: ["sig"]}
      "sine-osc" -> %{inputs: ["freq"], outputs: ["sig"]}
      "sin-vco" -> %{inputs: ["freq"], outputs: ["out"]}
      
      # Filters
      "moog-filt" -> %{inputs: ["in", "cutoff", "lpf_res"], outputs: ["out"]}
      "bp-filt" -> %{inputs: ["in", "freq", "q"], outputs: ["out"]}
      "lp-filt" -> %{inputs: ["in", "freq"], outputs: ["out"]}
      "hp-filt" -> %{inputs: ["in", "freq"], outputs: ["out"]}
      
      # Amplifiers
      "amp" -> %{inputs: ["in", "gain"], outputs: ["out"]}
      
      # Envelopes
      "adsr-env" -> %{inputs: ["in", "attack", "decay", "sustain", "release"], outputs: ["out"]}
      "perc-env" -> %{inputs: ["in", "attack", "decay"], outputs: ["out"]}
      "release" -> %{inputs: ["in", "release"], outputs: ["out"]}
      
      # Effects
      "freeverb" -> %{inputs: ["in", "room_size", "dampening", "wet_dry"], outputs: ["out"]}
      "reverb" -> %{inputs: ["in", "room_size", "dampening"], outputs: ["out"]}
      "echo" -> %{inputs: ["in", "delay", "feedback"], outputs: ["out"]}
      "delay" -> %{inputs: ["in", "delay", "feedback"], outputs: ["out"]}
      
      # Utilities
      "const" -> %{inputs: [], outputs: ["val"]}
      "c-splitter" -> %{inputs: ["in"], outputs: ["ob1", "ob2"]}
      "a-splitter" -> %{inputs: ["in", "lev", "pos"], outputs: ["ob1", "ob2"]}
      "pct-add" -> %{inputs: ["in", "gain"], outputs: ["out"]}
      "c-scale" -> %{inputs: ["in", "out_lo", "out_hi"], outputs: ["out"]}
      
      # Input/Output
      "midi-in" -> %{inputs: [], outputs: ["freq"]}
      "midi-in2" -> %{inputs: [], outputs: ["freq"]}
      "piano-in" -> %{inputs: [], outputs: ["freq"]}
      "audio-out" -> %{inputs: ["b1", "b2"], outputs: []}
      "audio-in" -> %{inputs: [], outputs: ["out"]}
      "cc-in" -> %{inputs: [], outputs: ["val"]}
      "cc-cont-in" -> %{inputs: [], outputs: ["val"]}
      
      # Control
      "slider-ctl" -> %{inputs: [], outputs: ["val"]}
      "note-freq" -> %{inputs: ["note"], outputs: ["freq"]}
      
      # Default fallback
      _ -> %{inputs: ["in1", "in2"], outputs: ["out1", "out2"]}
    end
  end

  def render(assigns) do
    ~H"""
    <div class="h-screen bg-gray-900 text-white overflow-hidden">
      <!-- Header -->
      <div class="bg-gray-800 p-4 flex items-center justify-between border-b border-gray-700">
        <div class="flex items-center space-x-4">
          <h1 class="text-xl font-bold">Modular Synthesizer Editor</h1>
          <%= if @connection_mode.active do %>
            <div class="flex items-center space-x-2 px-3 py-1 bg-orange-600 rounded-full">
              <div class="w-2 h-2 bg-white rounded-full animate-pulse"></div>
              <span class="text-sm font-medium">Connection Mode - Click input port to connect</span>
            </div>
          <% end %>
        </div>
        
        <div class="flex items-center space-x-4">
          <button 
            phx-click="toggle_file_browser"
            class="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded text-sm"
          >
            <%= if @show_file_browser, do: "Hide Files", else: "Load File" %>
          </button>
          
          <div class="flex items-center space-x-2">
            <button 
              phx-click="play_synth"
              class="px-4 py-2 bg-green-600 hover:bg-green-700 rounded text-sm"
              disabled={@current_synth == nil}
            >
              Play
            </button>
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
              
              <%= if @selected_node do %>
                <button 
                  phx-click="delete_node"
                  phx-value-id={@selected_node}
                  class="px-4 py-2 bg-red-600 hover:bg-red-700 rounded text-sm"
                  onclick="return confirm('Are you sure you want to delete this node and all its connections?')"
                >
                  Delete Node
                </button>
              <% end %>
          </div>
        </div>
      </div>

      <!-- Main Content -->
      <div class="flex h-full">
        <!-- File Browser Sidebar -->
        <div class={["transition-all duration-300 bg-gray-800 overflow-hidden", if(@show_file_browser, do: "w-64", else: "w-0")]}>
          <div class="p-4 h-full overflow-y-auto">
            <h3 class="text-lg font-semibold mb-4">Files</h3>
            
            <!-- User Files -->
            <div class="mb-6">
              <h4 class="text-sm font-medium text-gray-400 mb-2">User Files</h4>
              <div class="space-y-1 max-h-48 overflow-y-auto">
                <%= for file <- @user_files do %>
                  <button 
                    phx-click="load_file"
                    phx-value-path={file.path}
                    class="w-full text-left px-2 py-1 text-sm hover:bg-gray-700 rounded"
                  >
                    <%= file.name %>
                  </button>
                <% end %>
              </div>
            </div>
            
            <!-- Example Files -->
            <div>
              <h4 class="text-sm font-medium text-gray-400 mb-2">Examples</h4>
              <div class="space-y-1 max-h-96 overflow-y-auto">
                <%= for file <- @example_files do %>
                  <button 
                    phx-click="load_file"
                    phx-value-path={file.path}
                    class="w-full text-left px-2 py-1 text-sm hover:bg-gray-700 rounded"
                  >
                    <%= file.name %>
                  </button>
                <% end %>
              </div>
            </div>
          </div>
        </div>

        <!-- Canvas Area -->
        <div class="flex-1 relative">
          <svg 
            id="synth-canvas"
            class="w-full h-full bg-gray-900"
            viewBox={"0 0 #{@canvas_size.width} #{@canvas_size.height}"}
            phx-hook="SynthCanvas"
            phx-click="clear_selection"
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
      
      <!-- Parameter/Control Display -->
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
end