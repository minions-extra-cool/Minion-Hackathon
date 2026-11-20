defmodule Minion.Alerts.AutoResolveTest do
  use Minion.DataCase, async: true
  use Oban.Testing, repo: Minion.Repo

  alias Minion.Alerts.{Alert, AutoResolve, AutoResolveWorker, Processor}
  alias Minion.Rules.Rule

  defp insert_rule(dedup) do
    Repo.insert!(%Rule{
      name: "Disk full",
      owner_type: :team,
      owner_id: Ecto.UUID.generate(),
      severity: :warning,
      conditions: %{"field" => "payload.type", "op" => "eq", "value" => "DISK_FULL"},
      dedup: dedup,
      present: %{"title" => "Disk full on {{payload.host}}"},
      notify: []
    })
  end

  defp open_alert(rule, host) do
    envelope = Minion.Ingest.envelope("test", "http", %{"type" => "DISK_FULL", "host" => host})
    {:ok, [{_, alert}]} = Processor.process(envelope, [rule], dispatch: fn _ -> :ok end)
    alert
  end

  defp seconds_after(alert, seconds), do: DateTime.add(alert.last_seen, seconds)

  defp status(alert), do: Repo.get!(Alert, alert.id).status

  test "resolves an alert once it has been quiet for quiet_sec" do
    rule = insert_rule(%{"key" => ["payload.host"], "quiet_sec" => 600})
    alert = open_alert(rule, "web-1")

    assert AutoResolve.run(seconds_after(alert, 599)) == []
    assert status(alert) == :open

    assert [%Alert{id: id, status: :resolved}] = AutoResolve.run(seconds_after(alert, 601))
    assert id == alert.id
    assert status(alert) == :resolved
  end

  test "resolves acknowledged alerts too" do
    rule = insert_rule(%{"key" => ["payload.host"], "quiet_sec" => 60})
    alert = open_alert(rule, "web-1")
    alert |> Ecto.Changeset.change(status: :acked) |> Repo.update!()

    AutoResolve.run(seconds_after(alert, 61))

    assert status(alert) == :resolved
  end

  test "a new event resets the quiet period" do
    rule = insert_rule(%{"key" => ["payload.host"], "quiet_sec" => 60})
    alert = open_alert(rule, "web-1")
    repeat = open_alert(rule, "web-1")

    assert repeat.id == alert.id
    assert AutoResolve.run(DateTime.add(repeat.last_seen, 59)) == []
  end

  test "the next event after an auto-resolve opens a new alert" do
    rule = insert_rule(%{"key" => ["payload.host"], "quiet_sec" => 60})
    first = open_alert(rule, "web-1")

    AutoResolve.run(seconds_after(first, 61))
    second = open_alert(rule, "web-1")

    refute second.id == first.id
    assert second.status == :open
  end

  test "rules without a numeric quiet_sec never auto-resolve" do
    no_quiet = open_alert(insert_rule(%{"key" => ["payload.host"]}), "web-1")
    text_quiet = open_alert(insert_rule(%{"quiet_sec" => "soon"}), "web-2")

    assert AutoResolve.run(seconds_after(no_quiet, 1_000_000)) == []
    assert status(no_quiet) == :open
    assert status(text_quiet) == :open
  end

  test "subscribers are told about resolved alerts" do
    rule = insert_rule(%{"key" => ["payload.host"], "quiet_sec" => 60})
    alert = open_alert(rule, "web-1")
    Phoenix.PubSub.subscribe(Minion.PubSub, "alerts:team:#{rule.owner_id}")

    AutoResolve.run(seconds_after(alert, 61))

    assert_received {:alert, :resolved, %Alert{status: :resolved}}
  end

  describe "AutoResolveWorker" do
    test "the cron run schedules a second run half a minute later" do
      assert :ok = perform_job(AutoResolveWorker, %{"schedule_half_minute_run" => true})

      assert_enqueued(worker: AutoResolveWorker, args: %{})
    end

    test "the half-minute run does not schedule another" do
      assert :ok = perform_job(AutoResolveWorker, %{})

      refute_enqueued(worker: AutoResolveWorker)
    end
  end
end
