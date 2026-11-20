defmodule Minion.Accounts.Person do
  use Minion.Schema

  alias Minion.Accounts.Team

  @type t :: %__MODULE__{}

  schema "people" do
    field :name, :string
    field :email, :string
    field :phone, :string
    field :preferences, :map, default: %{}
    belongs_to :team, Team
    timestamps()
  end

  def changeset(person, attrs) do
    person
    |> cast(attrs, [:name, :email, :phone, :preferences, :team_id])
    |> validate_required([:name])
  end
end
