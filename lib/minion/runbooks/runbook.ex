defmodule Minion.Runbooks.Runbook do
  use Minion.Schema

  alias Minion.Rules.Rule

  @type t :: %__MODULE__{}

  schema "runbooks" do
    belongs_to :rule, Rule
    field :body, :string, default: ""
    timestamps()
  end

  def changeset(runbook, attrs) do
    runbook
    |> cast(attrs, [:body], empty_values: [nil])
    |> validate_required([:rule_id])
    |> unique_constraint(:rule_id)
  end
end
