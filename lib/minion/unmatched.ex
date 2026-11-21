defmodule Minion.Unmatched do
  import Ecto.Query

  alias Minion.Repo
  alias Minion.Rules.{ConditionTree, Draft, Path}
  alias Minion.Unmatched.Shape

  @topic "unmatched"
  @retention_hours 24
  @identifying_fields ~w(type alertname event event_type eventType kind name meta.schema schema level)

  def topic, do: @topic

  def subscribe, do: Phoenix.PubSub.subscribe(Minion.PubSub, @topic)

  @spec record(map()) :: Shape.t()
  def record(envelope) do
    now = DateTime.utc_now()
    source = to_string(envelope["source"] || "unknown")
    paths = envelope |> Map.get("payload") |> Path.list() |> Enum.map(&("payload." <> &1))

    shape =
      Repo.insert!(
        %Shape{
          signature: signature(source, paths),
          source: source,
          source_type: envelope["source_type"],
          paths: paths,
          count: 1,
          first_seen: now,
          last_seen: now,
          sample_event: envelope
        },
        on_conflict: [
          inc: [count: 1],
          set: [last_seen: now, sample_event: envelope, updated_at: now]
        ],
        conflict_target: :signature,
        returning: true
      )

    Phoenix.PubSub.broadcast(Minion.PubSub, @topic, {:unmatched, shape})
    shape
  end

  defp signature(source, paths) do
    :crypto.hash(:sha256, Jason.encode!([source | paths])) |> Base.encode16(case: :lower)
  end

  @spec list_recent(pos_integer()) :: [Shape.t()]
  def list_recent(limit \\ 200),
    do: Repo.all(from s in Shape, order_by: [desc: s.last_seen], limit: ^limit)

  @spec get(Ecto.UUID.t()) :: Shape.t() | nil
  def get(id), do: Repo.get(Shape, id)

  @spec dismiss(Ecto.UUID.t()) :: :ok
  def dismiss(id) do
    Repo.delete_all(from s in Shape, where: s.id == ^id)
    Phoenix.PubSub.broadcast(Minion.PubSub, @topic, {:dismissed, id})
    :ok
  end

  @spec prune(DateTime.t()) :: non_neg_integer()
  def prune(now \\ DateTime.utc_now()) do
    cutoff = DateTime.add(now, -@retention_hours, :hour)
    {count, _} = Repo.delete_all(from s in Shape, where: s.last_seen < ^cutoff)
    count
  end

  @spec identifying_field(Shape.t()) :: {String.t(), term()} | nil
  def identifying_field(%Shape{sample_event: event}) do
    Enum.find_value(@identifying_fields, fn field ->
      case Path.fetch(event, "payload." <> field) do
        {:ok, value} when is_binary(value) and value != "" -> {"payload." <> field, value}
        _ -> nil
      end
    end)
  end

  @spec suggested_draft(Shape.t(), String.t() | nil) :: map()
  def suggested_draft(%Shape{} = shape, owner) do
    identifying = identifying_field(shape)
    source_condition = %{"field" => "source", "op" => "eq", "value" => shape.source}

    conditions =
      case identifying do
        {field, value} -> [source_condition, %{"field" => field, "op" => "eq", "value" => value}]
        nil -> [source_condition]
      end

    label = if identifying, do: elem(identifying, 1), else: "events"

    Draft.new(owner)
    |> Map.merge(%{
      "name" => "#{label} from #{shape.source}",
      "conditions" => %{"all" => conditions},
      "title" => "#{label} from #{shape.source}"
    })
    |> Map.update!("conditions", &ConditionTree.normalize/1)
  end
end
