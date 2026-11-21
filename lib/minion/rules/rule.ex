defmodule Minion.Rules.Rule do
  use Minion.Schema

  alias Minion.Rules.ConditionTree

  @owner_types [:team, :person]
  @severities [:info, :warning, :critical]

  @type t :: %__MODULE__{}

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

  @fields [
    :name,
    :owner_type,
    :owner_id,
    :enabled,
    :severity,
    :conditions,
    :dedup,
    :present,
    :notify
  ]

  def cast_changeset(rule, attrs), do: cast(rule, attrs, @fields)

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
    |> validate_change(:conditions, &validate_conditions/2)
    |> validate_change(:dedup, &validate_dedup/2)
    |> validate_change(:present, &validate_present/2)
    |> validate_change(:notify, &validate_notify/2)
  end

  defp validate_conditions(:conditions, conditions) do
    case condition_errors(conditions) do
      [] -> []
      [first | _] -> [conditions: first]
    end
  end

  defp condition_errors(%{"all" => children}), do: group_errors(children)
  defp condition_errors(%{"any" => children}), do: group_errors(children)

  defp condition_errors(%{"field" => field, "op" => op} = leaf)
       when is_binary(field) and field != "" do
    cond do
      op not in ConditionTree.ops() ->
        ["has an unknown operator #{inspect(op)}"]

      op == "exists" ->
        []

      op == "in" and not (is_list(leaf["value"]) and leaf["value"] != []) ->
        ["\"#{field} is one of\" needs at least one value"]

      leaf["value"] in [nil, ""] ->
        ["\"#{field}\" needs a value"]

      true ->
        []
    end
  end

  defp condition_errors(_invalid), do: ["every condition needs a field"]

  defp group_errors([]), do: ["need at least one condition"]

  defp group_errors(children) when is_list(children),
    do: Enum.flat_map(children, &condition_errors/1)

  defp group_errors(_invalid), do: ["must be a list of conditions"]

  defp validate_dedup(:dedup, dedup) do
    cond do
      not is_list(Map.get(dedup, "key", [])) ->
        [dedup: "key must be a list of fields"]

      not Enum.all?(Map.get(dedup, "key", []), &(is_binary(&1) and &1 != "")) ->
        [dedup: "key fields must be non-empty paths"]

      not valid_quiet?(Map.get(dedup, "quiet_sec")) ->
        [dedup: "quiet time must be a positive number of seconds"]

      true ->
        []
    end
  end

  defp valid_quiet?(nil), do: true
  defp valid_quiet?(seconds), do: is_integer(seconds) and seconds > 0

  defp validate_present(:present, present) do
    if Enum.all?(
         ["title", "body", "color"],
         &(Map.get(present, &1) == nil or is_binary(present[&1]))
       ) and
         is_list(Map.get(present, "fields", [])) do
      []
    else
      [present: "title, body and colour must be text, and fields a list"]
    end
  end

  @channels ["email", "sms", "phone"]

  defp validate_notify(:notify, entries) do
    cond do
      not Enum.all?(entries, &valid_recipient?/1) ->
        [notify: "each entry needs a type (person, team or oncall) and an id"]

      not Enum.all?(entries, &valid_channels?(Map.get(&1, "channels"))) ->
        [notify: "channels must be one or more of email, sms and phone"]

      true ->
        []
    end
  end

  defp valid_recipient?(%{"type" => type, "id" => id})
       when type in ["person", "team", "oncall"] and is_binary(id),
       do: true

  defp valid_recipient?(_entry), do: false

  defp valid_channels?(nil), do: true

  defp valid_channels?(channels) when is_list(channels) and channels != [],
    do: Enum.all?(channels, &(&1 in @channels))

  defp valid_channels?(_channels), do: false
end
