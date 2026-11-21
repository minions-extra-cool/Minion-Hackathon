defmodule Minion.Alerts.QuietSweepTest do
  use Minion.DataCase, async: true
  use Oban.Testing, repo: Minion.Repo

  alias Minion.Accounts.{Person, Team}
  alias Minion.Alerts.{Alert, Processor, QuietSweep, QuietSweepWorker}
  alias Minion.Rules.Rule

  defp insert_team(auto_resolve_after \\ %{}) do
    Repo.insert!(%Team{
      name: "team-#{System.unique_integer([:positive])}",
      auto_resolve_after: auto_resolve_after
    })
  end

  defp insert_rule(owner, severity, dedup \\ %{"key" => ["payload.host"], "quiet_sec" => 60}) do
    owner_type = if match?(%Team{}, owner), do: :team, else: :person

    Repo.insert!(%Rule{
      name: "Disk full",
      owner_type: owner_type,
      owner_id: owner.id,
      severity: severity,
      conditions: %{"field" => "payload.type", "op" => "eq", "value" => "DISK_FULL"},
      dedup: dedup,
      present: %{"title" => "Disk full on {{payload.host}}"},
      notify: []
    })
  end

  defp alert_for(rule, host \\ "web-1") do
    envelope = Minion.Ingest.envelope("test", "http", %{"type" => "DISK_FULL", "host" => host})
    {:ok, [{_, alert}]} = Processor.process(envelope, [rule], dispatch: fn _ -> :ok end)
    alert
  end

  defp sweep_after(alert, seconds), do: QuietSweep.run(DateTime.add(alert.last_seen, seconds))

  defp reload(alert), do: Repo.get!(Alert, alert.id)

  describe "closing the dedup window after quiet_sec" do
    test "closes a quiet alert without resolving it" do
      alert = insert_team() |> insert_rule(:warning) |> alert_for()

      assert %{closed: []} = sweep_after(alert, 59)
      assert %{closed: [%Alert{id: id}]} = sweep_after(alert, 61)

      assert id == alert.id
      assert %Alert{status: :open, closed_at: %DateTime{}} = reload(alert)
    end

    test "a new event resets the quiet period" do
      rule = insert_team() |> insert_rule(:warning)
      first = alert_for(rule)
      repeat = alert_for(rule)

      assert repeat.id == first.id
      assert %{closed: []} = sweep_after(repeat, 59)
    end

    test "the next event after closing opens a new alert, and the closed one stays open" do
      rule = insert_team() |> insert_rule(:critical)
      first = alert_for(rule)
      sweep_after(first, 61)

      second = alert_for(rule)

      refute second.id == first.id
      assert %Alert{status: :open, closed_at: nil, count: 1} = second
      assert %Alert{status: :open, count: 1} = reload(first)
    end

    test "rules without a numeric quiet_sec never close" do
      team = insert_team()
      no_quiet = team |> insert_rule(:info, %{"key" => ["payload.host"]}) |> alert_for("web-1")
      text_quiet = team |> insert_rule(:info, %{"quiet_sec" => "soon"}) |> alert_for("web-2")

      assert %{closed: []} = sweep_after(no_quiet, 1_000_000)
      assert reload(text_quiet).closed_at == nil
    end
  end

  describe "auto-resolving by team setting" do
    test "resolves info and warning alerts after the team's quiet time for that severity" do
      team = insert_team(%{"info" => 300, "warning" => 3600})
      info = team |> insert_rule(:info) |> alert_for("web-1")
      warning = team |> insert_rule(:warning) |> alert_for("web-2")

      sweep_after(info, 301)
      assert reload(info).status == :resolved
      assert reload(warning).status == :open

      sweep_after(warning, 3601)

      assert %Alert{
               status: :resolved,
               closed_at: %DateTime{},
               resolved_at: %DateTime{},
               resolved_by_id: nil
             } = reload(warning)
    end

    test "never resolves critical alerts, even if the setting names critical" do
      team = insert_team(%{"critical" => 60, "warning" => 60})
      critical = team |> insert_rule(:critical) |> alert_for()

      assert %{resolved: []} = sweep_after(critical, 1_000_000)
      assert %Alert{status: :open, closed_at: %DateTime{}} = reload(critical)
    end

    test "leaves severities the team has no setting for unresolved" do
      warning = insert_team(%{"info" => 60}) |> insert_rule(:warning) |> alert_for()

      assert %{resolved: []} = sweep_after(warning, 1_000_000)
    end

    test "resolves acknowledged alerts too" do
      alert = insert_team(%{"info" => 60}) |> insert_rule(:info) |> alert_for()
      alert |> Ecto.Changeset.change(status: :acked) |> Repo.update!()

      sweep_after(alert, 61)

      assert reload(alert).status == :resolved
    end

    test "an alert owned by a person uses that person's team setting" do
      team = insert_team(%{"info" => 60})
      anna = Repo.insert!(%Person{name: "Anna", team_id: team.id})
      loner = Repo.insert!(%Person{name: "Loner"})

      annas = anna |> insert_rule(:info) |> alert_for("web-1")
      loners = loner |> insert_rule(:info) |> alert_for("web-2")

      sweep_after(annas, 61)

      assert reload(annas).status == :resolved
      assert reload(loners).status == :open
    end
  end

  test "subscribers are told about closed and resolved alerts" do
    team = insert_team(%{"info" => 60})
    alert = team |> insert_rule(:info) |> alert_for()
    Phoenix.PubSub.subscribe(Minion.PubSub, "alerts:team:#{team.id}")

    sweep_after(alert, 61)

    assert_received {:alert, :closed, %Alert{closed_at: %DateTime{}}}
    assert_received {:alert, :resolved, %Alert{status: :resolved}}
  end

  describe "QuietSweepWorker" do
    test "the cron run schedules a second run half a minute later" do
      assert :ok = perform_job(QuietSweepWorker, %{"schedule_half_minute_run" => true})

      assert_enqueued(worker: QuietSweepWorker, args: %{})
    end

    test "the half-minute run does not schedule another" do
      assert :ok = perform_job(QuietSweepWorker, %{})

      refute_enqueued(worker: QuietSweepWorker)
    end
  end
end
