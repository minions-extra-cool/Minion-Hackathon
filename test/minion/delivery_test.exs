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
      team = insert_team()
      insert_person(team, "Anna")
      rule = insert_rule(team)

      Repo.transaction(fn ->
        Dispatch.dispatch(insert_alert(rule), ~U[2026-11-20 10:00:00Z])

        assert Repo.aggregate(Delivery, :count) == 1
        assert Repo.aggregate(Oban.Job, :count) == 1

        Repo.rollback(:boom)
      end)

      assert Repo.aggregate(Delivery, :count) == 0
      assert Repo.aggregate(Oban.Job, :count) == 0
    end

    test "inserts one pending delivery and one job per person and channel" do
      team = insert_team()
      anna = insert_person(team, "Anna")
      piotr = insert_person(team, "Piotr", %{"warning" => [%{"channels" => ["email", "sms"]}]})
      rule = insert_rule(team)

      Dispatch.dispatch(insert_alert(rule), ~U[2026-11-20 10:00:00Z])

      deliveries =
        Repo.all(from d in Delivery, select: {d.person_id, d.channel, d.status, d.id})

      assert deliveries
             |> Enum.map(fn {person, channel, status, _id} -> {person, channel, status} end)
             |> Enum.sort() ==
               Enum.sort([
                 {anna.id, :email, :pending},
                 {piotr.id, :email, :pending},
                 {piotr.id, :sms, :pending}
               ])

      jobs = Repo.all(Oban.Job)

      assert jobs |> Enum.map(&{&1.args["delivery_id"], &1.queue}) |> Enum.sort() ==
               deliveries
               |> Enum.map(fn {_, channel, _, id} -> {id, to_string(channel)} end)
               |> Enum.sort()

      assert Enum.all?(jobs, &(&1.worker == "Minion.Delivery.Worker"))
    end

    test "resolves oncall to the team's oncall person" do
      team = insert_team()
      oncall = insert_person(team, "Piotr")
      other = insert_person(team, "Anna")

      team =
        team
        |> Team.changeset(%{oncall_person_id: oncall.id})
        |> Repo.update!()

      rule = insert_rule(team, notify: [%{"type" => "oncall", "id" => team.id}])

      Dispatch.dispatch(insert_alert(rule), ~U[2026-11-20 10:00:00Z])

      assert [oncall.id] == delivered_person_ids()
      refute other.id in delivered_person_ids()
    end

    test "skips notify entries that point at missing records" do
      team = insert_team()

      rule =
        insert_rule(team,
          notify: [
            %{"type" => "oncall", "id" => Ecto.UUID.generate()},
            %{"type" => "person", "id" => Ecto.UUID.generate()},
            %{"type" => "team", "id" => Ecto.UUID.generate()},
            %{"type" => "bogus", "id" => Ecto.UUID.generate()}
          ]
        )

      assert :ok == Dispatch.dispatch(insert_alert(rule), ~U[2026-11-20 10:00:00Z])
      assert [] == delivered_person_ids()
    end

    test "notifies a person once when named twice" do
      team = insert_team()
      person = insert_person(team, "Anna")

      rule =
        insert_rule(team,
          notify: [
            %{"type" => "team", "id" => team.id},
            %{"type" => "person", "id" => person.id}
          ]
        )

      Dispatch.dispatch(insert_alert(rule), ~U[2026-11-20 10:00:00Z])

      assert [person.id] == delivered_person_ids()
    end
  end

  defp delivered_person_ids do
    Repo.all(from d in Delivery, select: d.person_id, order_by: d.id)
  end

  defp insert_team do
    Repo.insert!(%Team{name: "ops-#{Ecto.UUID.generate()}"})
  end

  defp insert_person(team, name, preferences \\ %{"warning" => [%{"channels" => ["email"]}]}) do
    Repo.insert!(%Person{
      team_id: team.id,
      name: name,
      email: "#{String.downcase(name)}@minion.test",
      phone: "+48100200300",
      preferences: preferences
    })
  end

  defp insert_rule(team, opts \\ []) do
    notify = Keyword.get(opts, :notify, [%{"type" => "team", "id" => team.id}])

    Repo.insert!(%Rule{
      name: "Disk full",
      owner_type: :team,
      owner_id: team.id,
      severity: :warning,
      conditions: %{},
      notify: notify
    })
  end

  defp insert_alert(rule, severity \\ :warning) do
    Repo.insert!(%Alert{
      rule_id: rule.id,
      owner_type: :team,
      owner_id: rule.owner_id,
      fingerprint: Ecto.UUID.generate(),
      severity: severity,
      first_seen: DateTime.utc_now(),
      last_seen: DateTime.utc_now(),
      title: "Disk full on web-1",
      sample_event: %{}
    })
  end
end
