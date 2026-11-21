defmodule Minion.Repo.Migrations.AddAlertClosingAndTeamAutoResolve do
  use Ecto.Migration

  def change do
    alter table(:alerts) do
      add :closed_at, :utc_datetime_usec
    end

    alter table(:teams) do
      add :auto_resolve_after, :map, null: false, default: %{}
    end

    drop unique_index(:alerts, [:fingerprint],
           where: "status <> 'resolved'",
           name: :alerts_unresolved_fingerprint_index
         )

    create unique_index(:alerts, [:fingerprint],
             where: "status <> 'resolved' AND closed_at IS NULL",
             name: :alerts_active_fingerprint_index
           )
  end
end
