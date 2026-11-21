defmodule Minion.Delivery.PipelineSeamTest do
  use Minion.DataCase, async: true

  alias Minion.Accounts.{Person, Team}
  alias Minion.Alerts.Processor
  alias Minion.Delivery.Delivery
  alias Minion.Rules.Rule

  setup do
    team = Repo.insert!(%Team{name: "ops-#{System.unique_integer([:positive])}"})

    anna =
      Repo.insert!(%Person{
        team_id: team.id,
        name: "Anna",
        email: "anna@minion.test",
        phone: "+48100200300",
        preferences: %{"warning" => [%{"channels" => ["email", "sms"]}]}
      })

    rule =
      Repo.insert!(%Rule{
        name: "Disk full",
        owner_type: :team,
        owner_id: team.id,
        severity: :warning,
        conditions: %{"field" => "payload.type", "op" => "eq", "value" => "DISK_FULL"},
        dedup: %{"key" => ["payload.host"]},
        present: %{"title" => "Disk full on {{payload.host}}"},
        notify: [%{"type" => "team", "id" => team.id}]
      })

    %{anna: anna, rule: rule}
  end

  defp process(rule, payload),
    do: Processor.process(Minion.Ingest.envelope("test", "http", payload), [rule])

  defp deliveries, do: Repo.all(from d in Delivery, order_by: d.channel)

  test "a new alert from the pipeline gets its deliveries and jobs", %{anna: anna, rule: rule} do
    {:ok, [{:created, alert}]} = process(rule, %{"type" => "DISK_FULL", "host" => "web-1"})

    assert [
             %Delivery{
               alert_id: alert_id,
               person_id: person_id,
               channel: :email,
               status: :pending
             },
             %Delivery{channel: :sms, status: :pending}
           ] = deliveries()

    assert alert_id == alert.id
    assert person_id == anna.id
    assert Repo.aggregate(Oban.Job, :count) == 2
  end

  test "a repeat of an open alert notifies nobody again", %{rule: rule} do
    payload = %{"type" => "DISK_FULL", "host" => "web-1"}
    {:ok, [{:created, _}]} = process(rule, payload)
    {:ok, [{:updated, %{count: 2}}]} = process(rule, payload)

    assert length(deliveries()) == 2
    assert Repo.aggregate(Oban.Job, :count) == 2
  end

  test "an event that matches no rule notifies nobody", %{rule: rule} do
    assert {:ok, []} = process(rule, %{"type" => "CPU_HIGH"})
    assert deliveries() == []
  end
end
