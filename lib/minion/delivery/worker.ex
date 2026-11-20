defmodule Minion.Delivery.Worker do
  @moduledoc false

  use Oban.Worker, queue: :default, max_attempts: 1

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    :ok
  end
end
