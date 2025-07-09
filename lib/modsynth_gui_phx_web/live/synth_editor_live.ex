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

    {:ok, socket}
  end

  def handle_event("toggle_file_browser", _, socket) do
    {:noreply, assign(socket, :show_file_browser, !socket.assigns.show_file_browser)}
  end

  def handle_event("load_file", %{"path" => path}, socket) do
    case FileManager.load_synth_file(path) do
      {:ok, data} ->
        nodes = data["nodes"] || []
        connections = data["connections"] || []
        
        # Load the synth into the SynthManager
        case ModsynthGuiPhx.SynthManager.load_synth(data) do
          {:ok, message} ->
            socket =
              socket
              |> assign(:current_synth, data)
              |> assign(:nodes, nodes)
              |> assign(:connections, connections)
              |> assign(:show_file_browser, false)
              |> assign(:warnings, [])
              |> put_flash(:info, message)
            
            {:noreply, socket}
          
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
      |> put_flash(:info, "Node deleted successfully")
    
    {:noreply, socket}
  end

  def render(assigns) do
    ~H"""
    <div class="h-screen bg-gray-900 text-white overflow-hidden">
      <!-- Header -->
      <div class="bg-gray-800 p-4 flex items-center justify-between border-b border-gray-700">
        <h1 class="text-xl font-bold">Modular Synthesizer Editor</h1>
        
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
            <%= for connection <- @connections do %>
              <.connection_cable 
                connection={connection} 
                nodes={@nodes} 
              />
            <% end %>
            
            <!-- Nodes -->
            <%= for node <- @nodes do %>
              <.synth_node 
                node={node} 
                selected={@selected_node == node["id"]}
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
    
    assigns = assign(assigns, :node_color, node_color)
    
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
        height="80"
        rx="8"
        fill="rgba(0,0,0,0.3)"
      />
      
      <!-- Node Body -->
      <rect 
        width="140" 
        height="80"
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
        y="35" 
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
          y="50" 
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
          y="65" 
          text-anchor="middle" 
          dominant-baseline="middle"
          class="text-xs fill-yellow-400"
        >
          <%= @node["val"] %>
        </text>
      <% end %>
      
      <!-- Input Jacks (Left Side) -->
      <circle cx="8" cy="30" r="6" fill="#2D3748" stroke="#4A5568" stroke-width="2" class="input-jack" />
      <circle cx="8" cy="30" r="3" fill="#10B981" class="input-port" />
      
      <circle cx="8" cy="50" r="6" fill="#2D3748" stroke="#4A5568" stroke-width="2" class="input-jack" />
      <circle cx="8" cy="50" r="3" fill="#10B981" class="input-port" />
      
      <!-- Output Jacks (Right Side) -->
      <circle cx="132" cy="30" r="6" fill="#2D3748" stroke="#4A5568" stroke-width="2" class="output-jack" />
      <circle cx="132" cy="30" r="3" fill="#F59E0B" class="output-port" />
      
      <circle cx="132" cy="50" r="6" fill="#2D3748" stroke="#4A5568" stroke-width="2" class="output-jack" />
      <circle cx="132" cy="50" r="3" fill="#F59E0B" class="output-port" />
      
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
      from_x = (from_node["x"] || 0) + 132
      from_y = (from_node["y"] || 0) + 30
      to_x = (to_node["x"] || 0) + 8
      to_y = (to_node["y"] || 0) + 30
      
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
      <g>
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
      </g>
      """
    else
      ~H""
    end
  end
end