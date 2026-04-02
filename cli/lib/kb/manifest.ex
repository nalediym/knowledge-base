defmodule Kb.Manifest do
  @moduledoc """
  Reads and writes kb/.kb-manifest.json.
  Serializes all manifest access to prevent concurrent write corruption.
  """

  @manifest_path "kb/.kb-manifest.json"

  def path, do: @manifest_path

  def read do
    case File.read(@manifest_path) do
      {:ok, json} -> Jason.decode(json)
      {:error, :enoent} -> {:error, :no_manifest}
    end
  end

  def write(manifest) when is_map(manifest) do
    json = Jason.encode!(manifest, pretty: true)
    File.write!(@manifest_path, json <> "\n")
    :ok
  end

  def add_source(manifest, source_entry) do
    sources = Map.get(manifest, "sources", [])

    # Replace existing entry with same slug, or append
    slug = source_entry["slug"]

    updated =
      case Enum.find_index(sources, &(&1["slug"] == slug)) do
        nil -> sources ++ [source_entry]
        idx -> List.replace_at(sources, idx, source_entry)
      end

    Map.put(manifest, "sources", updated)
  end

  def new(project_name) do
    %{
      "version" => 1,
      "created" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "last_compiled" => nil,
      "sources" => [],
      "name" => project_name
    }
  end
end
