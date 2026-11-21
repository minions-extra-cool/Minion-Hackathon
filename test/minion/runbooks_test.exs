defmodule Minion.RunbooksTest do
  use Minion.DataCase, async: true

  import Minion.AlertFixtures

  alias Minion.Runbooks
  alias Minion.Runbooks.Runbook

  setup do
    %{rule: rule_fixture(team_fixture())}
  end

  test "a rule starts without a runbook", %{rule: rule} do
    assert Runbooks.get_for_rule(rule.id) == nil
    assert %Runbook{rule_id: rule_id, id: nil} = Runbooks.get_or_build_for_rule(rule.id)
    assert rule_id == rule.id
  end

  test "saving creates the runbook once, then updates it", %{rule: rule} do
    {:ok, created} =
      rule.id |> Runbooks.get_or_build_for_rule() |> Runbooks.save_runbook(%{body: "Step 1"})

    {:ok, updated} =
      rule.id |> Runbooks.get_or_build_for_rule() |> Runbooks.save_runbook(%{body: "Step 2"})

    assert updated.id == created.id
    assert Runbooks.get_for_rule(rule.id).body == "Step 2"
  end

  test "a rule has at most one runbook", %{rule: rule} do
    {:ok, _} = Runbooks.save_runbook(%Runbook{rule_id: rule.id}, %{body: "first"})

    assert {:error, changeset} = Runbooks.save_runbook(%Runbook{rule_id: rule.id}, %{body: "x"})
    assert %{rule_id: ["has already been taken"]} = errors_on(changeset)
  end

  test "rendering fills placeholders from the event", %{rule: rule} do
    runbook = %Runbook{rule_id: rule.id, body: "Restart {{payload.host}}, then {{payload.nope}}."}
    event = %{"payload" => %{"host" => "web-1"}}

    assert Runbooks.render(runbook, event) == "Restart web-1, then ."
  end

  test "blank runbooks are treated as missing" do
    assert Runbooks.blank?(nil)
    assert Runbooks.blank?(%Runbook{body: "  \n"})
    refute Runbooks.blank?(%Runbook{body: "Check the disk"})
  end
end
