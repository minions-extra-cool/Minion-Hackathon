defmodule MinionWeb.DashboardLive do
  use MinionWeb, :live_view

  import MinionWeb.AlertComponents

  alias Minion.Alerts
  alias Minion.Repo
  alias Minion.Rules.Rule

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Alerts.subscribe_all()

    alerts = Alerts.list_recent()

    {:ok,
     socket
     |> assign(
       page_title: "Dashboard",
       live?: connected?(socket),
       owners: Alerts.owner_names(),
       rules: alerts |> Enum.map(& &1.rule) |> Enum.reject(&is_nil/1) |> Map.new(&{&1.id, &1})
     )
     |> stream(:alerts, alerts)}
  end

  @impl true
  def handle_info({:alert, _event, alert}, socket) do
    socket = socket |> remember_rule(alert.rule_id) |> remember_owner(alert)
    alert = %{alert | rule: socket.assigns.rules[alert.rule_id]}

    {:noreply, stream_insert(socket, :alerts, alert, at: 0)}
  end

  def handle_info({:delivery, _delivery}, socket), do: {:noreply, socket}

  defp remember_rule(socket, nil), do: socket

  defp remember_rule(socket, rule_id) do
    if Map.has_key?(socket.assigns.rules, rule_id) do
      socket
    else
      assign(socket, :rules, Map.put(socket.assigns.rules, rule_id, Repo.get(Rule, rule_id)))
    end
  end

  defp remember_owner(socket, alert) do
    key = {alert.owner_type, alert.owner_id}

    if Map.has_key?(socket.assigns.owners, key) do
      socket
    else
      assign(socket, :owners, Map.put(socket.assigns.owners, key, Alerts.owner_name(alert)))
    end
  end

  defp owner_label(owners, alert), do: owners[{alert.owner_type, alert.owner_id}] || "unknown"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:dashboard}>
      <div class="flex flex-wrap items-end justify-between gap-4">
        <div>
          <h1 class="text-2xl font-semibold tracking-tight">Live feed</h1>
          <p class="mt-1 flex items-center gap-2 text-sm text-base-content/60">
            <span
              id="live-indicator"
              class={[
                "inline-block size-2 rounded-full",
                if(@live?, do: "bg-success", else: "bg-base-content/30")
              ]}
            />
            {if @live?, do: "Updating live as events arrive", else: "Connecting…"}
          </p>
        </div>
        <input
          id="alert-search"
          type="search"
          name="q"
          placeholder="Search alerts (coming soon)"
          disabled
          class="input input-sm w-72"
        />
      </div>

      <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
        <table id="alerts-table" class="table table-sm">
          <thead>
            <tr class="text-xs uppercase tracking-wide text-base-content/50">
              <th class="w-10"><span class="sr-only">Status</span></th>
              <th class="w-24">Severity</th>
              <th>Alert</th>
              <th class="w-40">Source</th>
              <th class="w-36">Owner</th>
              <th class="w-16 text-right">Events</th>
              <th class="w-32">Last event</th>
            </tr>
          </thead>
          <tbody id="alerts" phx-update="stream">
            <tr id="alerts-empty" class="hidden only:table-row">
              <td colspan="7" class="py-10 text-center text-base-content/50">
                No alerts yet. They appear here the moment an event matches a rule.
              </td>
            </tr>
            <tr
              :for={{dom_id, alert} <- @streams.alerts}
              id={dom_id}
              class={[
                "cursor-pointer transition-colors hover:bg-base-200",
                alert.status == :resolved && "text-base-content/50"
              ]}
              phx-click={JS.navigate(~p"/alerts/#{alert.id}")}
            >
              <td>
                <div class="flex items-center gap-2">
                  <.rule_stripe alert={alert} class="h-5" />
                  <.status_light status={alert.status} closed={not is_nil(alert.closed_at)} />
                </div>
              </td>
              <td><.severity_badge severity={alert.severity} /></td>
              <td class="max-w-0">
                <.link
                  navigate={~p"/alerts/#{alert.id}"}
                  class="block truncate font-medium hover:underline"
                >
                  {alert.title}
                </.link>
              </td>
              <td class="truncate text-base-content/70">
                {source(alert)}
                <span :if={source_type(alert)} class="text-xs text-base-content/40">
                  · {source_type(alert)}
                </span>
              </td>
              <td class="truncate text-base-content/70">{owner_label(@owners, alert)}</td>
              <td id={"#{dom_id}-count"} class="text-right tabular-nums">{alert.count}</td>
              <td class="text-base-content/70">
                <.local_time id={"#{dom_id}-last-seen"} at={alert.last_seen} />
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end
end
