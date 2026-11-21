defmodule Minion.Accounts do
  import Ecto.Query

  alias Minion.Accounts.{Person, Team}
  alias Minion.Repo

  @spec list_people() :: [Person.t()]
  def list_people, do: Repo.all(from p in Person, order_by: p.name, preload: :team)

  @spec get_person(Ecto.UUID.t() | nil) :: Person.t() | nil
  def get_person(nil), do: nil

  def get_person(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Person |> Repo.get(uuid) |> Repo.preload(:team)
      :error -> nil
    end
  end

  @spec get_person!(Ecto.UUID.t()) :: Person.t()
  def get_person!(id), do: Person |> Repo.get!(id) |> Repo.preload(:team)

  @spec owner_keys(Person.t() | nil) :: [{:person | :team, Ecto.UUID.t()}]
  def owner_keys(nil), do: []
  def owner_keys(%Person{id: id, team_id: nil}), do: [{:person, id}]
  def owner_keys(%Person{id: id, team_id: team_id}), do: [{:person, id}, {:team, team_id}]

  @spec owned_by(Ecto.Queryable.t(), Person.t() | nil) :: Ecto.Query.t()
  def owned_by(queryable, person) do
    owned =
      person
      |> owner_keys()
      |> Enum.reduce(dynamic(false), fn {type, id}, owned ->
        dynamic([r], ^owned or (r.owner_type == ^type and r.owner_id == ^id))
      end)

    where(queryable, ^owned)
  end

  @spec owns?(Person.t() | nil, %{owner_type: atom(), owner_id: Ecto.UUID.t()}) :: boolean()
  def owns?(person, %{owner_type: type, owner_id: id}), do: {type, id} in owner_keys(person)

  @spec change_person(Person.t(), map()) :: Ecto.Changeset.t()
  def change_person(%Person{} = person, attrs \\ %{}), do: Person.changeset(person, attrs)

  @spec update_person(Person.t(), map()) :: {:ok, Person.t()} | {:error, Ecto.Changeset.t()}
  def update_person(%Person{} = person, attrs) do
    with {:ok, person} <- person |> Person.changeset(attrs) |> Repo.update() do
      {:ok, Repo.preload(person, :team, force: true)}
    end
  end

  @spec create_person(map()) :: {:ok, Person.t()} | {:error, Ecto.Changeset.t()}
  def create_person(attrs), do: %Person{} |> Person.changeset(attrs) |> Repo.insert()

  @spec list_teams() :: [Team.t()]
  def list_teams do
    members = from p in Person, order_by: p.name
    Repo.all(from t in Team, order_by: t.name, preload: [:oncall_person, members: ^members])
  end

  @spec get_team!(Ecto.UUID.t()) :: Team.t()
  def get_team!(id) do
    members = from p in Person, order_by: p.name
    Team |> Repo.get!(id) |> Repo.preload([:oncall_person, members: members])
  end

  @spec create_team(map()) :: {:ok, Team.t()} | {:error, Ecto.Changeset.t()}
  def create_team(attrs), do: %Team{} |> Team.changeset(attrs) |> Repo.insert()

  @spec rule_counts() :: %{Ecto.UUID.t() => non_neg_integer()}
  def rule_counts do
    Repo.all(
      from r in Minion.Rules.Rule,
        where: r.owner_type == :team,
        group_by: r.owner_id,
        select: {r.owner_id, count(r.id)}
    )
    |> Map.new()
  end

  @spec list_team_rules(Ecto.UUID.t()) :: [Minion.Rules.Rule.t()]
  def list_team_rules(team_id) do
    Repo.all(
      from r in Minion.Rules.Rule,
        where: r.owner_type == :team and r.owner_id == ^team_id,
        order_by: r.name
    )
  end

  @spec generate_ingest_key(Team.t()) :: {:ok, Team.t(), String.t()}
  def generate_ingest_key(%Team{} = team) do
    key = "mk_" <> Base.url_encode64(:crypto.strong_rand_bytes(24), padding: false)
    {:ok, team} = put_ingest_key(team, key)
    {:ok, team, key}
  end

  @spec put_ingest_key(Team.t(), String.t()) :: {:ok, Team.t()}
  def put_ingest_key(%Team{} = team, key) when is_binary(key) and byte_size(key) >= 16 do
    team
    |> Ecto.Changeset.change(
      ingest_key_hash: hash_ingest_key(key),
      ingest_key_hint: String.slice(key, -4, 4),
      ingest_key_created_at: DateTime.utc_now()
    )
    |> Repo.update()
  end

  @spec team_for_ingest_key(String.t() | nil) :: Team.t() | nil
  def team_for_ingest_key(key) when is_binary(key) and key != "",
    do: Repo.get_by(Team, ingest_key_hash: hash_ingest_key(key))

  def team_for_ingest_key(_key), do: nil

  defp hash_ingest_key(key), do: :crypto.hash(:sha256, key)

  @spec change_team(Team.t(), map()) :: Ecto.Changeset.t()
  def change_team(%Team{} = team, attrs \\ %{}), do: Team.changeset(team, attrs)

  @spec update_team(Team.t(), map()) :: {:ok, Team.t()} | {:error, Ecto.Changeset.t()}
  def update_team(%Team{} = team, attrs) do
    with {:ok, team} <- team |> Team.changeset(attrs) |> Repo.update() do
      {:ok, get_team!(team.id)}
    end
  end
end
