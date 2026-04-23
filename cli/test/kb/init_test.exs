defmodule Kb.InitTest do
  use ExUnit.Case, async: false

  setup do
    tmp = System.tmp_dir!() |> Path.join("kb_init_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    on_exit(fn -> File.rm_rf!(tmp) end)

    # Isolate HOME so vault walks don't escape into the real user home.
    original_home = System.get_env("HOME")
    System.put_env("HOME", tmp)
    on_exit(fn -> if original_home, do: System.put_env("HOME", original_home) end)

    {:ok, tmp: tmp}
  end

  test "places kb/ at project root when no vault is found", %{tmp: tmp} do
    project = Path.join(tmp, "plainproj")
    File.mkdir_p!(project)

    capture_run(fn -> Kb.Init.run(project, yes: true) end)

    assert File.dir?(Path.join(project, "kb"))
    assert File.exists?(Path.join(project, "kb/.kb-manifest.json"))

    config = Path.join(project, "kb.config.json") |> File.read!() |> Jason.decode!()
    refute Map.has_key?(config, "in_vault")
    refute Map.has_key?(config, "vault_path")
  end

  test "places kb/ inside detected vault when --yes", %{tmp: tmp} do
    vault = Path.join(tmp, "my-vault")
    File.mkdir_p!(Path.join(vault, ".obsidian"))

    project = Path.join([vault, "notes", "work"])
    File.mkdir_p!(project)

    capture_run(fn -> Kb.Init.run(project, yes: true) end)

    assert File.dir?(Path.join(vault, "kb"))
    assert File.exists?(Path.join(vault, "kb/.kb-manifest.json"))

    config = Path.join(vault, "kb.config.json") |> File.read!() |> Jason.decode!()
    assert config["in_vault"] == true
    assert Path.expand(config["vault_path"]) == Path.expand(vault)
  end

  test "--no-vault skips vault detection even when vault exists", %{tmp: tmp} do
    vault = Path.join(tmp, "vault2")
    File.mkdir_p!(Path.join(vault, ".obsidian"))

    project = Path.join(vault, "code")
    File.mkdir_p!(project)

    capture_run(fn -> Kb.Init.run(project, yes: true, no_vault: true) end)

    assert File.dir?(Path.join(project, "kb"))
    refute File.dir?(Path.join(vault, "kb"))

    config = Path.join(project, "kb.config.json") |> File.read!() |> Jason.decode!()
    refute Map.get(config, "in_vault", false)
  end

  test "declining the prompt falls back to cwd kb/", %{tmp: tmp} do
    vault = Path.join(tmp, "vault3")
    File.mkdir_p!(Path.join(vault, ".obsidian"))

    project = Path.join(vault, "here")
    File.mkdir_p!(project)

    capture_run(fn ->
      Kb.Init.run(project, prompt: fn _ -> "n\n" end)
    end)

    assert File.dir?(Path.join(project, "kb"))
    refute File.dir?(Path.join(vault, "kb"))
  end

  test "existing .kb-manifest.json outside vaults still works", %{tmp: tmp} do
    project = Path.join(tmp, "legacy")
    File.mkdir_p!(Path.join(project, "kb"))
    manifest = Kb.Manifest.new("legacy")
    File.write!(
      Path.join(project, "kb/.kb-manifest.json"),
      Jason.encode!(manifest, pretty: true) <> "\n"
    )

    # Running init again should not crash and should not invent a vault.
    capture_run(fn -> Kb.Init.run(project, yes: true) end)

    assert File.exists?(Path.join(project, "kb/.kb-manifest.json"))
    assert File.dir?(Path.join(project, "kb"))
  end

  defp capture_run(fun) do
    ExUnit.CaptureIO.capture_io(:stderr, fn ->
      ExUnit.CaptureIO.capture_io(fun)
    end)
  end
end
