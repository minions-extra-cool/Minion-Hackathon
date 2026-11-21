import Ecto.Query

alias Minion.Accounts.{Person, Team}
alias Minion.Repo
alias Minion.Rules.Rule

if Repo.exists?(from t in Team, where: t.name == "ops") do
  IO.puts("Seed data already present, skipping")
else
  ops =
    Repo.insert!(%Team{name: "ops", auto_resolve_after: %{"info" => 3600, "warning" => 14_400}})

  anna =
    Repo.insert!(%Person{
      team_id: ops.id,
      name: "Anna",
      email: "anna@minion.test",
      phone: "+48100200300",
      preferences: %{
        "critical" => [
          %{"channels" => ["sms"], "hours" => [8, 20]},
          %{"channels" => ["email"]}
        ],
        "warning" => [%{"channels" => ["email"]}],
        "info" => []
      }
    })

  piotr =
    Repo.insert!(%Person{
      team_id: ops.id,
      name: "Piotr",
      email: "piotr@minion.test",
      phone: "+48400500600",
      preferences: %{
        "critical" => [%{"channels" => ["phone", "sms"]}],
        "warning" => [%{"channels" => ["email"]}],
        "info" => []
      }
    })

  ops |> Team.changeset(%{oncall_person_id: piotr.id}) |> Repo.update!()

  Repo.insert!(%Rule{
    name: "Disk full",
    owner_type: :team,
    owner_id: ops.id,
    severity: :warning,
    conditions: %{"field" => "payload.type", "op" => "eq", "value" => "DISK_FULL"},
    dedup: %{"key" => ["payload.host"], "quiet_sec" => 600},
    present: %{
      "title" => "Disk full on {{payload.host}}",
      "body" => "{{payload.host}} reported a full disk.",
      "fields" => ["payload.host"],
      "color" => "amber"
    },
    notify: [%{"type" => "team", "id" => ops.id}]
  })

  IO.puts(
    "Seeded team ops (#{ops.id}) with #{anna.name} and #{piotr.name}, and the Disk full rule"
  )
end

dev_ingest_key = System.get_env("MINION_INGEST_KEY", "minion-dev-ops-key")

case Repo.get_by(Team, name: "ops") do
  %Team{ingest_key_hash: nil} = ops ->
    {:ok, _} = Minion.Accounts.put_ingest_key(ops, dev_ingest_key)
    IO.puts("Team ops posts to /ingest with the key #{dev_ingest_key} (MINION_INGEST_KEY)")

  _ ->
    :ok
end
