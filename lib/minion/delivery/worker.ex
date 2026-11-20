defmodule Minion.Delivery.Worker do
  use Oban.Worker, queue: :default, max_attempts: 1

  alias Minion.Delivery.Delivery
  alias Minion.Repo

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"delivery_id" => delivery_id}}) do
    case Repo.get(Delivery, delivery_id) do
      nil -> {:cancel, :delivery_not_found}
      delivery -> delivery |> Repo.preload([:alert, :person]) |> send_delivery()
    end
  end

  defp send_delivery(delivery) do
    case channel_for(delivery.channel).deliver(delivery.alert, delivery.person) do
      :ok ->
        Delivery.changeset(delivery, %{
          status: :delivered,
          attempts: delivery.attempts + 1,
          last_error: nil
        })
        |> Repo.update!()

      {:error, reason} ->
        Delivery.changeset(delivery, %{
          status: :failed,
          attempts: delivery.attempts + 1,
          last_error: inspect(reason)
        })
        |> Repo.update!()
    end

    :ok
  end

  defp channel_for(:email), do: Minion.Channels.Email
  defp channel_for(:sms), do: Minion.Channels.Sms
  defp channel_for(:phone), do: Minion.Channels.Phone
end
