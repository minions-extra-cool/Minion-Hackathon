defmodule Minion.Accounts.Person do
  use Minion.Schema

  alias Minion.Accounts.Team

  @type t :: %__MODULE__{}

  @severities ~w(critical warning info)
  @channels ~w(email sms phone)

  schema "people" do
    field :name, :string
    field :email, :string
    field :phone, :string
    field :preferences, :map, default: %{}
    belongs_to :team, Team
    timestamps()
  end

  def severities, do: @severities
  def channels, do: @channels

  def changeset(person, attrs) do
    person
    |> cast(attrs, [:name, :email, :phone, :preferences, :team_id])
    |> validate_required([:name])
    |> validate_format(:email, ~r/^[^\s@]+@[^\s@]+$/, message: "must look like name@example.com")
    |> validate_format(:phone, ~r/^\+?[0-9 ()-]{6,}$/, message: "must be a phone number")
    |> validate_change(:preferences, &preference_errors/2)
    |> foreign_key_constraint(:team_id)
  end

  defp preference_errors(:preferences, preferences) when is_map(preferences) do
    Enum.flat_map(preferences, fn
      {severity, entries} when severity in @severities and is_list(entries) ->
        if Enum.all?(entries, &valid_entry?/1),
          do: [],
          else: [preferences: "#{severity} has an invalid entry"]

      {severity, _entries} ->
        [preferences: "unknown severity or malformed list: #{inspect(severity)}"]
    end)
  end

  defp preference_errors(:preferences, _other), do: [preferences: "must be a map"]

  defp valid_entry?(%{"channels" => channels} = entry) when is_list(channels) do
    Enum.all?(channels, &(&1 in @channels)) and valid_hours?(Map.get(entry, "hours"))
  end

  defp valid_entry?(_entry), do: false

  defp valid_hours?(nil), do: true

  defp valid_hours?([from, to])
       when is_integer(from) and is_integer(to) and from in 0..23 and to in 0..24 and from != to,
       do: true

  defp valid_hours?(_hours), do: false
end
