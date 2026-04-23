defmodule Kb.LifecycleTest do
  use ExUnit.Case, async: true

  alias Kb.Lifecycle

  describe "can_transition?/2" do
    test "legal manual transitions" do
      assert Lifecycle.can_transition?(:draft, :reviewed)
      assert Lifecycle.can_transition?(:reviewed, :verified)
      assert Lifecycle.can_transition?(:verified, :reviewed)
      assert Lifecycle.can_transition?(:draft, :archived)
      assert Lifecycle.can_transition?(:verified, :archived)
      assert Lifecycle.can_transition?(:stale, :reviewed)
      assert Lifecycle.can_transition?(:stale, :archived)
    end

    test "auto-demotion transitions to stale are legal" do
      assert Lifecycle.can_transition?(:draft, :stale)
      assert Lifecycle.can_transition?(:reviewed, :stale)
      assert Lifecycle.can_transition?(:verified, :stale)
    end

    test "illegal transitions are rejected" do
      refute Lifecycle.can_transition?(:draft, :verified)
      refute Lifecycle.can_transition?(:archived, :reviewed)
      refute Lifecycle.can_transition?(:archived, :verified)
      refute Lifecycle.can_transition?(:reviewed, :draft)
      refute Lifecycle.can_transition?(:verified, :draft)
    end

    test "identity transitions are no-ops" do
      assert Lifecycle.can_transition?(:draft, :draft)
      assert Lifecycle.can_transition?(:reviewed, :reviewed)
    end
  end

  describe "apply_command/2 — strict command rules" do
    test "kb review promotes draft to reviewed" do
      content = "---\nlifecycle: draft\n---\n# Hello\n"

      assert {:ok, new, :reviewed} = Lifecycle.apply_command(content, :review)
      assert new =~ "lifecycle: reviewed"
    end

    test "kb review rejects a non-draft page" do
      content = "---\nlifecycle: reviewed\n---\n# Hello\n"
      assert {:error, msg} = Lifecycle.apply_command(content, :review)
      assert msg =~ "requires lifecycle=draft"
    end

    test "kb verify promotes reviewed to verified and stamps REVIEWED tag" do
      content = "---\nlifecycle: reviewed\n---\n# Body\n\nSome text.\n"

      assert {:ok, new, :verified} = Lifecycle.apply_command(content, :verify)
      assert new =~ "lifecycle: verified"
      assert new =~ ~r/REVIEWED \[sha256:[0-9a-f]{64}\]/
    end

    test "kb verify rejects a draft page" do
      content = "---\nlifecycle: draft\n---\n# Body\n"
      assert {:error, msg} = Lifecycle.apply_command(content, :verify)
      assert msg =~ "requires lifecycle=reviewed"
    end

    test "kb verify rejects an archived page" do
      content = "---\nlifecycle: archived\n---\n# Body\n"
      assert {:error, _} = Lifecycle.apply_command(content, :verify)
    end

    test "kb archive accepts any non-archived state" do
      for state <- ~w(draft reviewed verified stale) do
        content = "---\nlifecycle: #{state}\n---\n# Body\n"
        assert {:ok, new, :archived} = Lifecycle.apply_command(content, :archive)
        assert new =~ "lifecycle: archived"
      end
    end

    test "kb archive on an already-archived page is an error" do
      content = "---\nlifecycle: archived\n---\n# Body\n"
      assert {:error, msg} = Lifecycle.apply_command(content, :archive)
      assert msg =~ "already archived"
    end

    test "pages without frontmatter are treated as draft" do
      content = "# A bare page\n\nNo frontmatter.\n"
      assert {:ok, new, :reviewed} = Lifecycle.apply_command(content, :review)
      assert new =~ "lifecycle: reviewed"
    end
  end

  describe "backwards compat" do
    test "ensure_lifecycle_frontmatter/1 fills draft when missing" do
      {new, changed?} = Lifecycle.ensure_lifecycle_frontmatter("# Hello\n\nBody.\n")
      assert changed?
      assert new =~ "lifecycle: draft"
    end

    test "ensure_lifecycle_frontmatter/1 is a no-op when already set" do
      content = "---\nlifecycle: verified\n---\n# Body\n"
      {new, changed?} = Lifecycle.ensure_lifecycle_frontmatter(content)
      refute changed?
      assert new == content
    end
  end

  describe "hash drift" do
    test "stamp + check_drift round-trips" do
      body = "# Title\n\nStable content.\n"
      stamped = Lifecycle.stamp_reviewed(body)
      assert :ok = Lifecycle.check_drift(:verified, stamped)
    end

    test "editing a verified body triggers drift" do
      body = "# Title\n\nOriginal content.\n"
      stamped = Lifecycle.stamp_reviewed(body)
      edited = String.replace(stamped, "Original", "Edited")
      assert {:drift, _, _} = Lifecycle.check_drift(:verified, edited)
    end

    test "verified without a stamp is flagged :no_stamp" do
      assert :no_stamp = Lifecycle.check_drift(:verified, "# No stamp here\n")
    end

    test "non-verified pages are never drifted" do
      assert :ok = Lifecycle.check_drift(:draft, "whatever")
      assert :ok = Lifecycle.check_drift(:reviewed, "whatever")
      assert :ok = Lifecycle.check_drift(:stale, "whatever")
    end
  end

  describe "check_auto_stale/4" do
    test "page fresher than threshold stays fresh" do
      now = ~U[2026-04-23 12:00:00Z]
      recent = DateTime.add(now, -10 * 86_400)
      assert :fresh = Lifecycle.check_auto_stale(:reviewed, recent, 90, now)
    end

    test "91-day-old page goes stale" do
      now = ~U[2026-04-23 12:00:00Z]
      old = DateTime.add(now, -91 * 86_400)
      assert :stale = Lifecycle.check_auto_stale(:reviewed, old, 90, now)
      assert :stale = Lifecycle.check_auto_stale(:verified, old, 90, now)
      assert :stale = Lifecycle.check_auto_stale(:draft, old, 90, now)
    end

    test "already-stale and archived pages are not re-staled" do
      now = ~U[2026-04-23 12:00:00Z]
      old = DateTime.add(now, -1000 * 86_400)
      assert :fresh = Lifecycle.check_auto_stale(:stale, old, 90, now)
      assert :fresh = Lifecycle.check_auto_stale(:archived, old, 90, now)
    end

    test "missing last_seen is treated as stale" do
      now = ~U[2026-04-23 12:00:00Z]
      assert :stale = Lifecycle.check_auto_stale(:draft, nil, 90, now)
    end

    test "accepts ISO8601 strings" do
      now = ~U[2026-04-23 12:00:00Z]
      assert :stale = Lifecycle.check_auto_stale(:reviewed, "2024-01-01T00:00:00Z", 90, now)
      assert :fresh = Lifecycle.check_auto_stale(:reviewed, "2026-04-01T00:00:00Z", 90, now)
    end
  end

  describe "config" do
    test "stale_after_days defaults to 90 and respects override" do
      assert Lifecycle.stale_after_days(%{}) == 90
      assert Lifecycle.stale_after_days(%{"lifecycle" => %{"stale_after_days" => 30}}) == 30
      # Invalid value falls back to default
      assert Lifecycle.stale_after_days(%{"lifecycle" => %{"stale_after_days" => -1}}) == 90
    end

    test "drift_action defaults to :demote" do
      assert Lifecycle.drift_action(%{}) == :demote
      assert Lifecycle.drift_action(%{"lifecycle" => %{"drift_action" => "warn"}}) == :warn
      assert Lifecycle.drift_action(%{"lifecycle" => %{"drift_action" => "demote"}}) == :demote
    end
  end
end
