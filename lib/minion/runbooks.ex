defmodule Minion.Runbooks do
  alias Minion.Repo
  alias Minion.Rules.Template
  alias Minion.Runbooks.Runbook

  @spec get_for_rule(Ecto.UUID.t() | nil) :: Runbook.t() | nil
  def get_for_rule(nil), do: nil
  def get_for_rule(rule_id), do: Repo.get_by(Runbook, rule_id: rule_id)

  @spec get_or_build_for_rule(Ecto.UUID.t()) :: Runbook.t()
  def get_or_build_for_rule(rule_id), do: get_for_rule(rule_id) || %Runbook{rule_id: rule_id}

  @spec change_runbook(Runbook.t(), map()) :: Ecto.Changeset.t()
  def change_runbook(%Runbook{} = runbook, attrs \\ %{}), do: Runbook.changeset(runbook, attrs)

  @spec save_runbook(Runbook.t(), map()) :: {:ok, Runbook.t()} | {:error, Ecto.Changeset.t()}
  def save_runbook(%Runbook{} = runbook, attrs),
    do: runbook |> Runbook.changeset(attrs) |> Repo.insert_or_update()

  @spec blank?(Runbook.t() | nil) :: boolean()
  def blank?(nil), do: true
  def blank?(%Runbook{body: body}), do: String.trim(body || "") == ""

  @spec render(Runbook.t(), map() | nil) :: String.t()
  def render(%Runbook{body: body}, event), do: Template.render(body, event || %{})
end
