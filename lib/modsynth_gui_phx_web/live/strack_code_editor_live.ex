defmodule ModsynthGuiPhxWeb.STrackCodeEditorLive do
  use ModsynthGuiPhxWeb, :live_view
  
  @default_code ""

  def mount(_params, _session, socket) do
    scripts_dir = Path.expand("~/.modsynth/strack_scripts")
    File.mkdir_p!(scripts_dir)
    
    socket =
      socket
      |> assign(:code, @default_code)
      |> assign(:result, nil)
      |> assign(:error, nil)
      |> assign(:scripts_dir, scripts_dir)
      |> assign(:saved_filename, nil)
      |> assign(:all_files, list_all_script_files(scripts_dir))
      |> assign(:example_files_dir, Path.expand("./example_stracks"))
      |> assign(:playing, false)
      |> assign(:midi_player_pid, nil)

    {:ok, socket}
  end

  def handle_event("editor_content_changed", %{"value" => value}, socket) do
    IO.puts("Editor content changed: #{inspect(String.length(value))} characters")
    {:noreply, assign(socket, :code, value)}
  end

  def handle_event("execute_code", params, socket) do
    IO.puts("Execute button clicked with params: #{inspect(params)}")
    IO.puts("Current code in socket: #{inspect(socket.assigns.code)}")
    case execute_strack_code(socket.assigns.code) do
      {:ok, result} ->
        IO.puts("Code executed successfully: #{inspect(result)}")
        {:noreply, assign(socket, result: result, error: nil)}
      {:error, error} ->
        IO.puts("Code execution failed: #{inspect(error)}")
        {:noreply, assign(socket, result: nil, error: error)}
    end
  end

  def handle_event("play_code", _params, socket) do
    case socket.assigns.result do
      nil ->
        {:noreply, put_flash(socket, :error, "No STrack map to play. Execute code first.")}
      result ->
        case play_strack_map_with_current_synth(result) do
          {:ok, _} ->
            socket =
              socket
              |> assign(:playing, true)
              |> assign(:midi_player_pid, :managed_by_synth_manager)
              |> put_flash(:info, "Playing STrack map...")
            {:noreply, socket}
          {:error, error} ->
            {:noreply, put_flash(socket, :error, "Failed to play: #{error}")}
        end
    end
  end

  def handle_event("stop_playback", _params, socket) do
    case stop_strack_playback(socket.assigns.midi_player_pid) do
      :ok ->
        socket =
          socket
          |> assign(:playing, false)
          |> assign(:midi_player_pid, nil)
          |> put_flash(:info, "Playback stopped")
        {:noreply, socket}
      {:error, error} ->
        {:noreply, put_flash(socket, :error, "Failed to stop playback: #{error}")}
    end
  end

  def handle_event("save_code", %{"filename" => filename}, socket) do
    if String.trim(filename) == "" do
      {:noreply, put_flash(socket, :error, "Please enter a filename")}
    else
      filename = ensure_exs_extension(filename)
      filepath = Path.join(socket.assigns.scripts_dir, filename)
      
      case File.write(filepath, socket.assigns.code) do
        :ok ->
          socket =
            socket
            |> assign(:saved_filename, filename)
            |> assign(:all_files, list_all_script_files(socket.assigns.scripts_dir))
            |> put_flash(:info, "Saved as #{filename}")
          {:noreply, socket}
        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to save: #{reason}")}
      end
    end
  end

  def handle_event("load_file", %{"path" => filepath}, socket) do
    case File.read(filepath) do
      {:ok, content} ->
        filename = Path.basename(filepath, ".exs")
        socket =
          socket
          |> assign(:code, content)
          |> assign(:saved_filename, filename)
          |> assign(:result, nil)
          |> assign(:error, nil)
          |> put_flash(:info, "Loaded #{filename}")
        
        # Explicitly push the loaded content to Monaco Editor
        socket = LiveMonacoEditor.set_value(socket, content)
        {:noreply, socket}
      {:error, reason} ->
        {:noreply, put_flash(socket, :error, "Failed to load: #{reason}")}
    end
  end

  def handle_event("new_file", _params, socket) do
    socket =
      socket
      |> assign(:code, @default_code)
      |> assign(:saved_filename, nil)
      |> assign(:result, nil)
      |> assign(:error, nil)
      |> put_flash(:info, "New file created")
    
    # Explicitly clear the Monaco Editor
    socket = LiveMonacoEditor.set_value(socket, @default_code)
    {:noreply, socket}
  end

  def handle_event("viewport_resize", _params, socket) do
    # Handle viewport resize event from phx-hook
    {:noreply, socket}
  end

  defp execute_strack_code(code) do
    try do
      # Execute the code and capture the result
      {result, _bindings} = Code.eval_string(code, [])
      
      # Validate that the result is a map of STrack structs
      case validate_strack_map(result) do
        :ok ->
          {:ok, result}
        {:error, reason} ->
          {:error, "Invalid result: #{reason}"}
      end
    rescue
      e ->
        {:error, "Execution error: #{Exception.message(e)}"}
    catch
      kind, reason ->
        {:error, "#{kind}: #{inspect(reason)}"}
    end
  end

  defp validate_strack_map(result) when is_map(result) do
    case Enum.all?(result, fn {_key, value} -> is_strack?(value) end) do
      true -> :ok
      false -> {:error, "All values must be STrack structs"}
    end
  end

  defp validate_strack_map(_), do: {:error, "Result must be a map"}

  defp is_strack?(%STrack{}), do: true
  defp is_strack?(_), do: false

  defp play_strack_map_with_current_synth(strack_map) do
    try do
      # Get the current synth data from the main editor
      case ModsynthGuiPhx.SynthManager.get_current_synth_data() do
        {:ok, current_synth} ->
          IO.puts("Got current synth data from main editor")
          
          # Use SynthManager's play_midi_file_with_current_data function
          # This ensures proper synth lifecycle management and state consistency
          case ModsynthGuiPhx.SynthManager.play_midi_file_with_current_data(strack_map, current_synth.data) do
            {:ok, {message, _input_control_list, _connection_list}} ->
              IO.puts("STrack playback started successfully: #{message}")
              # Return success - SynthManager handles the MIDI player PID internally
              {:ok, :managed_by_synth_manager}
            {:error, error} ->
              IO.puts("Error starting STrack playback: #{error}")
              {:error, error}
          end
          
        {:error, error} ->
          IO.puts("No synth loaded in main editor: #{error}")
          {:error, "No synth loaded in main editor. Please load a synth file first."}
      end
    rescue
      e ->
        IO.puts("Error in play_strack_map_with_current_synth: #{Exception.message(e)}")
        IO.puts("Error stacktrace: #{Exception.format_stacktrace(__STACKTRACE__)}")
        {:error, Exception.message(e)}
    end
  end

  def handle_info(:midi_play_done, socket) do
    # Handle when playback naturally finishes
    # SynthManager handles all synth lifecycle management
    
    socket =
      socket
      |> assign(:playing, false)
      |> assign(:midi_player_pid, nil)
      |> put_flash(:info, "Playback finished")
    
    {:noreply, socket}
  end

  defp stop_strack_playback(_pid) do
    # Use the exact same pattern as SynthManager which works without timeout
    case ModsynthGuiPhx.SynthManager.stop_synth() do
      {:ok, message} ->
        IO.puts("Playback stopped successfully: #{message}")
        :ok
      {:error, reason} ->
        IO.puts("Error stopping playback: #{reason}")
        {:error, reason}
    end
  end

  defp list_all_script_files(scripts_dir) do
    # Get user files
    user_files = list_script_files_in_dir(scripts_dir, "User")
    
    # Get example files  
    example_files_dir = Path.expand("./example_stracks")
    example_files = list_script_files_in_dir(example_files_dir, "Examples")
    
    # Combine and sort all files by name
    (user_files ++ example_files)
    |> Enum.sort_by(fn file -> file.name end)
  end

  defp list_script_files_in_dir(dir, category) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".exs"))
        |> Enum.map(fn file ->
          %{
            name: Path.basename(file, ".exs"),
            path: Path.join(dir, file),
            category: category
          }
        end)
      {:error, _} ->
        []
    end
  end

  defp ensure_exs_extension(filename) do
    if String.ends_with?(filename, ".exs") do
      filename
    else
      filename <> ".exs"
    end
  end

  def render(assigns) do
    ~H"""
    <div id="strack-code-editor-main" class="h-screen bg-gray-900 text-white overflow-hidden" phx-hook="ViewportResize">
      <!-- Header -->
      <div class="bg-gray-800 p-2 flex items-center justify-between border-b border-gray-700">
        <div class="flex items-center space-x-4">
          <h1 class="text-xl font-bold">STrack Code Editor</h1>
          <.link
            navigate="/synth_editor"
            class="text-blue-400 hover:text-blue-300 text-sm font-medium"
          >
            Synth Editor
          </.link>
          <%= if @saved_filename do %>
            <div class="flex items-center space-x-2 px-3 py-1 bg-blue-600 rounded-full">
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12h6m-6 4h6m2 5H7a2 2 0 01-2-2V5a2 2 0 012-2h5.586a1 1 0 01.707.293l5.414 5.414a1 1 0 01.293.707V19a2 2 0 01-2 2z"></path>
              </svg>
              <span class="text-sm font-medium"><%= @saved_filename %></span>
            </div>
          <% end %>
          <%= if @playing do %>
            <div class="flex items-center space-x-2 px-3 py-1 bg-green-600 rounded-full">
              <div class="w-2 h-2 bg-white rounded-full animate-pulse"></div>
              <span class="text-sm font-medium">Playing STrack</span>
            </div>
          <% end %>
        </div>

        <div class="flex items-center space-x-4">
          <button
            phx-click="new_file"
            class="px-4 py-2 bg-gray-600 hover:bg-gray-700 rounded text-sm"
          >
            New File
          </button>
          <div class="flex items-center space-x-2">
            <button
              phx-click="execute_code"
              class="px-4 py-2 bg-blue-600 hover:bg-blue-700 rounded text-sm"
            >
              Execute
            </button>
            <button
              phx-click="play_code"
              class="px-4 py-2 bg-green-600 hover:bg-green-700 rounded text-sm disabled:opacity-50 disabled:cursor-not-allowed"
              disabled={is_nil(@result) or @playing}
            >
              Play
            </button>
            <button
              phx-click="stop_playback"
              class="px-4 py-2 bg-red-600 hover:bg-red-700 rounded text-sm disabled:opacity-50 disabled:cursor-not-allowed"
              disabled={not @playing}
            >
              Stop
            </button>
          </div>
        </div>
      </div>

      <!-- Main Content -->
      <div class="flex" style={"height: calc(100vh - 60px)"}>
        <!-- File Browser Sidebar -->
        <div class="w-64 bg-gray-800 overflow-hidden">
          <div class="p-4 h-full overflow-y-auto">
            <h3 class="text-lg font-semibold mb-4">Files</h3>
            
            <!-- Save Section -->
            <div class="mb-6">
              <label class="block text-sm font-medium text-gray-300 mb-2">Save As:</label>
              <form phx-submit="save_code">
                <input
                  type="text"
                  name="filename"
                  placeholder="script_name.exs"
                  value={@saved_filename}
                  class="w-full px-3 py-2 bg-gray-700 border border-gray-600 rounded text-sm mb-2 text-white placeholder-gray-400"
                />
                <button
                  type="submit"
                  class="w-full px-4 py-2 bg-green-600 hover:bg-green-700 rounded text-sm"
                >
                  Save
                </button>
              </form>
            </div>

            <!-- Load Section -->
            <div>
              <label class="block text-sm font-medium text-gray-300 mb-2">Load File:</label>
              <div class="space-y-1 overflow-y-auto" style="max-height: calc(100vh - 400px);">
                <%= for file <- @all_files do %>
                  <button
                    phx-click="load_file"
                    phx-value-path={file.path}
                    class="w-full text-left px-2 py-1 text-sm hover:bg-gray-700 rounded flex items-center justify-between"
                  >
                    <span class="flex-1 truncate text-white"><%= file.name %></span>
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
        </div>

        <!-- Editor Area -->
        <div class="flex-1 flex flex-col overflow-hidden">
          <!-- Code Editor -->
          <div class="flex-1 bg-gray-900">
            <LiveMonacoEditor.code_editor
              id="strack-code-editor"
              value={@code}
              change="editor_content_changed"
              opts={
                Map.merge(
                  LiveMonacoEditor.default_opts(),
                  %{
                    "language" => "elixir",
                    "theme" => "vs-dark",
                    "minimap" => %{"enabled" => false},
                    "lineNumbers" => "on",
                    "automaticLayout" => true
                  }
                )
              }
              style="height: calc(100vh - 384px); width: 100%;"
            />
          </div>

          <!-- Results/Error Display -->
          <div class="bg-gray-800 border-t border-gray-700 overflow-y-auto" style="height: 320px;">
            <div class="p-4">
              <h3 class="text-lg font-medium text-white mb-3">Results</h3>
              
              <%= if @error do %>
                <div class="bg-red-900/50 border border-red-700 rounded-md p-3">
                  <h4 class="text-sm font-medium text-red-300 mb-2">Error:</h4>
                  <pre class="text-sm text-red-200 whitespace-pre-wrap"><%= @error %></pre>
                </div>
              <% end %>

              <%= if @result do %>
                <div class="bg-green-900/50 border border-green-700 rounded-md p-3">
                  <h4 class="text-sm font-medium text-green-300 mb-2">STrack Map:</h4>
                  <pre class="text-sm text-green-200 whitespace-pre-wrap"><%= inspect(@result, pretty: true) %></pre>
                </div>
              <% end %>

              <%= if is_nil(@result) and is_nil(@error) do %>
                <div class="text-gray-400 text-sm">
                  Execute code to see results here.
                </div>
              <% end %>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end