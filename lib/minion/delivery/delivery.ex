defmodule Minion.Delivery.Delivery do
  use Minion.Schema

  alias Minion.Accounts.Person
  alias Minion.Alerts.Alert

  @type t :: %__MODULE__{}
  @type channel :: atom()

  schema "deliveries" do
    field :channel, Ecto.Enum, values: Minion.Channels.names()
    field :status, Ecto.Enum, values: [:pending, :delivered, :failed], default: :pending
    field :attempts, :integer, default: 0
    field :last_error, :string
    belongs_to :alert, Alert
    belongs_to :person, Person
    timestamps()
  end

  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [:alert_id, :person_id, :channel, :status, :attempts, :last_error])
    |> validate_required([:alert_id, :person_id, :channel])
  end
end
