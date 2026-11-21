defmodule Minion.Delivery.WorkerExitTest do
  use Minion.DataCase, async: false
  use Oban.Testing, repo: Minion.Repo

  alias Minion.Accounts.{Person, Team}
  alias Minion.Alerts.Alert
  alias Minion.Delivery.{Delivery, Worker}
  alias Minion.Rules.Rule

  defmodule ExitingAdapter do
    use Swoosh.Adapter

    def deliver(_email, _config), do: exit(:mail_storage_not_started)
  end

  setup do
    original = Application.get_env(:minion, Minion.Mailer)
    Application.put_env(:minion, Minion.Mailer, adapter: ExitingAdapter)
    on_exit(fn -> Application.put_env(:minion, Minion.Mailer, original) end)

    team = Repo.insert!(%Team{name: "ops-#{Ecto.UUID.generate()}"})
    person = Repo.insert!(%Person{team_id: team.id, name: "Anna", email: "anna@minion.test"})

    rule =
      Repo.insert!(%Rule{
        name: "Disk full",
        owner_type: :team,
        owner_id: team.id,
        severity: :warning,
        conditions: %{},
        notify: []
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
        sample_event: %{}
      })

    %{
      delivery: Repo.insert!(%Delivery{alert_id: alert.id, person_id: person.id, channel: :email})
    }
  end

  test "a channel that exits is recorded and retried, like any other failure", %{
    delivery: delivery
  } do
    assert {:error, {:exit, :mail_storage_not_started}} =
             perform_job(Worker, %{"delivery_id" => delivery.id}, attempt: 1)

    assert %Delivery{status: :pending, attempts: 1, last_error: error} =
             Repo.get!(Delivery, delivery.id)

    assert error =~ "mail_storage_not_started"
  end

  test "on the last attempt an exiting channel marks the delivery failed", %{delivery: delivery} do
    assert {:cancel, {:exit, :mail_storage_not_started}} =
             perform_job(Worker, %{"delivery_id" => delivery.id}, attempt: 4)

    assert %Delivery{status: :failed} = Repo.get!(Delivery, delivery.id)
  end
end
