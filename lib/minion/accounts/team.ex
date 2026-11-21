defmodule Minion.Accounts.Team do
  use Minion.Schema

  alias Minion.Accounts.Person

  schema "teams" do
    field :name, :string
    field :auto_resolve_after, :map, default: %{}
    belongs_to :oncall_person, Person
    has_many :members, Person
    timestamps()
  end

  def changeset(team, attrs) do
    team
    |> cast(attrs, [:name, :oncall_person_id, :auto_resolve_after])
    |> validate_required([:name])
    |> validate_auto_resolve_after()
    |> unique_constraint(:name)
  end

  defp validate_auto_resolve_after(changeset) do
    validate_change(changeset, :auto_resolve_after, fn :auto_resolve_after, settings ->
      Enum.flat_map(settings, fn
        {severity, seconds}
        when severity in ["info", "warning"] and is_integer(seconds) and seconds > 0 ->
          []

        {"critical", _seconds} ->
          [auto_resolve_after: "critical alerts never auto-resolve"]

        {severity, seconds} ->
          [auto_resolve_after: "invalid entry #{inspect(severity)} => #{inspect(seconds)}"]
      end)
    end)
  end
end
