defmodule Minion.Rules.Rule do
  use Minion.Schema

  @owner_types [:team, :person]
  @severities [:info, :warning, :critical]

  schema "rules" do
    field :name, :string
    field :owner_type, Ecto.Enum, values: @owner_types
    field :owner_id, :binary_id
    field :enabled, :boolean, default: true
    field :severity, Ecto.Enum, values: @severities
    field :conditions, :map
    field :dedup, :map, default: %{}
    field :present, :map, default: %{}
    field :notify, {:array, :map}
    timestamps()
  end

  def severities, do: @severities

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [
      :name,
      :owner_type,
      :owner_id,
      :enabled,
      :severity,
      :conditions,
      :dedup,
      :present,
      :notify
    ])
    |> validate_required([:name, :owner_type, :owner_id, :severity, :conditions, :notify])
  end
end
