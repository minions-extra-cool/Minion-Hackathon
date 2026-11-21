defmodule Minion.Alerts do
  import Ecto.Query

  alias Minion.Accounts.{Person, Team}
  alias Minion.Alerts.Alert
  alias Minion.Delivery.Delivery
  alias Minion.Repo

  @spec topic(Alert.t()) :: String.t()
  def topic(%Alert{owner_type: owner_type, owner_id: owner_id}),
    do: "alerts:#{owner_type}:#{owner_id}"

  @spec subscribe_visible(Person.t() | nil) :: :ok
  def subscribe_visible(person) do
    person
    |> visible_owners()
    |> Enum.each(fn {type, id} ->
      Phoenix.PubSub.subscribe(Minion.PubSub, "alerts:#{type}:#{id}")
    end)
  end

  @spec visible_to?(Alert.t(), Person.t() | nil) :: boolean()
  def visible_to?(%Alert{owner_type: type, owner_id: id}, person),
    do: {type, id} in visible_owners(person)

  defp visible_owners(nil), do: []
  defp visible_owners(%Person{id: id, team_id: nil}), do: [{:person, id}]
  defp visible_owners(%Person{id: id, team_id: team_id}), do: [{:person, id}, {:team, team_id}]

  @spec subscribe(Alert.t()) :: :ok | {:error, term()}
  def subscribe(%Alert{} = alert), do: Phoenix.PubSub.subscribe(Minion.PubSub, topic(alert))

  @spec list_recent(pos_integer()) :: [Alert.t()]
  def list_recent(limit \\ 200) do
    Repo.all(from a in Alert, order_by: [desc: a.last_seen], limit: ^limit, preload: :rule)
  end

  @spec list_recent_visible(Person.t() | nil, pos_integer()) :: [Alert.t()]
  def list_recent_visible(nil, _limit), do: []

  def list_recent_visible(%Person{id: person_id, team_id: team_id}, limit) do
    owned_by_person = dynamic([a], a.owner_type == :person and a.owner_id == ^person_id)

    owned =
      if team_id,
        do: dynamic([a], ^owned_by_person or (a.owner_type == :team and a.owner_id == ^team_id)),
        else: owned_by_person

    Repo.all(
      from a in Alert,
        where: ^owned,
        order_by: [desc: a.last_seen],
        limit: ^limit,
        preload: :rule
    )
  end

  @spec get_alert!(Ecto.UUID.t()) :: Alert.t()
  def get_alert!(id), do: Alert |> Repo.get!(id) |> Repo.preload(:rule)

  @spec get_alert(Ecto.UUID.t()) :: Alert.t() | nil
  def get_alert(id), do: Repo.get(Alert, id)

  @spec with_rule(Alert.t()) :: Alert.t()
  def with_rule(%Alert{} = alert), do: Repo.preload(alert, :rule)

  @spec list_deliveries(Alert.t()) :: [Delivery.t()]
  def list_deliveries(%Alert{id: id}) do
    Repo.all(
      from d in Delivery, where: d.alert_id == ^id, order_by: d.inserted_at, preload: :person
    )
  end

  @spec owner_names() :: %{{atom(), Ecto.UUID.t()} => String.t()}
  def owner_names do
    teams = Repo.all(from t in Team, select: {t.id, t.name})
    people = Repo.all(from p in Person, select: {p.id, p.name})

    Map.new(teams, fn {id, name} -> {{:team, id}, name} end)
    |> Map.merge(Map.new(people, fn {id, name} -> {{:person, id}, name} end))
  end

  @spec owner_name(Alert.t()) :: String.t() | nil
  def owner_name(%Alert{owner_type: :team, owner_id: id}),
    do: Repo.one(from t in Team, where: t.id == ^id, select: t.name)

  def owner_name(%Alert{owner_type: :person, owner_id: id}),
    do: Repo.one(from p in Person, where: p.id == ^id, select: p.name)

  @spec acknowledge(Ecto.UUID.t(), Ecto.UUID.t()) :: {:ok, Alert.t()} | {:error, :not_open}
  def acknowledge(id, person_id) do
    now = DateTime.utc_now()

    case transition(id, [:open], :acked, acked_by_id: person_id, acked_at: now) do
      {:ok, alert} -> {:ok, alert}
      :error -> {:error, :not_open}
    end
  end

  @spec resolve(Ecto.UUID.t(), Ecto.UUID.t()) :: {:ok, Alert.t()} | {:error, :already_resolved}
  def resolve(id, person_id) do
    now = DateTime.utc_now()

    case transition(id, [:open, :acked], :resolved, resolved_by_id: person_id, resolved_at: now) do
      {:ok, alert} -> {:ok, alert}
      :error -> {:error, :already_resolved}
    end
  end

  @spec save_resolution_note(Ecto.UUID.t(), String.t() | nil) ::
          {:ok, Alert.t()} | {:error, :not_resolved}
  def save_resolution_note(id, note) do
    note = if is_binary(note) and String.trim(note) != "", do: String.trim(note)

    from(a in Alert, where: a.id == ^id and a.status == :resolved, select: a)
    |> Repo.update_all(set: [resolution_note: note, updated_at: DateTime.utc_now()])
    |> case do
      {1, [alert]} ->
        Phoenix.PubSub.broadcast(Minion.PubSub, topic(alert), {:alert, :updated, alert})
        {:ok, alert}

      {0, []} ->
        {:error, :not_resolved}
    end
  end

  defp transition(id, from_statuses, to_status, actor_fields) do
    now = DateTime.utc_now()

    from(a in Alert, where: a.id == ^id and a.status in ^from_statuses, select: a)
    |> Repo.update_all(set: [status: to_status, updated_at: now] ++ actor_fields)
    |> case do
      {1, [alert]} ->
        Phoenix.PubSub.broadcast(Minion.PubSub, topic(alert), {:alert, to_status, alert})
        {:ok, alert}

      {0, []} ->
        :error
    end
  end
end
