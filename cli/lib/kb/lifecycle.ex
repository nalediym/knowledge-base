defmodule Kb.Lifecycle do
  @moduledoc """
  5-state lifecycle machine for wiki pages.

      draft ──kb review──→ reviewed ──kb verify──→ verified
        │                      │                      │
        │                      │                      ├─(hash drift)─→ reviewed
        │                      │                      │
        └─(stale_after days)───┴──────────────────────┴──→ stale ──kb archive──→ archived

  States live as YAML frontmatter at the top of every wiki page:

      ---
      lifecycle: verified
      last_seen: 2026-04-23T12:34:56Z
      ---

  Transitions beyond the diagram are illegal and rejected with a clear error.

  Composes with the existing `REVIEWED [sha256:<hash>]` tag: on `kb verify`
  the body is hashed and the tag is stamped; on `kb build` pages whose current
  body hash diverges from the stamped hash are demoted verified → reviewed
  (or warn, per config).
  """

  @states ~w(draft reviewed verified stale archived)a
  @state_strings Enum.map(@states, &Atom.to_string/1)

  # current_state => set of target states reachable by any non-compile mechanism
  # (manual command or auto-demotion). Compile-driven demotions are encoded
  # separately below.
  @transitions %{
    draft: [:reviewed, :stale, :archived],
    reviewed: [:verified, :stale, :archived],
    verified: [:reviewed, :stale, :archived],
    stale: [:reviewed, :archived],
    archived: []
  }

  @default_stale_after_days 90
  @reviewed_tag_regex ~r/REVIEWED \[sha256:([0-9a-f]{64})\]/

  @doc "All valid lifecycle states, as atoms."
  def states, do: @states

  @doc "All valid lifecycle states, as strings."
  def state_strings, do: @state_strings

  @doc "Default state for unknown / missing frontmatter."
  def default_state, do: :draft

  @doc "Regex used to find the stamped REVIEWED tag."
  def reviewed_tag_regex, do: @reviewed_tag_regex

  @doc """
  Whether a manual/auto transition from `from` to `to` is allowed.
  Identity transitions (:reviewed → :reviewed etc.) are allowed and are no-ops.
  """
  def can_transition?(same, same) when is_atom(same), do: same in @states

  def can_transition?(from, to) when is_atom(from) and is_atom(to) do
    to in Map.get(@transitions, from, [])
  end

  @doc """
  Transition `from` → `to` or return `{:error, message}`.

  Identity transitions are a no-op and succeed.
  """
  def transition(from, to) when is_atom(from) and is_atom(to) do
    cond do
      from == to ->
        {:ok, to}

      can_transition?(from, to) ->
        {:ok, to}

      true ->
        {:error, "illegal transition: #{from} -> #{to}"}
    end
  end

  @doc "Parse a state string into an atom, or {:error, msg}."
  def parse_state(value) when is_binary(value) do
    v = value |> String.trim() |> String.downcase()

    if v in @state_strings do
      {:ok, String.to_atom(v)}
    else
      {:error, "invalid lifecycle state: #{inspect(value)} (valid: #{Enum.join(@state_strings, ", ")})"}
    end
  end

  def parse_state(other), do: {:error, "invalid lifecycle state: #{inspect(other)}"}

  @doc """
  Split a page into `{frontmatter_map, body}`.

  Supports either a YAML frontmatter block delimited by `---` at the very top,
  or no frontmatter (returns `{%{}, content}`).

  Keys are returned as strings.
  """
  def parse_page(content) when is_binary(content) do
    case content do
      "---\n" <> rest ->
        case String.split(rest, ~r/\n---\n/, parts: 2) do
          [yaml, body] ->
            meta =
              case YamlElixir.read_from_string(yaml) do
                {:ok, map} when is_map(map) -> map
                _ -> %{}
              end

            {meta, body}

          _ ->
            {%{}, content}
        end

      _ ->
        {%{}, content}
    end
  end

  @doc """
  Serialize `{frontmatter, body}` back into a markdown page. Keys are sorted
  for deterministic output. Returns a string.
  """
  def render_page(frontmatter, body) when is_map(frontmatter) and is_binary(body) do
    case frontmatter do
      empty when empty == %{} ->
        body

      _ ->
        yaml =
          frontmatter
          |> Enum.sort_by(fn {k, _} -> to_string(k) end)
          |> Enum.map_join("\n", fn {k, v} -> "#{k}: #{format_scalar(v)}" end)

        "---\n" <> yaml <> "\n---\n" <> body
    end
  end

  defp format_scalar(v) when is_binary(v), do: v
  defp format_scalar(v) when is_atom(v), do: Atom.to_string(v)
  defp format_scalar(v) when is_integer(v) or is_float(v), do: to_string(v)
  defp format_scalar(v), do: inspect(v)

  @doc """
  Read the current state from a frontmatter map.

  Returns the atom state. Pages without `lifecycle:` are treated as `:draft`
  (backwards-compatible).
  """
  def state_of(frontmatter) when is_map(frontmatter) do
    case Map.get(frontmatter, "lifecycle") do
      nil ->
        :draft

      v ->
        case parse_state(v) do
          {:ok, s} -> s
          _ -> :draft
        end
    end
  end

  @doc """
  Compute sha256 of the page body. Whitespace is preserved; the REVIEWED tag
  itself and any trailing whitespace are stripped before hashing so re-stamping
  produces a stable self-referential hash.
  """
  def body_hash(body) when is_binary(body) do
    cleaned =
      body
      |> String.replace(@reviewed_tag_regex, "")
      |> String.trim_trailing()

    :crypto.hash(:sha256, cleaned) |> Base.encode16(case: :lower)
  end

  @doc "Extract the sha256 from a stamped REVIEWED tag, or nil."
  def stamped_hash(body) when is_binary(body) do
    case Regex.run(@reviewed_tag_regex, body) do
      [_, hash] -> hash
      _ -> nil
    end
  end

  @doc """
  Stamp a `REVIEWED [sha256:<hash>]` tag onto the body, replacing any existing
  stamp. The hash is computed from the body *without* the tag so it remains
  stable.
  """
  def stamp_reviewed(body) when is_binary(body) do
    hash = body_hash(body)

    stripped =
      body
      |> String.replace(@reviewed_tag_regex, "")
      |> String.trim_trailing()

    stripped <> "\n\nREVIEWED [sha256:#{hash}]\n"
  end

  @doc """
  Check a `verified` page for hash drift.

  Returns one of:
    - `:ok` — stamped hash matches current body
    - `{:drift, stamped, current}` — body has diverged; caller should demote
    - `:no_stamp` — verified page without a stamp; caller should demote
  """
  def check_drift(:verified, body) do
    case stamped_hash(body) do
      nil ->
        :no_stamp

      stamped ->
        current = body_hash(body)
        if stamped == current, do: :ok, else: {:drift, stamped, current}
    end
  end

  def check_drift(_state, _body), do: :ok

  @doc """
  Return `:stale` if a page's `last_seen` is older than `stale_after_days`
  relative to `now`, otherwise `:fresh`.

  `last_seen` may be an ISO8601 string, a `DateTime`, or `nil`.
  Archived pages are never auto-staled.
  """
  def check_auto_stale(state, _last_seen, _stale_after_days, _now)
      when state in [:stale, :archived],
      do: :fresh

  def check_auto_stale(_state, nil, _stale_after_days, _now), do: :stale

  def check_auto_stale(_state, last_seen, stale_after_days, now) do
    case normalize_datetime(last_seen) do
      {:ok, dt} ->
        age_days = DateTime.diff(now, dt, :second) |> div(86_400)
        if age_days >= stale_after_days, do: :stale, else: :fresh

      :error ->
        :stale
    end
  end

  defp normalize_datetime(%DateTime{} = dt), do: {:ok, dt}

  defp normalize_datetime(s) when is_binary(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> {:ok, dt}
      _ -> :error
    end
  end

  defp normalize_datetime(_), do: :error

  @doc """
  Config accessors. Reads `lifecycle.stale_after_days` and
  `lifecycle.drift_action` from the decoded config map, with sane defaults.
  """
  def stale_after_days(config) when is_map(config) do
    case get_in(config, ["lifecycle", "stale_after_days"]) do
      n when is_integer(n) and n > 0 -> n
      _ -> @default_stale_after_days
    end
  end

  def stale_after_days(_), do: @default_stale_after_days

  def drift_action(config) when is_map(config) do
    case get_in(config, ["lifecycle", "drift_action"]) do
      "warn" -> :warn
      "demote" -> :demote
      _ -> :demote
    end
  end

  def drift_action(_), do: :demote

  @doc """
  Backwards-compat helper: given a page's content, return the content with
  `lifecycle:` frontmatter filled in if missing. Returns `{content, changed?}`.
  """
  def ensure_lifecycle_frontmatter(content) when is_binary(content) do
    {meta, body} = parse_page(content)

    if Map.has_key?(meta, "lifecycle") do
      {content, false}
    else
      new_meta = Map.put(meta, "lifecycle", "draft")
      {render_page(new_meta, body), true}
    end
  end

  @doc """
  Apply a user-driven transition to page content. Updates the `lifecycle` key
  in frontmatter and, for `:verify`, stamps the REVIEWED tag.

  Commands are strict (stricter than the general transition table, which also
  admits auto-demotions):

    - `:review`  accepts only `draft → reviewed`
    - `:verify`  accepts only `reviewed → verified`
    - `:archive` accepts any non-archived state

  Returns `{:ok, new_content, new_state}` or `{:error, reason}`.
  """
  def apply_command(content, action) when action in [:review, :verify, :archive] do
    {meta, body} = parse_page(content)
    current = state_of(meta)

    with {:ok, target} <- command_transition(action, current) do
      {new_meta, new_body} =
        case action do
          :verify -> {Map.put(meta, "lifecycle", "verified"), stamp_reviewed(body)}
          :review -> {Map.put(meta, "lifecycle", "reviewed"), body}
          :archive -> {Map.put(meta, "lifecycle", "archived"), body}
        end

      {:ok, render_page(new_meta, new_body), target}
    end
  end

  defp command_transition(:review, :draft), do: {:ok, :reviewed}
  defp command_transition(:review, other),
    do: {:error, "kb review requires lifecycle=draft, got #{other}"}

  defp command_transition(:verify, :reviewed), do: {:ok, :verified}
  defp command_transition(:verify, other),
    do: {:error, "kb verify requires lifecycle=reviewed, got #{other}"}

  defp command_transition(:archive, :archived),
    do: {:error, "page is already archived"}
  defp command_transition(:archive, _), do: {:ok, :archived}
end
