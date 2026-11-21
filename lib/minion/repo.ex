defmodule Minion.Repo do
  use Ecto.Repo,
    otp_app: :minion,
    adapter: Ecto.Adapters.Postgres
end
