defmodule Kb.LLM.Heuristic do
  @moduledoc """
  No-network heuristic claim comparator.

  Strategy:
    1. Tokenize both claims, strip stopwords, find shared content words.
       If overlap is too low the pair is unrelated → :unknown.
    2. Over the shared-topic pairs, detect polarity conflict via:
         a. negation asymmetry (only one side carries `no/not/never/cannot`
            or `n't`),
         b. antonym pair hit (common opposing adjectives/verbs),
         c. numeric disagreement on the same unit/noun.
    3. Otherwise → :agree.

  Not meant to be production-grade — enough signal to flag planted
  contradictions in tests and small KBs without requiring an API key.
  """

  @behaviour Kb.LLM

  @stopwords MapSet.new(~w(
    a an the is are was were be been being am
    do does did done doing of in on at to for with by from into onto
    that this these those it its they them their there here
    as if then than so but or and not no
    have has had having
    can cannot could should would may might must will
    i you he she we us our your my me him her
    about over under between across through during
    some any all each every many few more most less least
  ))

  # Pairs of opposing terms. Directional: if a claim contains the left and
  # the other claim contains the right (or vice versa), that's a conflict
  # signal — provided they share topic.
  @antonyms [
    {"increase", "decrease"},
    {"increases", "decreases"},
    {"rises", "falls"},
    {"rise", "fall"},
    {"faster", "slower"},
    {"fast", "slow"},
    {"hot", "cold"},
    {"high", "low"},
    {"large", "small"},
    {"big", "small"},
    {"more", "less"},
    {"always", "never"},
    {"safe", "unsafe"},
    {"secure", "insecure"},
    {"stateful", "stateless"},
    {"synchronous", "asynchronous"},
    {"dense", "sparse"},
    {"linear", "quadratic"},
    {"allowed", "forbidden"},
    {"allowed", "disallowed"},
    {"enabled", "disabled"},
    {"possible", "impossible"},
    {"true", "false"},
    {"yes", "no"},
    {"up", "down"}
  ]

  @neg_markers ~w(not no never cannot can't won't don't doesn't didn't isn't aren't wasn't weren't shouldn't wouldn't couldn't)

  @impl Kb.LLM
  def compare_claims(a, b) do
    text_a = normalize(a.text)
    text_b = normalize(b.text)

    tokens_a = tokens(text_a)
    tokens_b = tokens(text_b)

    overlap = MapSet.intersection(MapSet.new(tokens_a), MapSet.new(tokens_b))

    cond do
      MapSet.size(overlap) < 2 ->
        :unknown

      antonym_conflict?(text_a, text_b) ->
        :disagree

      negation_asymmetry?(text_a, text_b) ->
        :disagree

      numeric_conflict?(text_a, text_b, overlap) ->
        :disagree

      true ->
        :agree
    end
  end

  defp normalize(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s\.\-']/, " ")
  end

  defp tokens(text) do
    text
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reject(&(&1 in @stopwords or String.length(&1) < 3))
  end

  defp antonym_conflict?(a, b) do
    Enum.any?(@antonyms, fn {x, y} ->
      (word_present?(a, x) and word_present?(b, y)) or
        (word_present?(a, y) and word_present?(b, x))
    end)
  end

  defp negation_asymmetry?(a, b) do
    has_a = Enum.any?(@neg_markers, &word_present?(a, &1))
    has_b = Enum.any?(@neg_markers, &word_present?(b, &1))
    has_a != has_b
  end

  defp word_present?(text, word) do
    Regex.match?(~r/\b#{Regex.escape(word)}\b/, text)
  end

  # Numeric conflict: both claims carry a number followed by the same
  # shared content word (overlap) and the numbers differ.
  defp numeric_conflict?(a, b, overlap) do
    nums_a = numbers_near_words(a, overlap)
    nums_b = numbers_near_words(b, overlap)

    Enum.any?(nums_a, fn {word, num_a} ->
      case Enum.find(nums_b, fn {w, _} -> w == word end) do
        {_, num_b} -> num_a != num_b
        nil -> false
      end
    end)
  end

  defp numbers_near_words(text, shared_words) do
    Regex.scan(~r/(\d+(?:\.\d+)?)\s*[a-z%]*\s+([a-z\-]+)/, text)
    |> Enum.map(fn [_, num, word] -> {word, num} end)
    |> Enum.filter(fn {word, _} -> MapSet.member?(shared_words, word) end)
  end
end
