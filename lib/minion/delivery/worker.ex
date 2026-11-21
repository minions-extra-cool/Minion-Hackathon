defmodule Minion.Delivery.Worker do
  use Oban.Worker, queue: :default, max_attempts: 4

  import Ecto.Query

  alias Minion.Delivery.Delivery
  alias Minion.Repo

  @retry_delays_sec [5, 15, 60]
  @permanent_errors [:no_email_address, :no_phone_number]

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}),
    do: Enum.at(@retry_delays_sec, attempt - 1, List.last(@retry_delays_sec))

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"delivery_id" => delivery_id}} = job) do
    case Repo.get(Delivery, delivery_id) do
      nil ->
        {:cancel, :delivery_not_found}

      %Delivery{status: :pending} = delivery ->
        delivery |> Repo.preload([:alert, :person]) |> attempt(job)

      _already_finished ->
        :ok
    end
  end

  defp attempt(delivery, job) do
    case send_through_channel(delivery) do
      :ok ->
        delivery |> record(status: :delivered, last_error: nil) |> broadcast()
        :ok

      {:error, reason} ->
        if last_attempt?(job, reason) do
          give_up(delivery, reason)
          {:cancel, reason}
        else
          delivery |> record(last_error: inspect(reason)) |> broadcast()
          {:error, reason}
        end
    end
  end

  defp send_through_channel(delivery) do
    channel_for(delivery.channel).deliver(delivery.alert, delivery.person)
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  defp last_attempt?(job, reason),
    do: reason in @permanent_errors or job.attempt >= job.max_attempts

  defp give_up(delivery, reason) do
    {:ok, changed} =
      Repo.transaction(fn ->
        failed = record(delivery, status: :failed, last_error: inspect(reason))
        [failed | List.wrap(fall_back_to_email(failed))]
      end)

    Enum.each(changed, &broadcast/1)
  end

  defp fall_back_to_email(%Delivery{channel: :email}), do: nil
  defp fall_back_to_email(%Delivery{person: %{email: email}}) when email in [nil, ""], do: nil

  defp fall_back_to_email(%Delivery{alert: alert, person: person}) do
    Repo.one!(from a in Minion.Alerts.Alert, where: a.id == ^alert.id, lock: "FOR UPDATE")

    already_emailed? =
      Repo.exists?(
        from d in Delivery,
          where: d.alert_id == ^alert.id and d.person_id == ^person.id and d.channel == :email
      )

    if not already_emailed? do
      alert
      |> Minion.Delivery.schedule(person, :email)
      |> Map.merge(%{alert: alert, person: person})
    end
  end

  defp record(delivery, changes) do
    delivery
    |> Delivery.changeset(Map.new([{:attempts, delivery.attempts + 1} | changes]))
    |> Repo.update!()
  end

  defp broadcast(%Delivery{alert: alert} = delivery),
    do: Phoenix.PubSub.broadcast(Minion.PubSub, Minion.Alerts.topic(alert), {:delivery, delivery})

  defp channel_for(:email), do: Minion.Channels.Email
  defp channel_for(:sms), do: Minion.Channels.Sms
  defp channel_for(:phone), do: Minion.Channels.Phone
end
