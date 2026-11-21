import Ecto.Query

alias Minion.Accounts
alias Minion.Accounts.{Person, Team}
alias Minion.Repo
alias Minion.Rules.Rule
alias Minion.Runbooks
alias Minion.Runbooks.Runbook

defmodule Minion.Seeds do
  def team!(attrs), do: %Team{} |> Team.changeset(attrs) |> Repo.insert!()

  def person!(team, attrs),
    do: %Person{} |> Person.changeset(Map.put(attrs, :team_id, team.id)) |> Repo.insert!()

  def rule!(attrs, runbook_body) do
    rule = %Rule{} |> Rule.changeset(attrs) |> Repo.insert!()
    {:ok, _runbook} = Runbooks.save_runbook(%Runbook{rule_id: rule.id}, %{body: runbook_body})
    rule
  end
end

alias Minion.Seeds

if Repo.exists?(from t in Team, where: t.name == "Gru's Squad") do
  IO.puts("Seed data already present, skipping")
else
  gru_squad =
    Seeds.team!(%{
      name: "Gru's Squad",
      auto_resolve_after: %{"info" => 3600, "warning" => 14_400}
    })

  gru =
    Seeds.person!(gru_squad, %{
      name: "Gru",
      email: "gru@minion.test",
      phone: "+1 555 0100",
      preferences: %{
        "critical" => [
          %{"channels" => ["sms"], "hours" => [8, 20]},
          %{"channels" => ["email"]}
        ],
        "warning" => [%{"channels" => ["email"]}],
        "info" => []
      }
    })

  kevin =
    Seeds.person!(gru_squad, %{
      name: "Kevin",
      email: "kevin@minion.test",
      phone: "+1 555 0101",
      preferences: %{
        "critical" => [%{"channels" => ["phone", "sms"]}],
        "warning" => [%{"channels" => ["sms", "email"]}],
        "info" => [%{"channels" => ["email"]}]
      }
    })

  bob =
    Seeds.person!(gru_squad, %{
      name: "Bob",
      email: "bob@minion.test",
      phone: "+1 555 0102",
      preferences: %{
        "critical" => [%{"channels" => ["sms", "email"]}],
        "warning" => [%{"channels" => ["email"]}],
        "info" => []
      }
    })

  gru_squad = gru_squad |> Team.changeset(%{oncall_person_id: kevin.id}) |> Repo.update!()

  vector_industries =
    Seeds.team!(%{
      name: "Vector Industries",
      auto_resolve_after: %{"info" => 1800, "warning" => 7200}
    })

  vector =
    Seeds.person!(vector_industries, %{
      name: "Vector",
      email: "vector@minion.test",
      phone: "+1 555 0199",
      preferences: %{
        "critical" => [%{"channels" => ["phone", "sms"]}],
        "warning" => [
          %{"channels" => ["sms"], "hours" => [22, 6]},
          %{"channels" => ["email"]}
        ],
        "info" => []
      }
    })

  vector_industries =
    vector_industries |> Team.changeset(%{oncall_person_id: vector.id}) |> Repo.update!()

  Seeds.rule!(
    %{
      name: "Order settlement failed in prod",
      owner_type: :team,
      owner_id: gru_squad.id,
      severity: :critical,
      conditions: %{
        "all" => [
          %{"field" => "payload.type", "op" => "eq", "value" => "WORKFLOW_FAILED"},
          %{"field" => "payload.workflowName", "op" => "eq", "value" => "order-settlement"},
          %{"field" => "payload.environment", "op" => "eq", "value" => "prod"}
        ]
      },
      dedup: %{"key" => ["payload.workflowName", "payload.step"], "quiet_sec" => 300},
      present: %{
        "title" => "{{payload.workflowName}} failed at {{payload.step}}",
        "body" => "{{payload.error.message}}",
        "fields" => ["payload.step", "payload.error.code", "payload.workflowId"],
        "color" => "red"
      },
      notify: [
        %{"type" => "oncall", "id" => gru_squad.id, "channels" => ["phone", "sms"]},
        %{"type" => "team", "id" => gru_squad.id}
      ]
    },
    """
    runbook: settlement-timeout
    owner: Gru's Squad
    matches:
      type: WORKFLOW_FAILED
      workflow: {{payload.workflowName}}
      step: {{payload.step}}
    steps:
      - check: "Is counterparty-service healthy?"
        action: http_get https://counterparty-service.lair.internal/health
        expect: 200 and "status": "UP"
        if_not: restart counterparty-service (kubectl -n settlement rollout restart deploy/counterparty-service), wait 2 minutes, check again
      - check: "Did the counterparty answer slowly or not at all?"
        action: open the Grafana board "Settlement / Counterparty latency", filter on step {{payload.step}}
        note: p99 above 30s for 5 minutes means the counterparty is degraded, not us
      - retry: "Retry the failed workflow once the dependency is healthy"
        action: http_post https://workflow-engine.lair.internal/workflows/{{payload.workflowId}}/retry
        note: retry at most twice; a third failure means the trade data itself is bad
      - escalate: "Still failing after two retries"
        action: page Gru, and post the workflow id {{payload.workflowId}} and error code {{payload.error.code}} in #settlement-incidents
    sla: settle before 16:00 UTC cut-off; after cut-off, tell treasury the trade moves to T+1
    """
  )

  Seeds.rule!(
    %{
      name: "High error rate on payments",
      owner_type: :team,
      owner_id: gru_squad.id,
      severity: :critical,
      conditions: %{
        "all" => [
          %{"field" => "payload.alertname", "op" => "eq", "value" => "HighErrorRate"},
          %{"field" => "payload.labels.service", "op" => "matches", "value" => "payments-*"}
        ]
      },
      dedup: %{
        "key" => ["payload.labels.service", "payload.labels.region"],
        "quiet_sec" => 300
      },
      present: %{
        "title" => "High error rate on {{payload.labels.service}} ({{payload.labels.region}})",
        "body" =>
          "{{payload.annotations.summary}} Error rate {{payload.annotations.error_rate}}.",
        "fields" => ["payload.labels.service", "payload.labels.region"],
        "color" => "red"
      },
      notify: [%{"type" => "team", "id" => gru_squad.id}]
    },
    """
    # HighErrorRate on {{payload.labels.service}}

    Customers in **{{payload.labels.region}}** are failing to pay. Every minute counts: one minute of payments-api errors is roughly 400 lost banana orders.

    ## First five minutes
    1. Open the [payments dashboard](https://grafana.lair.internal/d/payments) and check whether the errors are in **one region only** or everywhere.
    2. Check the last deploy of {{payload.labels.service}} in `#deploys`. If something shipped in the last 30 minutes, roll it back first and ask questions later.
    3. Look at the top error in the logs: `kubectl -n payments logs deploy/{{payload.labels.service}} --since=10m | grep ERROR | sort | uniq -c | sort -rn | head`

    ## If it is one region
    - Fail traffic over to the other region with `./bin/failover {{payload.labels.region}}`. This **needs approval** from Gru or the on-call lead.
    - Keep the failed region drained until the error rate has been under 1% for 15 minutes.

    ## If it is every region
    - It is almost never us: check the card processor status page and the `#vendor-status` channel.
    - Switch to the backup processor with the feature flag `payments.backup_processor`.

    ## While it lasts
    - Post an update in `#payments-incidents` every 15 minutes, even if nothing changed.
    - When it is over, write down what fixed it in the resolve dialog so this runbook learns.

    > Do not restart all payments pods at once. Sessions are sticky and customers will lose their baskets.
    """
  )

  Seeds.rule!(
    %{
      name: "Disk full",
      owner_type: :team,
      owner_id: gru_squad.id,
      severity: :warning,
      conditions: %{
        "all" => [%{"field" => "payload.type", "op" => "eq", "value" => "DISK_FULL"}]
      },
      dedup: %{"key" => ["payload.host"], "quiet_sec" => 600},
      present: %{
        "title" => "Disk full on {{payload.host}}",
        "body" => "{{payload.host}} reports {{payload.used}}% disk used.",
        "fields" => ["payload.host", "payload.used"],
        "color" => "amber"
      },
      notify: [%{"type" => "team", "id" => gru_squad.id}]
    },
    """
    Checklist: disk full on {{payload.host}} ({{payload.used}}% used)

    - [ ] SSH in: `ssh {{payload.host}}.lair.internal`
    - [ ] Find what is big: `sudo du -xh / --max-depth=2 | sort -rh | head -20`
    - [ ] Old logs are the usual cause. Rotate and compress them: `sudo logrotate -f /etc/logrotate.conf`
    - [ ] Clear the package and container caches: `sudo apt-get clean && docker system prune -f`
    - [ ] If the host is a database (`db-*`), do **not** delete anything under `/var/lib/postgresql`. Call Kevin instead.
    - [ ] Check usage is under 80%: `df -h /`
    - [ ] If it fills up again within a day, open a ticket to grow the volume and link it in the resolve note.
    """
  )

  Seeds.rule!(
    %{
      name: "Banana stock low",
      owner_type: :person,
      owner_id: bob.id,
      severity: :info,
      conditions: %{
        "all" => [
          %{"field" => "payload.type", "op" => "eq", "value" => "STOCK_LOW"},
          %{"field" => "payload.item", "op" => "in", "value" => ["banana", "banana-split"]},
          %{"field" => "payload.quantity", "op" => "lt", "value" => 100}
        ]
      },
      dedup: %{"key" => ["payload.warehouse"], "quiet_sec" => 3600},
      present: %{
        "title" => "Only {{payload.quantity}} {{payload.item}}s left in {{payload.warehouse}}",
        "body" => "",
        "fields" => ["payload.warehouse", "payload.quantity"],
        "color" => "green"
      },
      notify: [%{"type" => "person", "id" => bob.id, "channels" => ["email"]}]
    },
    """
    This happens every Friday because Kevin takes the whole crate for the weekend. Before ordering anything, ask Kevin if he has the bananas from {{payload.warehouse}}. If he doesn't, order 500 from the usual supplier (Banana Bros, account BB-1138, the order form is on the wiki under Supplies > Fruit) and pick next-day delivery. Never order the green ones, nobody eats them. If the warehouse is below 20 it's an emergency, tell Gru.
    """
  )

  Seeds.rule!(
    %{
      name: "Pricing engine slow",
      owner_type: :team,
      owner_id: vector_industries.id,
      severity: :warning,
      conditions: %{
        "all" => [
          %{"field" => "source", "op" => "matches", "value" => "pricing-engine-*"},
          %{"field" => "payload.level", "op" => "in", "value" => ["WARN", "ERROR", "FATAL"]},
          %{"field" => "payload.latency_ms", "op" => "gt", "value" => 1000}
        ]
      },
      dedup: %{"key" => ["payload.instrument"], "quiet_sec" => 300},
      present: %{
        "title" => "Pricing latency {{payload.latency_ms}} ms for {{payload.instrument}}",
        "body" => "{{payload.instance}}: {{payload.message}}",
        "fields" => ["payload.instance", "payload.instrument", "payload.latency_ms"],
        "color" => "amber"
      },
      notify: [%{"type" => "team", "id" => vector_industries.id}]
    },
    """
    When pricing latency goes over a second, it's usually the cache. Restart the pricing-engine instance named in the alert ({{payload.instance}}), wait 2 minutes, and if latency is still high, call the pricing on-call person (that's me, Vector, oh yeah!). If it's only {{payload.instrument}} and nothing else, the market data feed for that instrument is probably stale; check the feed status page before restarting anything. Don't restart more than one instance at a time or the remaining ones fall over from the extra load.
    """
  )

  Seeds.rule!(
    %{
      name: "Rates trade rejected",
      owner_type: :team,
      owner_id: vector_industries.id,
      severity: :warning,
      conditions: %{
        "all" => [
          %{"field" => "payload.meta.schema", "op" => "matches", "value" => "trade.rejected.*"},
          %{"field" => "payload.trade.desk", "op" => "eq", "value" => "rates"},
          %{"field" => "payload.trade.notional", "op" => "gt", "value" => 100_000}
        ]
      },
      dedup: %{"key" => ["payload.trade.id"]},
      present: %{
        "title" => "Rejected {{payload.trade.currency}} trade {{payload.trade.id}}",
        "body" =>
          "{{payload.trade.notional}} {{payload.trade.currency}} with {{payload.trade.counterparty}}: {{payload.reason.message}}",
        "fields" => [
          "payload.trade.counterparty",
          "payload.trade.notional",
          "payload.reason.code"
        ],
        "color" => "blue"
      },
      notify: [%{"type" => "team", "id" => vector_industries.id, "channels" => ["email"]}]
    },
    """
    Full procedure: [Rates desk: rejected trades](https://wiki.vector.internal/rates/rejected-trades) (Confluence, last reviewed by Vector).

    Short version for trade {{payload.trade.id}} (reason `{{payload.reason.code}}`):
    1. `LIMIT_BREACH`: ask risk to raise the limit for {{payload.trade.counterparty}} or split the trade. Never book around the limit.
    2. `STALE_PRICE`: re-price and resubmit from the blotter; it is safe to retry once.
    3. `UNKNOWN_COUNTERPARTY`: the counterparty is missing from static data. Raise it with onboarding, the trade waits.
    4. Anything else: call the trader who booked it before the market closes.
    """
  )

  Seeds.rule!(
    %{
      name: "Shrink ray offline",
      owner_type: :team,
      owner_id: vector_industries.id,
      severity: :critical,
      conditions: %{
        "all" => [
          %{"field" => "payload.alertname", "op" => "eq", "value" => "TargetDown"},
          %{"field" => "payload.labels.job", "op" => "eq", "value" => "shrink-ray"}
        ]
      },
      dedup: %{"key" => ["payload.labels.instance"], "quiet_sec" => 600},
      present: %{
        "title" => "Shrink ray offline on {{payload.labels.instance}}",
        "body" => "{{payload.annotations.description}}",
        "fields" => ["payload.labels.instance", "payload.labels.region"],
        "color" => "red"
      },
      notify: [
        %{"type" => "oncall", "id" => vector_industries.id, "channels" => ["phone", "sms"]}
      ]
    },
    """
    # Shrink ray offline

    The shrink ray on **{{payload.labels.instance}}** stopped answering health checks. Until it is back, the vault is unguarded.

    ## Check
    1. Is the power on? Look at the lab power panel for {{payload.labels.instance}}. A tripped breaker is the cause 8 times out of 10.
    2. Is the controller alive? `curl -s http://{{payload.labels.instance}}:9100/health`
    3. Did someone "borrow" it? Check the vault camera feed. If the ray is physically gone, this is a security incident: lock the vault (`./bin/vault lockdown`) and stop here.

    ## Fix
    - Breaker tripped: reset it once. If it trips again, the capacitor is failing; do not reset a third time.
    - Controller hung: `sudo systemctl restart shrink-ray-controller` on the instance, then wait for the green light (about 90 seconds).
    - After it is back, fire one calibration shot at the test pyramid before trusting it.

    ---
    Escalation: Vector, always. There is nobody else.
    """
  )

  IO.puts("""
  Seeded Gru's Squad (#{gru.name}, #{kevin.name} on call, #{bob.name}) and Vector Industries (#{vector.name} on call)
  with 7 rules, each with a runbook
  """)
end

dev_ingest_keys = [
  {"Gru's Squad", System.get_env("MINION_INGEST_KEY", "minion-dev-gru-key"), "MINION_INGEST_KEY"},
  {"Vector Industries", System.get_env("MINION_VECTOR_INGEST_KEY", "minion-dev-vector-key"),
   "MINION_VECTOR_INGEST_KEY"}
]

for {team_name, key, env_var} <- dev_ingest_keys do
  case Repo.get_by(Team, name: team_name) do
    %Team{ingest_key_hash: nil} = team ->
      {:ok, _} = Accounts.put_ingest_key(team, key)
      IO.puts("#{team_name} posts to /ingest with the key #{key} (#{env_var})")

    _ ->
      :ok
  end
end
