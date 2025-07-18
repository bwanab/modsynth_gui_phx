defmodule ModsynthGuiPhxWeb.STrackCodeEditorLive do
  use ModsynthGuiPhxWeb, :live_view
  
  @default_code """
  # Create a simple note and STrack
  note = Note.new(:C, octave: 3, duration: 100)
  %{0 => STrack.new([note], name: "example", tpqn: 960, type: :instrument, program_number: 73, bpm: 100)}
  """

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
      |> assign(:available_files, list_script_files(scripts_dir))
      |> assign(:playing, false)
      |> assign(:midi_player_pid, nil)

    {:ok, socket}
  end

  def handle_event("code-editor-lost-focus", %{"value" => value}, socket) do
    IO.puts("Code editor lost focus with value: #{inspect(value)}")
    {:noreply, assign(socket, :code, value)}
  end
  
  def handle_event("code-editor-change", %{"value" => value}, socket) do
    IO.puts("Code editor changed with value: #{inspect(value)}")
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
          {:ok, pid} ->
            socket =
              socket
              |> assign(:playing, true)
              |> assign(:midi_player_pid, pid)
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
            |> assign(:available_files, list_script_files(socket.assigns.scripts_dir))
            |> put_flash(:info, "Saved as #{filename}")
          {:noreply, socket}
        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to save: #{reason}")}
      end
    end
  end

  def handle_event("load_file", %{"filename" => filename}, socket) do
    filepath = Path.join(socket.assigns.scripts_dir, filename)
    
    case File.read(filepath) do
      {:ok, content} ->
        socket =
          socket
          |> assign(:code, content)
          |> assign(:saved_filename, filename)
          |> assign(:result, nil)
          |> assign(:error, nil)
          |> put_flash(:info, "Loaded #{filename}")
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
      # Get the current synth data from the main editor (like MIDI file playback does)
      case ModsynthGuiPhx.SynthManager.get_current_synth_data() do
        {:ok, current_synth} ->
          IO.puts("Got current synth data from main editor")
          
          # Create virtual output port
          port_name = "modsynth"
          IO.puts("Creating virtual output port: #{port_name}")
          port = Midiex.create_virtual_output(port_name)
          
          # Get available node types (like in SynthManager)
          available_node_types = Modsynth.init()
          
          # Use the exact same pattern as SynthManager play_midi_file_with_current_data
          IO.puts("Calling Modsynth.specs_to_data and Modsynth.play with current synth data")
          {_input_control_list, _node_map, _connection_list} = Modsynth.specs_to_data(available_node_types, current_synth.data)
          |> Modsynth.play(port_name)
          
          # Play the STrack map through the loaded synth network
          IO.puts("Calling MidiPlayer.play with strack_map: #{inspect(strack_map)}")
          pid = MidiPlayer.play(strack_map, synth: port)
          
          # Set up notification for when playback is done (like in SynthManager)
          MidiPlayer.notify_when_play_done(pid)
          
          # Don't wait for completion in the LiveView process
          # The audio will play in the background
          IO.puts("Play completed successfully")
          {:ok, pid}
          
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
    # Handle when playback naturally finishes (like in SynthManager)
    ScClient.group_free(1)
    MidiInClient.stop_midi()
    
    socket =
      socket
      |> assign(:playing, false)
      |> assign(:midi_player_pid, nil)
      |> put_flash(:info, "Playback finished")
    
    {:noreply, socket}
  end

  defp stop_strack_playback(pid) do
    try do
      # Follow the same pattern as SynthManager :stop_synth
      # Stop the synth using group_free (as seen in the SynthManager)
      ScClient.group_free(1)
      if !is_nil(pid) do
        MidiPlayer.stop(pid)
      end
      MidiInClient.stop_midi()
      IO.puts("Playback stopped successfully")
      :ok
    rescue
      e ->
        IO.puts("Error stopping playback: #{Exception.message(e)}")
        {:error, Exception.message(e)}
    end
  end

  defp list_script_files(scripts_dir) do
    case File.ls(scripts_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".exs"))
        |> Enum.sort()
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
    <div class="min-h-screen bg-gray-100">
      <div class="bg-white shadow-sm border-b">
        <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div class="flex justify-between items-center py-4">
            <h1 class="text-2xl font-bold text-gray-900">STrack Code Editor</h1>
            <div class="flex space-x-2">
              <button
                phx-click="new_file"
                class="bg-gray-500 hover:bg-gray-600 text-white px-4 py-2 rounded-md text-sm font-medium"
              >
                New
              </button>
              <.link
                navigate="/synth_editor"
                class="bg-blue-500 hover:bg-blue-600 text-white px-4 py-2 rounded-md text-sm font-medium"
              >
                Synth Editor
              </.link>
            </div>
          </div>
        </div>
      </div>

      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
        <div class="grid grid-cols-1 lg:grid-cols-4 gap-6">
          <!-- File Management Panel -->
          <div class="bg-white rounded-lg shadow p-4">
            <h3 class="text-lg font-medium text-gray-900 mb-4">Files</h3>
            
            <!-- Save Section -->
            <div class="mb-4">
              <label class="block text-sm font-medium text-gray-700 mb-2">Save As:</label>
              <form phx-submit="save_code">
                <input
                  type="text"
                  name="filename"
                  placeholder="script_name.exs"
                  value={@saved_filename}
                  class="w-full px-3 py-2 border border-gray-300 rounded-md text-sm mb-2"
                />
                <button
                  type="submit"
                  class="w-full bg-green-500 hover:bg-green-600 text-white px-4 py-2 rounded-md text-sm font-medium"
                >
                  Save
                </button>
              </form>
            </div>

            <!-- Load Section -->
            <div>
              <label class="block text-sm font-medium text-gray-700 mb-2">Load File:</label>
              <div class="space-y-1 max-h-40 overflow-y-auto">
                <%= for file <- @available_files do %>
                  <button
                    phx-click="load_file"
                    phx-value-filename={file}
                    class="w-full text-left px-3 py-2 text-sm text-gray-700 hover:bg-gray-100 rounded-md"
                  >
                    <%= file %>
                  </button>
                <% end %>
              </div>
            </div>
          </div>

          <!-- Code Editor -->
          <div class="lg:col-span-3">
            <div class="bg-white rounded-lg shadow">
              <div class="p-4 border-b">
                <div class="flex justify-between items-center">
                  <h3 class="text-lg font-medium text-gray-900">Code Editor</h3>
                  <div class="flex space-x-2">
                    <button
                      phx-click="execute_code"
                      class="bg-blue-500 hover:bg-blue-600 text-white px-4 py-2 rounded-md text-sm font-medium"
                    >
                      Execute
                    </button>
                    <button
                      phx-click="play_code"
                      class="bg-green-500 hover:bg-green-600 text-white px-4 py-2 rounded-md text-sm font-medium disabled:opacity-50 disabled:cursor-not-allowed"
                      disabled={is_nil(@result) or @playing}
                    >
                      Play
                    </button>
                    <button
                      phx-click="stop_playback"
                      class="bg-red-500 hover:bg-red-600 text-white px-4 py-2 rounded-md text-sm font-medium disabled:opacity-50 disabled:cursor-not-allowed"
                      disabled={not @playing}
                    >
                      Stop
                    </button>
                  </div>
                </div>
              </div>

              <div class="p-4">
                <LiveMonacoEditor.code_editor
                  id="strack-code-editor"
                  value={@code}
                  opts={
                    Map.merge(
                      LiveMonacoEditor.default_opts(),
                      %{
                        "language" => "elixir",
                        "theme" => "vs-light",
                        "minimap" => %{"enabled" => false},
                        "lineNumbers" => "on",
                        "automaticLayout" => true
                      }
                    )
                  }
                  style="min-height: 400px; width: 100%;"
                />
              </div>
            </div>

            <!-- Results/Error Display -->
            <div class="mt-6 bg-white rounded-lg shadow">
              <div class="p-4 border-b">
                <h3 class="text-lg font-medium text-gray-900">Results</h3>
              </div>
              <div class="p-4">
                <%= if @error do %>
                  <div class="bg-red-50 border border-red-200 rounded-md p-3">
                    <h4 class="text-sm font-medium text-red-800 mb-2">Error:</h4>
                    <pre class="text-sm text-red-700 whitespace-pre-wrap"><%= @error %></pre>
                  </div>
                <% end %>

                <%= if @result do %>
                  <div class="bg-green-50 border border-green-200 rounded-md p-3">
                    <h4 class="text-sm font-medium text-green-800 mb-2">STrack Map:</h4>
                    <pre class="text-sm text-green-700 whitespace-pre-wrap"><%= inspect(@result, pretty: true) %></pre>
                  </div>
                <% end %>

                <%= if is_nil(@result) and is_nil(@error) do %>
                  <div class="text-gray-500 text-sm">
                    Execute code to see results here.
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end