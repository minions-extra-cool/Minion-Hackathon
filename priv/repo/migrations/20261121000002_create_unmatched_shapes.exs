defmodule Minion.Repo.Migrations.CreateUnmatchedShapes do
  use Ecto.Migration

  def change do
    create table(:unmatched_shapes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :signature, :string, null: false
      add :source, :string, null: false
      add :source_type, :string
      add :paths, {:array, :string}, null: false, default: []
      add :count, :integer, null: false, default: 1
      add :first_seen, :utc_datetime_usec, null: false
      add :last_seen, :utc_datetime_usec, null: false
      add :sample_event, :map, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:unmatched_shapes, [:signature])
    create index(:unmatched_shapes, [:last_seen])
  end
end
