defmodule Kb.LifecycleSweep do
  @moduledoc """
  Compile-time lifecycle sweep: walks every wiki page and applies:

    1. Backwards-compat: fills `lifecycle: draft` for pages with no key
    2. Auto-stale demotion when `last_seen` is older than
       `lifecycle.stale_after_days` (default 90)
    3. Drift demotion when a `verified` page's body hashes differently from
       its stamped `REVIEWED [sha256:]` tag (per `lifecycle.drift_action`)

  Returns a summary map so callers can report or roll up stats.
  """

  alias Kb.Lifecycle

  @default_wiki_glob "kb/wiki/**/*.md"

  @doc """
  Run the sweep across every markdown file matching `glob`.

  `opts`:
    - :config         — decoded kb.config.json (map). Defaults to {}.
    - :glob           — glob pattern. Defaults to `kb/wiki/**/*.md`.
    - :now            — reference DateTime. Defaults to `DateTime.utc_now/0`.
    - :last_seen_fn   — function/1 returning `DateTime` or ISO8601 string for
                        a given page path. Defaults to file mtime.
  """
  def run(opts \\ []) do
    config = Keyword.get(opts, :config, %{})
    glob = Keyword.get(opts, :glob, @default_wiki_glob)
    now = Keyword.get(opts, :now, DateTime.utc_now())
    last_seen_fn = Keyword.get(opts, :last_seen_fn, &mtime_last_seen/1)

    stale_after = Lifecycle.stale_after_days(config)
    drift_action = Lifecycle.drift_action(config)

    files = Path.wildcard(glob)

    acc = %{
      visited: 0,
      filled_default: 0,
      auto_staled: 0,
      drift_demoted: 0,
      drift_warned: 0,
      by_state: %{draft: 0, reviewed: 0, verified: 0, stale: 0, archived: 0},
      stale_by_project: %{}
    }

    Enum.reduce(files, acc, fn file, acc ->
      sweep_file(file, acc, %{
        stale_after: stale_after,
        drift_action: drift_action,
        now: now,
        last_seen_fn: last_seen_fn
      })
    end)
  end

  defp sweep_file(path, acc, opts) do
    case File.read(path) do
      {:error, _} ->
        acc

      {:ok, original} ->
        {content, filled?} = Lifecycle.ensure_lifecycle_frontmatter(original)
        {meta, body} = Lifecycle.parse_page(content)
        current = Lifecycle.state_of(meta)

        # Drift check first — a stale verified page that's also drifted should
        # be demoted to reviewed, then evaluated for staleness.
        {current, meta, body, drift_delta} =
          apply_drift(current, meta, body, opts.drift_action)

        last_seen = opts.last_seen_fn.(path)

        {current, meta, staled?} =
          apply_auto_stale(current, meta, last_seen, opts.stale_after, opts.now)

        new_content = Lifecycle.render_page(meta, body)

        if new_content != original do
          File.write!(path, new_content)
        end

        acc
        |> Map.update!(:visited, &(&1 + 1))
        |> maybe_inc(:filled_default, filled?)
        |> maybe_inc(:auto_staled, staled?)
        |> merge_drift(drift_delta)
        |> update_in([:by_state, current], &(&1 + 1))
        |> update_stale_by_project(path, current)
    end
  end

  defp apply_drift(:verified, meta, body, action) do
    case Lifecycle.check_drift(:verified, body) do
      :ok ->
        {:verified, meta, body, :none}

      :no_stamp ->
        handle_drift(:no_stamp, meta, body, action)

      {:drift, _stamped, _current} ->
        handle_drift(:drift, meta, body, action)
    end
  end

  defp apply_drift(state, meta, body, _action), do: {state, meta, body, :none}

  defp handle_drift(kind, meta, body, :demote) do
    {:reviewed, Map.put(meta, "lifecycle", "reviewed"), body, {:demoted, kind}}
  end

  defp handle_drift(kind, meta, body, :warn) do
    {:verified, meta, body, {:warned, kind}}
  end

  defp apply_auto_stale(state, meta, last_seen, stale_after, now) do
    case Lifecycle.check_auto_stale(state, last_seen, stale_after, now) do
      :stale when state not in [:stale, :archived] ->
        {:stale, Map.put(meta, "lifecycle", "stale"), true}

      _ ->
        {state, meta, false}
    end
  end

  defp maybe_inc(acc, _key, false), do: acc
  defp maybe_inc(acc, key, true), do: Map.update!(acc, key, &(&1 + 1))

  defp merge_drift(acc, :none), do: acc
  defp merge_drift(acc, {:demoted, _}), do: Map.update!(acc, :drift_demoted, &(&1 + 1))
  defp merge_drift(acc, {:warned, _}), do: Map.update!(acc, :drift_warned, &(&1 + 1))

  defp update_stale_by_project(acc, path, :stale) do
    project = project_of(path)
    Map.update!(acc, :stale_by_project, &Map.update(&1, project, 1, fn n -> n + 1 end))
  end

  defp update_stale_by_project(acc, _path, _state), do: acc

  # Derive a "project" bucket from the path. For a layout like
  # `kb/wiki/sources/<slug>.md` or `kb/wiki/concepts/<slug>.md` we use the
  # immediate parent directory beneath `wiki/`.
  defp project_of(path) do
    case Path.split(path) do
      parts ->
        case Enum.drop_while(parts, &(&1 != "wiki")) do
          ["wiki", bucket | _] -> bucket
          _ -> "unknown"
        end
    end
  end

  defp mtime_last_seen(path) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: m}} ->
        DateTime.from_unix!(m)

      _ ->
        nil
    end
  end
end
