defmodule Minion.Unmatched.Shape do
  use Minion.Schema

  @type t :: %__MODULE__{}

  schema "unmatched_shapes" do
    field :signature, :string
    field :source, :string
    field :source_type, :string
    field :paths, {:array, :string}, default: []
    field :count, :integer, default: 1
    field :first_seen, :utc_datetime_usec
    field :last_seen, :utc_datetime_usec
    field :sample_event, :map
    timestamps()
  end
end
