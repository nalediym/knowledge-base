defmodule Kb.VaultTest do
  use ExUnit.Case, async: false

  @tmp_root System.tmp_dir!() |> Path.join("kb_vault_test")

  setup do
    File.rm_rf!(@tmp_root)
    File.mkdir_p!(@tmp_root)
    on_exit(fn -> File.rm_rf!(@tmp_root) end)
    {:ok, tmp: @tmp_root}
  end

  test "detects vault at cwd", %{tmp: tmp} do
    File.mkdir_p!(Path.join(tmp, ".obsidian"))
    assert {:ok, found} = Kb.Vault.find_vault_root(tmp)
    assert Path.expand(found) == Path.expand(tmp)
  end

  test "detects vault above cwd (nested path)", %{tmp: tmp} do
    File.mkdir_p!(Path.join(tmp, ".obsidian"))
    nested = Path.join([tmp, "notes", "project", "src"])
    File.mkdir_p!(nested)

    assert {:ok, found} = Kb.Vault.find_vault_root(nested)
    assert Path.expand(found) == Path.expand(tmp)
  end

  test "returns :not_found when no .obsidian exists", %{tmp: tmp} do
    nested = Path.join(tmp, "deep/dir/here")
    File.mkdir_p!(nested)

    # Ensure HOME boundary doesn't silently return a vault from the user's
    # actual home directory — point HOME at our tmp to isolate the walk.
    original_home = System.get_env("HOME")
    System.put_env("HOME", tmp)

    try do
      assert :not_found = Kb.Vault.find_vault_root(nested)
    after
      if original_home, do: System.put_env("HOME", original_home)
    end
  end

  test "stops walking at filesystem root without crashing" do
    # /tmp or /var will never contain .obsidian in test environments.
    # We just need to ensure the traversal terminates.
    start = System.tmp_dir!() |> Path.join("definitely-no-vault-#{System.unique_integer([:positive])}")
    File.mkdir_p!(start)

    original_home = System.get_env("HOME")
    System.put_env("HOME", start)

    try do
      assert :not_found = Kb.Vault.find_vault_root(start)
    after
      File.rm_rf!(start)
      if original_home, do: System.put_env("HOME", original_home)
    end
  end
end
