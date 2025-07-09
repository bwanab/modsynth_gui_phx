defmodule ModsynthGuiPhx.FileManager do
  @moduledoc """
  Manages file operations for synth networks including reading/writing 
  JSON files and handling directory structure.
  """

  @default_user_dir "~/.modsynth"
  @synth_networks_dir "synth_networks"

  def user_dir do
    System.get_env("MODSYNTH_DIR") || @default_user_dir
  end

  def synth_networks_dir do
    Path.join(user_dir(), @synth_networks_dir)
    |> Path.expand()
  end

  def ensure_directories do
    networks_dir = synth_networks_dir()
    File.mkdir_p!(networks_dir)
    {:ok, networks_dir}
  end

  def list_synth_files do
    networks_dir = synth_networks_dir()
    example_dir = Path.join([Application.app_dir(:sc_em), "..", "examples"])
    
    user_files = list_json_files(networks_dir, "User")
    example_files = list_json_files(example_dir, "Examples")
    
    {user_files, example_files}
  end

  defp list_json_files(directory, category) do
    case File.ls(directory) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".json"))
        |> Enum.map(fn file ->
          %{
            name: Path.basename(file, ".json"),
            path: Path.join(directory, file),
            category: category
          }
        end)
      
      {:error, _} -> []
    end
  end

  def load_synth_file(file_path) do
    case File.read(file_path) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, data} -> {:ok, data}
          {:error, reason} -> {:error, "JSON decode error: #{inspect(reason)}"}
        end
      
      {:error, reason} -> {:error, "File read error: #{inspect(reason)}"}
    end
  end

  def save_synth_file(filename, data) do
    ensure_directories()
    file_path = Path.join(synth_networks_dir(), "#{filename}.json")
    
    case Jason.encode(data, pretty: true) do
      {:ok, json} ->
        case File.write(file_path, json) do
          :ok -> {:ok, file_path}
          {:error, reason} -> {:error, "Write error: #{inspect(reason)}"}
        end
      
      {:error, reason} -> {:error, "JSON encode error: #{inspect(reason)}"}
    end
  end
end