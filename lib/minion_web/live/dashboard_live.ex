defmodule MinionWeb.DashboardLive do
  use MinionWeb, :live_view

  import MinionWeb.AlertComponents

  alias Minion.Alerts
  alias Minion.Repo
  alias Minion.Rules.Rule

  @shown 200
  @searched 1000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Alerts.subscribe_all()

    {:ok, assign(socket, page_title: "Dashboard", owners: Alerts.owner_names(), rules: %{})}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = params |> Map.get("q", "") |> String.trim()
    alerts = Alerts.list_recent(if query == "", do: @shown, else: @searched)
    socket = assign(socket, query: query, search_form: to_form(%{"q" => query}))

    socket =
      assign(
        socket,
        :rules,
        alerts
        |> Enum.map(& &1.rule)
        |> Enum.reject(&is_nil/1)
        |> Map.new(&{&1.id, &1})
        |> Map.merge(socket.assigns.rules)
      )

    shown = alerts |> Enum.filter(&matches?(socket, &1)) |> Enum.take(@shown)
    {:noreply, stream(socket, :alerts, shown, reset: true)}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    path = if String.trim(query) == "", do: ~p"/", else: ~p"/?#{[q: query]}"
    {:noreply, push_patch(socket, to: path, replace: true)}
  end

  @impl true
  def handle_info({:alert, _event, alert}, socket) do
    socket = socket |> remember_rule(alert.rule_id) |> remember_owner(alert)
    alert = %{alert | rule: socket.assigns.rules[alert.rule_id]}

    if matches?(socket, alert) do
      {:noreply, stream_insert(socket, :alerts, alert, at: 0)}
    else
      {:noreply, stream_delete(socket, :alerts, alert)}
    end
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

  defp matches?(%{assigns: %{query: ""}}, _alert), do: true

  defp matches?(socket, alert) do
    searchable =
      Enum.join(
        [
          alert.title,
          alert.body,
          source(alert),
          source_type(alert),
          owner_label(socket.assigns.owners, alert),
          alert.rule && alert.rule.name,
          alert.severity,
          status_label(alert.status, not is_nil(alert.closed_at))
        ],
        " "
      )

    Minion.Fuzzy.match?(socket.assigns.query, searchable)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_person={@current_person} people={@people} active={:dashboard}>
      <.feed_header active={:alerts}>
        <:actions>
          <.form for={@search_form} id="search-form" phx-change="search" phx-submit="search">
            <.input
              field={@search_form[:q]}
              id="alert-search"
              type="search"
              placeholder="Search alerts"
              autocomplete="off"
              phx-debounce="150"
              class="input input-sm w-72"
            />
          </.form>
        </:actions>
      </.feed_header>

      <p :if={@query != ""} id="search-summary" class="text-sm text-base-content/60">
        Showing alerts matching <span class="font-semibold text-base-content">{@query}</span>
        <.link patch={~p"/"} id="clear-search" class="ml-2 underline hover:text-base-content">
          Clear
        </.link>
      </p>

      <div class="overflow-x-auto rounded-box border border-base-300 bg-base-100">
        <table id="alerts-table" class="table table-sm">
          <thead>
            <tr class="text-xs uppercase tracking-wide text-base-content/50">
              <th class="w-10"><span class="sr-only">Status and severity</span></th>
              <th>Alert</th>
              <th class="w-40">Source</th>
              <th class="w-36">Owner</th>
              <th class="w-16 text-right">Events</th>
              <th class="w-32">Last event</th>
            </tr>
          </thead>
          <tbody id="alerts" phx-update="stream">
            <tr id="alerts-empty" class="hidden only:table-row">
              <td colspan="6" class="py-10 text-center text-base-content/50">
                No alerts to show. New alerts appear here the moment an event matches a rule.
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
                <.status_light
                  status={alert.status}
                  severity={alert.severity}
                  closed={not is_nil(alert.closed_at)}
                />
              </td>
              <td class="max-w-0">
                <span class="flex items-center gap-2">
                  <span class="flex w-1 shrink-0">
                    <.rule_color_mark id={"#{dom_id}-color"} alert={alert} />
                  </span>
                  <.link
                    navigate={~p"/alerts/#{alert.id}"}
                    class="min-w-0 truncate font-medium hover:underline"
                  >
                    {alert.title}
                  </.link>
                </span>
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
