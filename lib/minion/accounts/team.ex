defmodule Minion.Accounts.Team do
  use Minion.Schema

  alias Minion.Accounts.Person

  schema "teams" do
    field :name, :string
    belongs_to :oncall_person, Person
    has_many :members, Person
    timestamps()
  end

  def changeset(team, attrs) do
    team
    |> cast(attrs, [:name, :oncall_person_id])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
