defmodule Kb.LifecycleSweepTest do
  use ExUnit.Case

  alias Kb.Lifecycle
  alias Kb.LifecycleSweep

  setup do
    tmp = Path.join(System.tmp_dir!(), "kb-lifecycle-#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(tmp, "kb/wiki/concepts"))
    File.mkdir_p!(Path.join(tmp, "kb/wiki/sources"))

    on_exit(fn -> File.rm_rf!(tmp) end)

    {:ok, tmp: tmp}
  end

  test "fills default lifecycle for pages without frontmatter", %{tmp: tmp} do
    path = Path.join(tmp, "kb/wiki/concepts/a.md")
    File.write!(path, "# Untagged page\n\nSome content.\n")

    now = DateTime.utc_now()

    summary =
      LifecycleSweep.run(
        glob: Path.join(tmp, "kb/wiki/**/*.md"),
        now: now,
        # keep fresh regardless of mtime
        last_seen_fn: fn _ -> now end
      )

    assert summary.filled_default == 1
    updated = File.read!(path)
    assert updated =~ "lifecycle: draft"
    assert summary.by_state.draft == 1
  end

  test "91-day-old page auto-demotes to stale", %{tmp: tmp} do
    path = Path.join(tmp, "kb/wiki/concepts/old.md")
    File.write!(path, "---\nlifecycle: reviewed\n---\n# Old page\n")

    now = ~U[2026-04-23 12:00:00Z]
    old = DateTime.add(now, -91 * 86_400)

    summary =
      LifecycleSweep.run(
        glob: Path.join(tmp, "kb/wiki/**/*.md"),
        now: now,
        last_seen_fn: fn _ -> old end
      )

    assert summary.auto_staled == 1
    assert summary.by_state.stale == 1

    {meta, _body} = Lifecycle.parse_page(File.read!(path))
    assert Lifecycle.state_of(meta) == :stale
    assert summary.stale_by_project == %{"concepts" => 1}
  end

  test "90-day-old page (exactly) goes stale; 89-day-old stays fresh", %{tmp: tmp} do
    ok_path = Path.join(tmp, "kb/wiki/concepts/fresh.md")
    File.write!(ok_path, "---\nlifecycle: reviewed\n---\n# Fresh\n")

    now = ~U[2026-04-23 12:00:00Z]

    summary =
      LifecycleSweep.run(
        glob: Path.join(tmp, "kb/wiki/**/*.md"),
        now: now,
        last_seen_fn: fn _ -> DateTime.add(now, -89 * 86_400) end
      )

    assert summary.auto_staled == 0
    assert summary.by_state.reviewed == 1
  end

  test "verified page with drifted body demotes to reviewed", %{tmp: tmp} do
    path = Path.join(tmp, "kb/wiki/sources/drifted.md")
    original_body = "# Verified\n\nStable content.\n"
    stamped = Lifecycle.stamp_reviewed(original_body)
    # Write with verified frontmatter, but tamper with body after stamping.
    tampered = String.replace(stamped, "Stable", "Tampered")
    File.write!(path, "---\nlifecycle: verified\n---\n" <> tampered)

    now = DateTime.utc_now()

    summary =
      LifecycleSweep.run(
        glob: Path.join(tmp, "kb/wiki/**/*.md"),
        now: now,
        last_seen_fn: fn _ -> now end
      )

    assert summary.drift_demoted == 1
    assert summary.by_state.reviewed == 1

    {meta, _body} = Lifecycle.parse_page(File.read!(path))
    assert Lifecycle.state_of(meta) == :reviewed
  end

  test "drift_action=warn leaves page verified but records a warning", %{tmp: tmp} do
    path = Path.join(tmp, "kb/wiki/sources/warnme.md")
    body = "# V\n\nBody.\n"
    stamped = Lifecycle.stamp_reviewed(body)
    tampered = String.replace(stamped, "Body.", "Tampered.")
    File.write!(path, "---\nlifecycle: verified\n---\n" <> tampered)

    now = DateTime.utc_now()

    summary =
      LifecycleSweep.run(
        glob: Path.join(tmp, "kb/wiki/**/*.md"),
        now: now,
        last_seen_fn: fn _ -> now end,
        config: %{"lifecycle" => %{"drift_action" => "warn"}}
      )

    assert summary.drift_warned == 1
    assert summary.drift_demoted == 0
    assert summary.by_state.verified == 1
  end

  test "archived pages are never auto-staled", %{tmp: tmp} do
    path = Path.join(tmp, "kb/wiki/concepts/archived.md")
    File.write!(path, "---\nlifecycle: archived\n---\n# Done\n")

    now = DateTime.utc_now()
    ancient = DateTime.add(now, -10_000 * 86_400)

    summary =
      LifecycleSweep.run(
        glob: Path.join(tmp, "kb/wiki/**/*.md"),
        now: now,
        last_seen_fn: fn _ -> ancient end
      )

    assert summary.auto_staled == 0
    assert summary.by_state.archived == 1
  end

  test "config-driven stale_after_days", %{tmp: tmp} do
    path = Path.join(tmp, "kb/wiki/concepts/short.md")
    File.write!(path, "---\nlifecycle: reviewed\n---\n# Short-ttl\n")

    now = ~U[2026-04-23 12:00:00Z]

    summary =
      LifecycleSweep.run(
        glob: Path.join(tmp, "kb/wiki/**/*.md"),
        now: now,
        last_seen_fn: fn _ -> DateTime.add(now, -31 * 86_400) end,
        config: %{"lifecycle" => %{"stale_after_days" => 30}}
      )

    assert summary.auto_staled == 1
  end
end
