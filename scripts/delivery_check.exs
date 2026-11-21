import Ecto.Query

alias Minion.Accounts.Team
alias Minion.Alerts.Alert
alias Minion.Repo
alias Minion.Rules.Rule

severity = String.to_existing_atom(List.first(System.argv()) || "critical")
ops = Repo.one!(from t in Team, where: t.name == "ops")
rule = Repo.one!(from r in Rule, where: r.owner_id == ^ops.id, limit: 1)
now = DateTime.utc_now()
title = "Delivery check #{Calendar.strftime(now, "%H:%M:%S")}"

{:ok, alert} =
  Repo.transaction(fn ->
    alert =
      Repo.insert!(%Alert{
        rule_id: rule.id,
        owner_type: :team,
        owner_id: ops.id,
        fingerprint: Ecto.UUID.generate(),
        severity: severity,
        first_seen: now,
        last_seen: now,
        title: title,
        body: "Created by scripts/delivery_check.exs",
        sample_event: %{}
      })

    :ok = Minion.Delivery.dispatch(alert)
    alert
  end)

deliveries = Repo.all(from d in Minion.Delivery.Delivery, where: d.alert_id == ^alert.id, preload: :person)

IO.puts("Created #{severity} alert \"#{title}\" for team ops with #{length(deliveries)} deliveries:")
Enum.each(deliveries, &IO.puts("  #{&1.person.name} by #{&1.channel}"))
IO.puts("Watch them arrive at http://localhost:4000/gateway and http://localhost:8025")
