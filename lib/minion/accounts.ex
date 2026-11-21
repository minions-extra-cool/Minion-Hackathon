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

  @spec change_team(Team.t(), map()) :: Ecto.Changeset.t()
  def change_team(%Team{} = team, attrs \\ %{}), do: Team.changeset(team, attrs)

  @spec update_team(Team.t(), map()) :: {:ok, Team.t()} | {:error, Ecto.Changeset.t()}
  def update_team(%Team{} = team, attrs) do
    with {:ok, team} <- team |> Team.changeset(attrs) |> Repo.update() do
      {:ok, get_team!(team.id)}
    end
  end
end
