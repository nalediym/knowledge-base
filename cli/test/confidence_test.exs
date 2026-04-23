defmodule Kb.ConfidenceTest do
  use ExUnit.Case, async: true

  alias Kb.Confidence

  describe "score/2" do
    test "known fixture matches expected within ±0.05" do
      # 3 sources, all documentation (quality 1.0), fresh (0 days), 5 backlinks.
      # log(4)/log(11) ≈ 0.578
      # quality                     = 1.000
      # exp(-0/180)                 = 1.000
      # log(6)/log(11) ≈ 0.747
      # weighted avg (0.25 each)   ≈ 0.831
      score =
        Confidence.score(%{
          sources: 3,
          source_quality: ["documentation", "documentation", "documentation"],
          age_days: 0,
          backlinks: 5,
          content_type: "concept"
        })

      assert_in_delta score, 0.83, 0.05
    end

    test "score is clamped to [0, 1]" do
      high =
        Confidence.score(%{
          sources: 1_000_000,
          source_quality: ["official"],
          age_days: 0,
          backlinks: 1_000_000
        })

      assert high <= 1.0
      assert high >= 0.0

      zero = Confidence.score(%{})
      assert zero >= 0.0
      assert zero <= 1.0
    end

    test "raising source weight monotonically raises score when sources > 0" do
      base = %{
        sources: 5,
        source_quality: ["documentation"],
        age_days: 30,
        backlinks: 0,
        content_type: "concept"
      }

      low = Confidence.score(base, %{"weights" => %{"sources" => 0.1, "quality" => 0.3, "recency" => 0.3, "crossrefs" => 0.3}})
      hi = Confidence.score(base, %{"weights" => %{"sources" => 0.7, "quality" => 0.1, "recency" => 0.1, "crossrefs" => 0.1}})

      assert hi > low
    end

    test "older pages receive a lower recency factor" do
      base = fn age ->
        %{
          sources: 1,
          source_quality: ["blog"],
          age_days: age,
          backlinks: 0,
          content_type: "concept"
        }
      end

      young = Confidence.score(base.(0))
      middle = Confidence.score(base.(180))
      old = Confidence.score(base.(1_000))

      assert young > middle
      assert middle > old
    end

    test "decay τ varies by content type" do
      # 60 days is 2x the news τ but under the concept τ
      news = Confidence.score(%{age_days: 60, content_type: "news"})
      concept = Confidence.score(%{age_days: 60, content_type: "concept"})

      assert concept > news
    end

    test "unknown content type falls back to default τ" do
      default_score = Confidence.score(%{age_days: 180, content_type: "default"})
      fallback = Confidence.score(%{age_days: 180, content_type: "mystery"})
      assert_in_delta default_score, fallback, 0.001
    end
  end

  describe "shim_legacy/1" do
    test "maps legacy strings to canonical numeric values" do
      assert Confidence.shim_legacy("high") == 0.85
      assert Confidence.shim_legacy("medium") == 0.55
      assert Confidence.shim_legacy("low") == 0.25
      assert Confidence.shim_legacy(" High ") == 0.85
    end

    test "returns nil for unknown or non-string input" do
      assert Confidence.shim_legacy("unknown") == nil
      assert Confidence.shim_legacy(0.5) == nil
      assert Confidence.shim_legacy(nil) == nil
    end
  end

  describe "bucket/1" do
    test "buckets numeric scores" do
      assert Confidence.bucket(0.9) == "high"
      assert Confidence.bucket(0.5) == "medium"
      assert Confidence.bucket(0.1) == "low"
    end
  end

  describe "config" do
    test "load_config/1 returns empty map when file missing" do
      assert Confidence.load_config("nonexistent.json") == %{}
    end

    test "custom τ changes recency factor" do
      signal = %{age_days: 90, content_type: "code"}
      default = Confidence.score(signal)
      short_tau = Confidence.score(signal, %{"decay_tau_days" => %{"code" => 10}})
      assert default > short_tau
    end
  end
end
