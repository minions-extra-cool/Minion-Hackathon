defmodule Minion.Alerts.Alert do
  use Minion.Schema

  alias Minion.Delivery.Delivery
  alias Minion.Rules.Rule

  schema "alerts" do
    field :owner_type, Ecto.Enum, values: [:team, :person]
    field :owner_id, :binary_id
    field :fingerprint, :string
    field :status, Ecto.Enum, values: [:open, :acked, :resolved], default: :open
    field :severity, Ecto.Enum, values: [:info, :warning, :critical]
    field :count, :integer, default: 1
    field :first_seen, :utc_datetime_usec
    field :last_seen, :utc_datetime_usec
    field :title, :string
    field :body, :string
    field :sample_event, :map
    belongs_to :rule, Rule
    has_many :deliveries, Delivery
    timestamps()
  end

  def changeset(alert, attrs) do
    alert
    |> cast(attrs, [
      :rule_id,
      :owner_type,
      :owner_id,
      :fingerprint,
      :status,
      :severity,
      :count,
      :first_seen,
      :last_seen,
      :title,
      :body,
      :sample_event
    ])
    |> validate_required([
      :owner_type,
      :owner_id,
      :fingerprint,
      :severity,
      :first_seen,
      :last_seen,
      :title,
      :sample_event
    ])
    |> unique_constraint(:fingerprint, name: :alerts_unresolved_fingerprint_index)
  end
end
