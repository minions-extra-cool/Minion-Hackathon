defmodule MinionWeb.RulesLive do
  use MinionWeb, :live_view

  import MinionWeb.AlertComponents

  alias Minion.Rules
  alias Minion.Rules.ConditionTree

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Minion.PubSub, Rules.topic())

    {:ok,
     socket
     |> assign(
       page_title: "Rules",
       owners: Map.new(Rules.owner_options(), fn {label, value} -> {value, label} end),
       notify_labels: Map.new(Rules.notify_options(), &{&1.value, &1.label})
     )
     |> stream(:rules, Rules.list_rules())}
  end

  @impl true
  def handle_event("toggle", %{"id" => id}, socket) do
    rule = Rules.get_rule!(id)
    {:ok, rule} = Rules.set_enabled(rule, not rule.enabled)
    {:noreply, stream_insert(socket, :rules, rule)}
  end

  @impl true
  def handle_info({:rules_changed, id}, socket) do
    case Rules.get_rule(id) do
      nil -> {:noreply, stream_delete_by_dom_id(socket, :rules, "rules-#{id}")}
      rule -> {:noreply, stream_insert(socket, :rules, rule)}
    end
  end

  defp owner_label(owners, rule), do: owners["#{rule.owner_type}:#{rule.owner_id}"] || "unknown"

  defp notify_label(_labels, []), do: "Nobody (feed only)"

  defp notify_label(labels, entries) do
    who =
      entries
      |> Enum.map(&(labels["#{&1["type"]}:#{&1["id"]}"] || "missing #{&1["type"]}"))
      |> Enum.join(", ")

    case entries |> Enum.flat_map(&List.wrap(&1["channels"])) |> Enum.uniq() do
      [] -> who
      channels -> "#{who} · by #{channels |> Enum.map(&channel_label/1) |> Enum.join(", ")}"
    end
  end

  defp channel_label("sms"), do: "SMS"
  defp channel_label("phone"), do: "phone call"
  defp channel_label(channel), do: channel

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_person={@current_person} people={@people} active={:rules}>
      <div class="flex flex-wrap items-end justify-between gap-4">
        <h1 class="text-2xl font-semibold tracking-tight">Rules</h1>
        <.link navigate={~p"/rules/new"} id="new-rule" class="btn btn-sm btn-primary">
          <.icon name="hero-plus-mini" class="size-4" /> New rule
        </.link>
      </div>

      <div class="overflow-x-auto border border-base-300 bg-base-100">
        <table id="rules-table" class="table table-sm">
          <thead>
            <tr class="text-xs uppercase tracking-wide text-base-content/50">
              <th class="w-10"><span class="sr-only">Severity</span></th>
              <th>Rule</th>
              <th>When</th>
              <th class="w-56">Notifies</th>
              <th class="w-24 text-right">Enabled</th>
            </tr>
          </thead>
          <tbody id="rules" phx-update="stream">
            <tr id="rules-empty" class="hidden only:table-row">
              <td colspan="5" class="py-10 text-center text-base-content/50">
                No rules yet. Create one to start turning events into alerts.
              </td>
            </tr>
            <tr
              :for={{dom_id, rule} <- @streams.rules}
              id={dom_id}
              class={[
                "transition-colors hover:bg-base-200",
                not rule.enabled && "text-base-content/50"
              ]}
            >
              <td><.rule_light severity={rule.severity} enabled={rule.enabled} /></td>
              <td>
                <.link navigate={~p"/rules/#{rule.id}"} class="font-medium hover:underline">
                  {rule.name}
                </.link>
                <div class="text-xs text-base-content/50">{owner_label(@owners, rule)}</div>
              </td>
              <td class="max-w-md font-mono text-xs text-base-content/70">
                {ConditionTree.describe(ConditionTree.normalize(rule.conditions))}
              </td>
              <td class="text-base-content/70">{notify_label(@notify_labels, rule.notify)}</td>
              <td class="text-right">
                <input
                  type="checkbox"
                  id={"#{dom_id}-enabled"}
                  class="toggle toggle-sm"
                  checked={rule.enabled}
                  phx-click="toggle"
                  phx-value-id={rule.id}
                  aria-label={"Enable #{rule.name}"}
                />
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end
end
