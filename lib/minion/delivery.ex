defmodule Minion.Delivery do
  @moduledoc false

  import Ecto.Query

  alias Minion.Accounts.{Person, Team}
  alias Minion.Alerts.Alert
  alias Minion.Delivery.Delivery
  alias Minion.Repo
  alias Minion.Rules.Rule

  @channels [:email, :sms, :phone]
  @preference_hours_zone "Etc/UTC"

  @spec dispatch(Alert.t(), DateTime.t() | nil) :: :ok
  def dispatch(%Alert{} = alert, now \\ nil) do
    now = now || DateTime.utc_now()

    alert
    |> people_to_notify()
    |> Enum.uniq_by(& &1.id)
    |> Enum.each(fn person ->
      person
      |> channels_for(alert.severity, now)
      |> Enum.each(fn channel -> schedule(alert, person, channel) end)
    end)

    :ok
  end

  def hours_zone, do: @preference_hours_zone

  defp people_to_notify(%Alert{rule_id: nil}), do: []

  defp people_to_notify(%Alert{rule_id: rule_id}) do
    Repo.get(Rule, rule_id).notify
    |> Enum.flat_map(&people_for_notify_entry/1)
  end

  defp people_for_notify_entry(%{"type" => "person", "id" => id}) do
    person = Repo.get(Person, id)
    if(person, do: [person], else: [])
  end

  defp people_for_notify_entry(%{"type" => "team", "id" => id}) do
    Repo.all(from person in Person, where: person.team_id == ^id)
  end

  defp people_for_notify_entry(%{"type" => "oncall", "id" => id}) do
    case Repo.get(Team, id) do
      nil ->
        []

      %Team{oncall_person_id: nil} ->
        []

      %Team{oncall_person_id: person_id} ->
        people_for_notify_entry(%{"type" => "person", "id" => person_id})
    end
  end

  defp people_for_notify_entry(_unknown), do: []

  defp channels_for(person, severity, now) do
    person.preferences
    |> Map.get(to_string(severity), [])
    |> Enum.find(&applies?(&1, now))
    |> case do
      nil -> []
      entry -> entry |> Map.get("channels", []) |> Enum.map(&channel_from/1)
    end
    |> Enum.uniq()
    |> Enum.filter(&(&1 in @channels))
  end

  defp channel_from(channel) when is_binary(channel) do
    String.to_existing_atom(channel)
  rescue
    ArgumentError -> nil
  end

  defp channel_from(channel) when is_atom(channel), do: channel

  defp applies?(%{"hours" => [from, to]}, now) do
    hour = hour_in_zone(now)
    from <= hour and hour < to
  end

  defp applies?(%{} = _entry, _now), do: true

  defp hour_in_zone(now) do
    now
    |> DateTime.shift_zone!(@preference_hours_zone)
    |> DateTime.to_time()
    |> Map.fetch!(:hour)
  end

  defp schedule(alert, person, channel) do
    delivery =
      %Delivery{alert_id: alert.id, person_id: person.id, channel: channel}
      |> Repo.insert!()

    %{"delivery_id" => delivery.id}
    |> Minion.Delivery.Worker.new(queue: to_string(channel))
    |> Oban.insert!()
  end
end
