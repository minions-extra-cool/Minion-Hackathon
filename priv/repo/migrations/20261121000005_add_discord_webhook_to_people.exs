defmodule Minion.Repo.Migrations.AddDiscordWebhookToPeople do
  use Ecto.Migration

  def change do
    alter table(:people) do
      add :discord_webhook_url, :text
    end
  end
end
