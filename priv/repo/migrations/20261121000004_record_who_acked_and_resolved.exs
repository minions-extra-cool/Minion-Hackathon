defmodule Minion.Repo.Migrations.RecordWhoAckedAndResolved do
  use Ecto.Migration

  def change do
    alter table(:alerts) do
      add :acked_by_id, references(:people, type: :binary_id, on_delete: :nilify_all)
      add :acked_at, :utc_datetime_usec
      add :resolved_by_id, references(:people, type: :binary_id, on_delete: :nilify_all)
      add :resolved_at, :utc_datetime_usec
      add :resolution_note, :text
    end
  end
end
