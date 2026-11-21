defmodule Minion.Rules.CacheTest do
  use Minion.DataCase

  alias Minion.Rules.{Cache, Rule}

  defp insert_rule(name, enabled) do
    Repo.insert!(%Rule{
      name: name,
      enabled: enabled,
      owner_type: :team,
      owner_id: Ecto.UUID.generate(),
      severity: :info,
      conditions: %{"field" => "source", "op" => "exists"},
      notify: []
    })
  end

  test "holds the enabled rules and picks up changes on reload" do
    insert_rule("enabled", true)
    insert_rule("disabled", false)
    start_supervised!(Cache)

    assert Enum.map(Cache.all(), & &1.name) == ["enabled"]

    insert_rule("added later", true)
    Cache.reload()

    assert Cache.all() |> Enum.map(& &1.name) |> Enum.sort() == ["added later", "enabled"]
  end

  test "reloads as soon as a rule is saved, without waiting for the timer" do
    rule = insert_rule("will be disabled", true)
    start_supervised!(Cache)
    assert Enum.map(Cache.all(), & &1.name) == ["will be disabled"]

    {:ok, _} = Minion.Rules.set_enabled(rule, false)
    :sys.get_state(Cache)

    assert Cache.all() == []
  end
end
