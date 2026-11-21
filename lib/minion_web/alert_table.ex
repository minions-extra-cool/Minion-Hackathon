defmodule MinionWeb.AlertTable do
  alias Minion.Alerts.Alert
  alias MinionWeb.AlertComponents

  @columns [
    %{id: "title", label: "Alert"},
    %{id: "source", label: "Source"},
    %{id: "owner", label: "Owner"},
    %{id: "rule", label: "Rule"},
    %{id: "severity", label: "Severity"},
    %{id: "status", label: "Status"},
    %{id: "count", label: "Events"},
    %{id: "first_seen", label: "First event"},
    %{id: "last_seen", label: "Last event"}
  ]
  @column_ids Enum.map(@columns, & &1.id)
  @required "title"
  @default_layout ~w(title source owner count last_seen)
  @sort_keys ["light" | @column_ids]
  @newest_first ~w(light severity status count first_seen last_seen)
  @default_sort {"last_seen", :desc}

  @severity_rank %{critical: 3, warning: 2, info: 1}
  @status_rank %{open: 3, acked: 2, resolved: 1}

  @type layout :: [String.t()]
  @type sort :: {String.t(), :asc | :desc}

  def columns, do: @columns
  def default_layout, do: @default_layout
  def default_sort, do: @default_sort
  def required?(id), do: id == @required

  @spec label(String.t()) :: String.t()
  def label("light"), do: "Status and severity"
  def label(id), do: Enum.find_value(@columns, id, &(&1.id == id && &1.label))

  @spec normalize_layout(term()) :: layout()
  def normalize_layout(ids) when is_list(ids) do
    ids = ids |> Enum.filter(&(&1 in @column_ids)) |> Enum.uniq()
    if @required in ids, do: ids, else: [@required | ids]
  end

  def normalize_layout(_ids), do: @default_layout

  @spec hidden(layout()) :: [String.t()]
  def hidden(layout), do: Enum.reject(@column_ids, &(&1 in layout))

  @spec toggle(layout(), String.t()) :: layout()
  def toggle(layout, @required), do: layout

  def toggle(layout, id) when id in @column_ids,
    do: if(id in layout, do: List.delete(layout, id), else: layout ++ [id])

  def toggle(layout, _unknown), do: layout

  @spec move(layout(), String.t(), :up | :down) :: layout()
  def move(layout, id, direction) do
    case Enum.find_index(layout, &(&1 == id)) do
      nil ->
        layout

      index ->
        target = if direction == :up, do: index - 1, else: index + 1

        if target < 0 or target >= length(layout),
          do: layout,
          else: layout |> List.delete_at(index) |> List.insert_at(target, id)
    end
  end

  @spec parse_sort(map()) :: sort()
  def parse_sort(%{"sort" => key} = params) when key in @sort_keys do
    case params["dir"] do
      "asc" -> {key, :asc}
      "desc" -> {key, :desc}
      _ -> {key, first_direction(key)}
    end
  end

  def parse_sort(_params), do: @default_sort

  @spec next_sort(sort(), String.t()) :: sort()
  def next_sort({key, :asc}, key), do: {key, :desc}
  def next_sort({key, :desc}, key), do: {key, :asc}
  def next_sort(_current, key), do: {key, first_direction(key)}

  defp first_direction(key) when key in @newest_first, do: :desc
  defp first_direction(_key), do: :asc

  @spec sort([Alert.t()], sort(), map()) :: [Alert.t()]
  def sort(alerts, {key, direction}, owners) do
    Enum.sort(alerts, fn a, b ->
      left = sort_value(a, key, owners)
      right = sort_value(b, key, owners)

      cond do
        left == right -> newer_first(a, b)
        direction == :asc -> left < right
        true -> left > right
      end
    end)
  end

  defp newer_first(a, b) do
    case DateTime.compare(a.last_seen, b.last_seen) do
      :gt -> true
      :lt -> false
      :eq -> a.id <= b.id
    end
  end

  @spec owner_label(map(), Alert.t()) :: String.t()
  def owner_label(owners, alert), do: owners[{alert.owner_type, alert.owner_id}] || "unknown"

  defp sort_value(alert, "light", _owners),
    do: {@severity_rank[alert.severity] || 0, @status_rank[alert.status] || 0}

  defp sort_value(alert, "severity", _owners), do: @severity_rank[alert.severity] || 0
  defp sort_value(alert, "status", _owners), do: @status_rank[alert.status] || 0
  defp sort_value(alert, "title", _owners), do: fold(alert.title)
  defp sort_value(alert, "source", _owners), do: fold(AlertComponents.source(alert))
  defp sort_value(alert, "owner", owners), do: fold(owner_label(owners, alert))
  defp sort_value(%{rule: %{name: name}}, "rule", _owners), do: fold(name)
  defp sort_value(_alert, "rule", _owners), do: ""
  defp sort_value(alert, "count", _owners), do: alert.count
  defp sort_value(alert, "first_seen", _owners), do: microseconds(alert.first_seen)
  defp sort_value(alert, "last_seen", _owners), do: microseconds(alert.last_seen)

  defp fold(nil), do: ""
  defp fold(text), do: text |> to_string() |> String.downcase()

  defp microseconds(nil), do: 0
  defp microseconds(datetime), do: DateTime.to_unix(datetime, :microsecond)
end
