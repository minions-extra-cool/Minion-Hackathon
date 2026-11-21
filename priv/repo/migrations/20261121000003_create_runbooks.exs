defmodule Minion.Repo.Migrations.CreateRunbooks do
  use Ecto.Migration

  def change do
    create table(:runbooks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :rule_id, references(:rules, type: :binary_id, on_delete: :delete_all), null: false
      add :body, :text, null: false, default: ""
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:runbooks, [:rule_id])
  end
end
