defmodule Kb.Watch.HookTest do
  use ExUnit.Case, async: false

  setup do
    tmp = Path.join(System.tmp_dir!(), "kb-hook-#{System.unique_integer([:positive])}")
    File.mkdir_p!(tmp)
    path = Path.join(tmp, "settings.json")
    on_exit(fn -> File.rm_rf!(tmp) end)
    {:ok, path: path}
  end

  test "installs into a missing settings file", %{path: path} do
    assert {:ok, :installed} = Kb.Watch.Hook.install(settings_path: path)
    assert File.exists?(path)

    data = Jason.decode!(File.read!(path))
    entries = get_in(data, ["hooks", "SessionStart"])
    assert is_list(entries)
    assert length(entries) == 1
    assert hd(hd(entries)["hooks"])["command"] == "kb ingest --sessions"
  end

  test "is idempotent — running twice does not duplicate entries", %{path: path} do
    {:ok, :installed} = Kb.Watch.Hook.install(settings_path: path)
    {:ok, :already_present} = Kb.Watch.Hook.install(settings_path: path)
    {:ok, :already_present} = Kb.Watch.Hook.install(settings_path: path)

    data = Jason.decode!(File.read!(path))
    entries = get_in(data, ["hooks", "SessionStart"])
    assert length(entries) == 1
  end

  test "backs up the existing file once before writing", %{path: path} do
    File.write!(path, Jason.encode!(%{"existing" => true}))

    {:ok, :installed} = Kb.Watch.Hook.install(settings_path: path)
    assert File.exists?(path <> ".bak")
    assert Jason.decode!(File.read!(path <> ".bak")) == %{"existing" => true}

    # Second run must not overwrite the original backup with current state.
    File.write!(path <> ".bak.sentinel", "x")
    {:ok, :already_present} = Kb.Watch.Hook.install(settings_path: path)
    assert Jason.decode!(File.read!(path <> ".bak")) == %{"existing" => true}
  end

  test "preserves unrelated settings keys", %{path: path} do
    File.write!(path, Jason.encode!(%{"theme" => "dark", "model" => "opus"}))
    {:ok, :installed} = Kb.Watch.Hook.install(settings_path: path)

    data = Jason.decode!(File.read!(path))
    assert data["theme"] == "dark"
    assert data["model"] == "opus"
    assert get_in(data, ["hooks", "SessionStart"]) |> length() == 1
  end
end
