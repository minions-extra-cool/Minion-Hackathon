defmodule Minion.Delivery do
  require Logger

  import Ecto.Query

  alias Minion.Accounts.{Person, Team}
  alias Minion.Alerts.Alert
  alias Minion.Delivery.Delivery
  alias Minion.Repo
  alias Minion.Rules.Rule

  @channels [:email, :sms, :phone]
  @preference_hours_zone "Etc/UTC"

  @spec dispatch(Alert.t(), DateTime.t()) :: :ok
  def dispatch(%Alert{} = alert, now \\ DateTime.utc_now()) do
    alert
    |> recipients()
    |> Enum.group_by(fn {person, _channels} -> person.id end)
    |> Enum.each(fn {_person_id, [{person, _} | _] = entries} ->
      entries
      |> Enum.flat_map(fn {_person, rule_channels} ->
        rule_channels || channels_for(person, alert.severity, now)
      end)
      |> Enum.uniq()
      |> Enum.each(fn channel -> schedule(alert, person, channel) end)
    end)

    :ok
  end

  def hours_zone, do: @preference_hours_zone

  defp recipients(%Alert{rule_id: nil}), do: []

  defp recipients(%Alert{rule_id: rule_id}) do
    Repo.get(Rule, rule_id).notify
    |> Enum.flat_map(fn entry ->
      channels = rule_channels(entry)
      entry |> people_for_notify_entry() |> Enum.map(&{&1, channels})
    end)
  end

  defp rule_channels(%{"channels" => channels}) when is_list(channels) and channels != [] do
    channels |> Enum.map(&channel_from/1) |> Enum.filter(&(&1 in @channels)) |> Enum.uniq()
  end

  defp rule_channels(_entry), do: nil

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
    |> valid_entries(person, severity)
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

  defp valid_entries(entries, person, severity) do
    {valid, invalid} =
      if is_list(entries), do: Enum.split_with(entries, &is_map/1), else: {[], [entries]}

    if invalid != [] do
      Logger.warning(
        "Ignoring malformed #{severity} preferences for #{person.name} (#{person.id}): #{inspect(invalid)}"
      )
    end

    valid
  end

  defp applies?(%{"hours" => [from, to]}, now) when is_integer(from) and is_integer(to) do
    hour = hour_in_zone(now)
    if from <= to, do: from <= hour and hour < to, else: hour >= from or hour < to
  end

  defp applies?(%{"hours" => _malformed}, _now), do: false

  defp applies?(%{} = _entry, _now), do: true

  defp hour_in_zone(now) do
    now
    |> DateTime.shift_zone!(@preference_hours_zone)
    |> DateTime.to_time()
    |> Map.fetch!(:hour)
  end

  @spec schedule(Alert.t(), Person.t(), Delivery.channel()) :: Delivery.t()
  def schedule(alert, person, channel) do
    delivery =
      %Delivery{alert_id: alert.id, person_id: person.id, channel: channel}
      |> Repo.insert!()

    %{"delivery_id" => delivery.id}
    |> Minion.Delivery.Worker.new(queue: to_string(channel))
    |> Oban.insert!()

    delivery
  end
end
