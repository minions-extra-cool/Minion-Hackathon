defmodule Minion.Repo.Migrations.CreateCoreTables do
  use Ecto.Migration

  def change do
    create table(:teams, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:teams, [:name])

    create table(:people, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :team_id, references(:teams, type: :binary_id, on_delete: :nilify_all)
      add :name, :string, null: false
      add :email, :string
      add :phone, :string
      add :preferences, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create index(:people, [:team_id])

    alter table(:teams) do
      add :oncall_person_id, references(:people, type: :binary_id, on_delete: :nilify_all)
    end

    create table(:rules, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :owner_type, :string, null: false
      add :owner_id, :binary_id, null: false
      add :enabled, :boolean, null: false, default: true
      add :severity, :string, null: false
      add :conditions, :map, null: false
      add :dedup, :map, null: false, default: %{}
      add :present, :map, null: false, default: %{}
      add :notify, :map, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:rules, [:owner_type, :owner_id])

    create table(:alerts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :rule_id, references(:rules, type: :binary_id, on_delete: :nilify_all)
      add :owner_type, :string, null: false
      add :owner_id, :binary_id, null: false
      add :fingerprint, :string, null: false
      add :status, :string, null: false, default: "open"
      add :severity, :string, null: false
      add :count, :integer, null: false, default: 1
      add :first_seen, :utc_datetime_usec, null: false
      add :last_seen, :utc_datetime_usec, null: false
      add :title, :text, null: false
      add :body, :text
      add :sample_event, :map, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:alerts, [:fingerprint],
             where: "status <> 'resolved'",
             name: :alerts_unresolved_fingerprint_index
           )

    create index(:alerts, [:owner_type, :owner_id, :status])
    create index(:alerts, [:last_seen], where: "status <> 'resolved'")

    create table(:deliveries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :alert_id, references(:alerts, type: :binary_id, on_delete: :delete_all), null: false
      add :person_id, references(:people, type: :binary_id, on_delete: :delete_all), null: false
      add :channel, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :attempts, :integer, null: false, default: 0
      add :last_error, :text
      timestamps(type: :utc_datetime_usec)
    end

    create index(:deliveries, [:alert_id])
  end
end
