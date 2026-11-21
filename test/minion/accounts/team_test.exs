defmodule Minion.Accounts.TeamTest do
  use ExUnit.Case, async: true

  alias Minion.Accounts.Team

  defp changeset(auto_resolve_after),
    do: Team.changeset(%Team{}, %{name: "ops", auto_resolve_after: auto_resolve_after})

  test "accepts quiet times in seconds for info and warning" do
    assert changeset(%{"info" => 3600, "warning" => 14_400}).valid?
  end

  test "rejects an auto-resolve time for critical alerts" do
    assert {"critical alerts never auto-resolve", _} =
             changeset(%{"critical" => 60}).errors[:auto_resolve_after]
  end

  test "rejects unknown severities and non-positive or non-integer times" do
    refute changeset(%{"urgent" => 60}).valid?
    refute changeset(%{"info" => 0}).valid?
    refute changeset(%{"info" => "an hour"}).valid?
  end
end
