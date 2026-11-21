defmodule Minion.Rules do
  import Ecto.Query

  alias Minion.Accounts.{Person, Team}
  alias Minion.Repo
  alias Minion.Rules.Rule

  @topic "rules"

  def topic, do: @topic

  @spec list_rules() :: [Rule.t()]
  def list_rules, do: Repo.all(from r in Rule, order_by: [asc: r.name, asc: r.inserted_at])

  @spec get_rule!(Ecto.UUID.t()) :: Rule.t()
  def get_rule!(id), do: Repo.get!(Rule, id)

  @spec change_rule(Rule.t(), map()) :: Ecto.Changeset.t()
  def change_rule(%Rule{} = rule, attrs \\ %{}), do: Rule.changeset(rule, attrs)

  @spec create_rule(map()) :: {:ok, Rule.t()} | {:error, Ecto.Changeset.t()}
  def create_rule(attrs), do: %Rule{} |> Rule.changeset(attrs) |> Repo.insert() |> notify()

  @spec update_rule(Rule.t(), map()) :: {:ok, Rule.t()} | {:error, Ecto.Changeset.t()}
  def update_rule(%Rule{} = rule, attrs),
    do: rule |> Rule.changeset(attrs) |> Repo.update() |> notify()

  @spec set_enabled(Rule.t(), boolean()) :: {:ok, Rule.t()} | {:error, Ecto.Changeset.t()}
  def set_enabled(%Rule{} = rule, enabled), do: update_rule(rule, %{enabled: enabled})

  defp notify({:ok, rule} = result) do
    Phoenix.PubSub.broadcast(Minion.PubSub, @topic, {:rules_changed, rule.id})
    result
  end

  defp notify(error), do: error

  @spec owner_options() :: [{String.t(), String.t()}]
  def owner_options do
    teams = Repo.all(from t in Team, order_by: t.name)
    people = Repo.all(from p in Person, order_by: p.name)

    Enum.map(teams, &{"Team #{&1.name}", "team:#{&1.id}"}) ++
      Enum.map(people, &{&1.name, "person:#{&1.id}"})
  end

  @spec notify_options() :: [%{value: String.t(), label: String.t()}]
  def notify_options do
    teams = Repo.all(from t in Team, order_by: t.name)
    people = Repo.all(from p in Person, order_by: p.name)

    Enum.flat_map(teams, fn team ->
      [
        %{value: "team:#{team.id}", label: "Everyone in #{team.name}"},
        %{value: "oncall:#{team.id}", label: "On call for #{team.name}"}
      ]
    end) ++ Enum.map(people, &%{value: "person:#{&1.id}", label: &1.name})
  end
end
