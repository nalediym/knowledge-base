defmodule Kb.Manifest do
  @moduledoc """
  Reads and writes kb/.kb-manifest.json.
  Serializes all manifest access to prevent concurrent write corruption.
  Uses file-based locking to prevent corruption from concurrent sessions.
  """

  @manifest_path "kb/.kb-manifest.json"
  @lock_path "kb/.kb-lock"
  @lock_stale_seconds 300

  def path, do: @manifest_path
  def lock_path, do: @lock_path

  def read do
    case File.read(@manifest_path) do
      {:ok, json} -> Jason.decode(json)
      {:error, :enoent} -> {:error, :no_manifest}
    end
  end

  def write(manifest) when is_map(manifest) do
    case acquire_lock("write") do
      :ok ->
        try do
          json = Jason.encode!(manifest, pretty: true)
          File.write!(@manifest_path, json <> "\n")
          :ok
        after
          release_lock()
        end

      {:error, :locked} ->
        {:error, :locked}
    end
  end

  defp acquire_lock(operation) do
    case File.read(@lock_path) do
      {:ok, lock_json} ->
        case Jason.decode(lock_json) do
          {:ok, lock} ->
            lock_ts = Map.get(lock, "ts", "")
            age = lock_age_seconds(lock_ts)

            if age > @lock_stale_seconds do
              IO.puts("Warning: Stale lock found (PID #{lock["pid"]}, #{age}s ago). Overriding.")
              write_lock(operation)
            else
              IO.puts("Error: KB is locked by PID #{lock["pid"]} (#{lock["operation"]}). " <>
                "Wait or remove #{@lock_path} if stale.")
              {:error, :locked}
            end

          _ ->
            write_lock(operation)
        end

      {:error, :enoent} ->
        write_lock(operation)
    end
  end

  defp write_lock(operation) do
    lock = %{
      "pid" => System.pid() |> to_string(),
      "ts" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "operation" => operation
    }

    File.write!(@lock_path, Jason.encode!(lock))
    :ok
  end

  defp release_lock do
    File.rm(@lock_path)
  end

  defp lock_age_seconds(ts_string) do
    case DateTime.from_iso8601(ts_string) do
      {:ok, ts, _} -> DateTime.diff(DateTime.utc_now(), ts)
      _ -> @lock_stale_seconds + 1
    end
  end

  @doc """
  Atomically read-modify-write the manifest under lock.
  Prevents concurrent sessions from losing each other's changes.
  """
  def update(operation, fun) when is_function(fun, 1) do
    case acquire_lock(operation) do
      :ok ->
        try do
          case read() do
            {:ok, manifest} ->
              updated = fun.(manifest)
              json = Jason.encode!(updated, pretty: true)
              File.write!(@manifest_path, json <> "\n")
              {:ok, updated}

            {:error, :no_manifest} ->
              {:error, :no_manifest}
          end
        after
          release_lock()
        end

      {:error, :locked} ->
        {:error, :locked}
    end
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
