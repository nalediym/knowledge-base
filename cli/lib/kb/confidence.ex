defmodule Kb.Confidence do
  @moduledoc """
  Numeric confidence scoring for concept pages (0.0–1.0).

  Replaces legacy `confidence: high|medium|low` string frontmatter with a
  4-factor weighted score plus Ebbinghaus decay per content-type:

      confidence = w_s · log(sources + 1)
                 + w_q · avg(source_quality)
                 + w_r · exp(-age_days / τ)
                 + w_x · log(backlinks + 1)

  Weights and τ are read from `kb.config.json`:

      "confidence": {
        "weights":        { "sources": 0.25, "quality": 0.25,
                            "recency": 0.25, "crossrefs": 0.25 },
        "decay_tau_days": { "code": 90, "concept": 365, "news": 30,
                            "default": 180 }
      }

  Log terms are normalised by `log(11)` so 10 sources / 10 backlinks ≈ 1.0,
  keeping every factor in [0,1] and weights interpretable.
  """

  @default_weights %{
    "sources" => 0.25,
    "quality" => 0.25,
    "recency" => 0.25,
    "crossrefs" => 0.25
  }

  @default_tau %{
    "code" => 90,
    "concept" => 365,
    "news" => 30,
    "default" => 180
  }

  # Source-quality label → [0,1]. Mirrors llm-wiki's mapping.
  @quality_map %{
    "official" => 1.0,
    "documentation" => 1.0,
    "peer_reviewed" => 0.9,
    "paper" => 0.9,
    "blog" => 0.7,
    "tutorial" => 0.7,
    "forum" => 0.5,
    "session_transcript" => 0.5,
    "llm_generated" => 0.3,
    "unknown" => 0.4
  }

  # Legacy `high|medium|low` → numeric shim used on first compile.
  @legacy_map %{"high" => 0.85, "medium" => 0.55, "low" => 0.25}

  @log_norm :math.log(11)

  @doc """
  Compute confidence for a concept. Accepts a plain map with the following
  keys (all optional, defaults shown):

    * `:sources`       — integer, number of distinct raw sources (default 0)
    * `:source_quality`— list of quality labels or floats (default [])
    * `:age_days`      — integer, age of newest source in days (default 0)
    * `:backlinks`     — integer, inbound wiki links (default 0)
    * `:content_type`  — "code" | "concept" | "news" | other (default "default")

  Config overrides default weights and τ when passed in. Returns a float in
  [0.0, 1.0] rounded to 2 decimal places.
  """
  def score(concept, config \\ %{}) when is_map(concept) do
    weights = weights(config)
    tau = tau_for(Map.get(concept, :content_type, "default"), config)

    sources = Map.get(concept, :sources, 0) |> max(0)
    qualities = Map.get(concept, :source_quality, [])
    age_days = Map.get(concept, :age_days, 0) |> max(0)
    backlinks = Map.get(concept, :backlinks, 0) |> max(0)

    f_sources = :math.log(sources + 1) / @log_norm
    f_quality = avg_quality(qualities)
    f_recency = :math.exp(-age_days / tau)
    f_cross = :math.log(backlinks + 1) / @log_norm

    raw =
      weights["sources"] * f_sources +
        weights["quality"] * f_quality +
        weights["recency"] * f_recency +
        weights["crossrefs"] * f_cross

    raw
    |> clamp()
    |> Float.round(2)
  end

  @doc "Read the `confidence` block from `kb.config.json` (returns a plain map)."
  def load_config(path \\ "kb.config.json") do
    case File.read(path) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, %{"confidence" => conf}} when is_map(conf) -> conf
          _ -> %{}
        end

      _ ->
        %{}
    end
  end

  @doc """
  Convert a legacy `high|medium|low` string to a numeric score. Returns
  `nil` when the value is already numeric or unrecognised.
  """
  def shim_legacy(value) when is_binary(value) do
    Map.get(@legacy_map, String.downcase(String.trim(value)))
  end

  def shim_legacy(_), do: nil

  @doc "Human-readable label for a numeric score (used by lint/query output)."
  def bucket(score) when is_number(score) do
    cond do
      score >= 0.7 -> "high"
      score >= 0.4 -> "medium"
      true -> "low"
    end
  end

  @doc "Score lookup for a source-quality label (or passthrough for numbers)."
  def quality_value(q) when is_number(q), do: clamp(q * 1.0)

  def quality_value(q) when is_binary(q) do
    Map.get(@quality_map, String.downcase(String.trim(q)), 0.4)
  end

  def quality_value(_), do: 0.4

  # ── internals ────────────────────────────────────────────────────────

  defp weights(config) do
    raw = get_in(config, ["weights"]) || %{}
    Map.merge(@default_weights, normalise_map(raw))
  end

  defp tau_for(content_type, config) do
    taus = get_in(config, ["decay_tau_days"]) || %{}
    merged = Map.merge(@default_tau, normalise_map(taus))
    Map.get(merged, to_string(content_type), merged["default"])
  end

  defp normalise_map(m) when is_map(m) do
    for {k, v} <- m, into: %{}, do: {to_string(k), v}
  end

  defp normalise_map(_), do: %{}

  defp avg_quality([]), do: 0.4

  defp avg_quality(list) when is_list(list) do
    values = Enum.map(list, &quality_value/1)
    Enum.sum(values) / length(values)
  end

  defp avg_quality(q), do: quality_value(q)

  defp clamp(x) when x < 0.0, do: 0.0
  defp clamp(x) when x > 1.0, do: 1.0
  defp clamp(x), do: x * 1.0
end
