defmodule Minion.Repo.Migrations.AddIngestKeyToTeams do
  use Ecto.Migration

  def change do
    alter table(:teams) do
      add :ingest_key_hash, :binary
      add :ingest_key_hint, :string
      add :ingest_key_created_at, :utc_datetime_usec
    end

    create unique_index(:teams, [:ingest_key_hash])
  end
end
