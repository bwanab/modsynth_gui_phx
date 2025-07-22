defmodule ModsynthGuiPhx.FileManager do
  @moduledoc """
  Manages file operations for synth networks including reading/writing
  JSON files and handling directory structure.
  """

  require Logger

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
    # Use the actual source directory instead of the compiled app directory
    example_dir = Path.join([__DIR__, "..", "..", "..", "sc_em", "examples"])
                  |> Path.expand()

    Logger.debug("Looking for user files in: #{networks_dir}")
    Logger.debug("Looking for example files in: #{example_dir}")
    Logger.debug("Example dir exists? #{File.exists?(example_dir)}")

    user_files = list_json_files(networks_dir, "User")
    example_files = list_json_files(example_dir, "Examples")

    Logger.debug("Found #{length(user_files)} user files")
    Logger.debug("Found #{length(example_files)} example files")

    {user_files, example_files}
  end

  defp list_json_files(directory, category) do
    Logger.debug("Listing files in directory: #{directory}")
    case File.ls(directory) do
      {:ok, files} ->
        Logger.debug("Found #{length(files)} total files: #{inspect(files)}")
        json_files = files |> Enum.filter(&String.ends_with?(&1, ".json"))
        Logger.debug("Found #{length(json_files)} JSON files: #{inspect(json_files)}")

        json_files
        |> Enum.map(fn file ->
          %{
            name: Path.basename(file, ".json"),
            path: Path.join(directory, file),
            category: category
          }
        end)

      {:error, reason} ->
        Logger.debug("Error listing directory #{directory}: #{inspect(reason)}")
        []
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
    # Remove .json extension if already present, then add it to prevent double extensions
    clean_filename = String.replace_suffix(filename, ".json", "")
    file_path = Path.join(synth_networks_dir(), "#{clean_filename}.json")

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
