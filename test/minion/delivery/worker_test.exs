defmodule Minion.Delivery.WorkerTest do
  use Minion.DataCase

  alias Minion.Accounts.{Person, Team}
  alias Minion.Alerts.Alert
  alias Minion.Delivery.Delivery
  alias Minion.Delivery.Worker
  alias Minion.Repo
  alias Minion.Rules.Rule

  describe "perform/1" do
    test "marks the delivery delivered and counts the attempt" do
      %{delivery: delivery} = fixture(:email)

      Worker.perform(%Oban.Job{args: %{"delivery_id" => delivery.id}})

      delivery = Repo.get(Delivery, delivery.id)
      assert delivery.status == :delivered
      assert delivery.attempts == 1
      assert delivery.last_error == nil
    end

    test "records the error and marks the delivery failed" do
      %{delivery: delivery} = fixture(:sms)

      Worker.perform(%Oban.Job{args: %{"delivery_id" => delivery.id}})

      delivery = Repo.get(Delivery, delivery.id)
      assert delivery.status == :failed
      assert delivery.attempts == 1
      assert delivery.last_error == "not_implemented"
    end
  end

  defp fixture(channel) do
    team = Repo.insert!(%Team{name: "ops-#{Ecto.UUID.generate()}"})
    person = Repo.insert!(%Person{team_id: team.id, name: "Anna", email: "anna@minion.test"})

    rule =
      Repo.insert!(%Rule{
        name: "Disk full",
        owner_type: :team,
        owner_id: team.id,
        severity: :warning,
        conditions: %{},
        notify: [%{"type" => "team", "id" => team.id}]
      })

    alert =
      Repo.insert!(%Alert{
        rule_id: rule.id,
        owner_type: :team,
        owner_id: team.id,
        fingerprint: Ecto.UUID.generate(),
        severity: :warning,
        first_seen: DateTime.utc_now(),
        last_seen: DateTime.utc_now(),
        title: "Disk full on web-1",
        body: "web-1 reported a full disk.",
        sample_event: %{}
      })

    delivery =
      Repo.insert!(%Delivery{
        alert_id: alert.id,
        person_id: person.id,
        channel: channel
      })

    %{delivery: delivery, alert: alert, person: person}
  end
end
