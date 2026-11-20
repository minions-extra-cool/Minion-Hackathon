defmodule Minion.DeliveryTest do
  use Minion.DataCase

  import Ecto.Query

  alias Minion.Accounts.{Person, Team}
  alias Minion.Alerts.Alert
  alias Minion.Delivery.Delivery
  alias Minion.Repo
  alias Minion.Rules.Rule

  alias Minion.Delivery, as: Dispatch

  describe "dispatch/2" do
    test "writes no deliveries and no jobs when the surrounding transaction rolls back" do
      rule = insert_rule()
      alert = build_alert(rule)

      Repo.transaction(fn ->
        alert = Repo.insert!(alert)
        Dispatch.dispatch(alert)
        Repo.rollback(:boom)
      end)

      assert Repo.aggregate(Delivery, :count) == 0
      assert Repo.aggregate(Oban.Job, :count) == 0
    end

    test "inserts one delivery and one job per person and channel" do
      rule = insert_rule()
      alert = Repo.insert!(build_alert(rule))

      Dispatch.dispatch(alert, ~U[2026-11-20 10:00:00Z])

      deliveries = Repo.all(from d in Delivery, preload: [:person])
      jobs = Repo.all(Oban.Job)

      assert length(deliveries) == length(jobs)
      assert Enum.all?(deliveries, &(&1.status == :pending))
      assert Enum.all?(jobs, &(&1.worker == Minion.Delivery.Worker))
    end
  end

  defp insert_rule do
    team = Repo.insert!(%Team{name: "ops-#{Ecto.UUID.generate()}"})
    Repo.insert!(%Person{team_id: team.id, name: "Anna", preferences: %{}})

    Repo.insert!(%Rule{
      name: "Disk full",
      owner_type: :team,
      owner_id: team.id,
      severity: :warning,
      conditions: %{},
      notify: [%{"type" => "team", "id" => team.id}]
    })
  end

  defp build_alert(rule) do
    %Alert{
      rule_id: rule.id,
      owner_type: :team,
      owner_id: rule.owner_id,
      fingerprint: Ecto.UUID.generate(),
      severity: :warning,
      first_seen: DateTime.utc_now(),
      last_seen: DateTime.utc_now(),
      title: "Disk full on web-1",
      sample_event: %{}
    }
  end
end
