defmodule MinionWeb.DashboardLive do
  use MinionWeb, :live_view

  import MinionWeb.AlertComponents

  alias Minion.Alerts
  alias Minion.Repo
  alias Minion.Rules.Rule
  alias MinionWeb.AlertTable

  @shown 200
  @searched 1000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Alerts.subscribe_visible(socket.assigns.current_person)

    {:ok,
     assign(socket,
       page_title: "Dashboard",
       owners: Alerts.owner_names(),
       rules: %{},
       columns: AlertTable.default_layout(),
       shown: []
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    query = params |> Map.get("q", "") |> String.trim()

    alerts =
      Alerts.list_recent_visible(
        socket.assigns.current_person,
        if(query == "", do: @shown, else: @searched)
      )

    socket =
      assign(socket,
        query: query,
        sort: AlertTable.parse_sort(params),
        search_form: to_form(%{"q" => query})
      )

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
    {:noreply, show_rows(socket, shown)}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply, push_patch(socket, to: feed_path(String.trim(query), socket.assigns.sort))}
  end

  def handle_event("sort", %{"key" => key}, socket) do
    sort = AlertTable.next_sort(socket.assigns.sort, key)
    {:noreply, push_patch(socket, to: feed_path(socket.assigns.query, sort))}
  end

  def handle_event("set_columns", %{"columns" => columns}, socket),
    do: {:noreply, put_layout(socket, AlertTable.normalize_layout(columns), false)}

  def handle_event("toggle_column", %{"id" => id}, socket),
    do: {:noreply, put_layout(socket, AlertTable.toggle(socket.assigns.columns, id), true)}

  def handle_event("move_column", %{"id" => id, "direction" => direction}, socket) do
    direction = if direction == "up", do: :up, else: :down
    {:noreply, put_layout(socket, AlertTable.move(socket.assigns.columns, id, direction), true)}
  end

  def handle_event("reset_columns", _params, socket),
    do: {:noreply, put_layout(socket, AlertTable.default_layout(), true)}

  @impl true
  def handle_info({:alert, _event, alert}, socket) do
    if Minion.Accounts.owns?(socket.assigns.current_person, alert),
      do: {:noreply, show_alert(socket, alert)},
      else: {:noreply, socket}
  end

  def handle_info({:delivery, _delivery}, socket), do: {:noreply, socket}

  defp show_alert(socket, alert) do
    socket = socket |> remember_rule(alert.rule_id) |> remember_owner(alert)
    alert = %{alert | rule: socket.assigns.rules[alert.rule_id]}
    previous = socket.assigns.shown

    others = Enum.reject(previous, &(&1.id == alert.id))
    candidates = if matches?(socket, alert), do: [alert | others], else: others

    shown =
      candidates
      |> AlertTable.sort(socket.assigns.sort, socket.assigns.owners)
      |> Enum.take(@shown)

    socket =
      socket
      |> assign(:shown, shown)
      |> drop_rows(previous, shown)

    place_row(socket, alert, previous, shown)
  end

  defp show_rows(socket, alerts) do
    shown = AlertTable.sort(alerts, socket.assigns.sort, socket.assigns.owners)

    socket
    |> assign(:shown, shown)
    |> stream(:alerts, shown, reset: true)
  end

  defp drop_rows(socket, previous, shown) do
    kept = MapSet.new(shown, & &1.id)

    previous
    |> Enum.reject(&MapSet.member?(kept, &1.id))
    |> Enum.reduce(socket, &stream_delete(&2, :alerts, &1))
  end

  defp place_row(socket, alert, previous, shown) do
    old_index = Enum.find_index(previous, &(&1.id == alert.id))
    new_index = Enum.find_index(shown, &(&1.id == alert.id))

    cond do
      is_nil(new_index) ->
        socket

      old_index == new_index ->
        stream_insert(socket, :alerts, alert)

      is_nil(old_index) ->
        stream_insert(socket, :alerts, alert, at: new_index)

      true ->
        socket |> stream_delete(:alerts, alert) |> stream_insert(:alerts, alert, at: new_index)
    end
  end

  defp put_layout(socket, layout, save?) do
    socket =
      socket |> assign(:columns, layout) |> stream(:alerts, socket.assigns.shown, reset: true)

    if save?, do: push_event(socket, "columns_saved", %{columns: layout}), else: socket
  end

  defp feed_path(query, sort) do
    params =
      [q: query]
      |> Enum.reject(fn {_key, value} -> value == "" end)
      |> Kernel.++(if sort == AlertTable.default_sort(), do: [], else: sort_params(sort))

    if params == [], do: ~p"/", else: ~p"/?#{params}"
  end

  defp sort_params({key, direction}), do: [sort: key, dir: direction]

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

  defp matches?(%{assigns: %{query: ""}}, _alert), do: true

  defp matches?(socket, alert) do
    searchable =
      Enum.join(
        [
          alert.title,
          alert.body,
          source(alert),
          source_type(alert),
          AlertTable.owner_label(socket.assigns.owners, alert),
          alert.rule && alert.rule.name,
          alert.severity,
          status_label(alert.status, not is_nil(alert.closed_at))
        ],
        " "
      )

    Minion.Fuzzy.match?(socket.assigns.query, searchable)
  end

  defp aria_sort({key, :asc}, key), do: "ascending"
  defp aria_sort({key, :desc}, key), do: "descending"
  defp aria_sort(_sort, _key), do: "none"

  defp sort_icon({key, :asc}, key), do: "hero-chevron-up-micro"
  defp sort_icon({key, :desc}, key), do: "hero-chevron-down-micro"
  defp sort_icon(_sort, _key), do: "hero-chevron-up-down-micro"

  defp column_class("count"), do: "w-20 text-right"
  defp column_class("title"), do: "min-w-56"
  defp column_class(id) when id in ~w(first_seen last_seen), do: "w-32"
  defp column_class(id) when id in ~w(severity status), do: "w-28"
  defp column_class(_id), do: "w-40"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_person={@current_person} people={@people} active={:dashboard}>
      <.feed_header active={:alerts}>
        <:actions>
          <div class="flex items-center gap-2">
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
            <.columns_menu columns={@columns} />
          </div>
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
              <th class="w-10" aria-sort={aria_sort(@sort, "light")}>
                <.sort_button sort={@sort} key="light">
                  <span class="sr-only">{AlertTable.label("light")}</span>
                </.sort_button>
              </th>
              <th
                :for={column <- @columns}
                id={"column-#{column}"}
                class={column_class(column)}
                aria-sort={aria_sort(@sort, column)}
              >
                <.sort_button sort={@sort} key={column} align_right={column == "count"}>
                  {AlertTable.label(column)}
                </.sort_button>
              </th>
            </tr>
          </thead>
          <tbody id="alerts" phx-update="stream">
            <tr id="alerts-empty" class="hidden only:table-row">
              <td colspan={length(@columns) + 1} class="py-10 text-center text-base-content/50">
                <%= if @current_person do %>
                  No alerts for you or your team. New ones appear here the moment an event matches one of your rules.
                <% else %>
                  Pick who you are in the top bar to see your team's alerts.
                <% end %>
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
              <.cell
                :for={column <- @columns}
                column={column}
                alert={alert}
                dom_id={dom_id}
                owners={@owners}
              />
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end

  attr :sort, :any, required: true
  attr :key, :string, required: true
  attr :align_right, :boolean, default: false
  slot :inner_block, required: true

  defp sort_button(assigns) do
    ~H"""
    <button
      type="button"
      id={"sort-#{@key}"}
      phx-click="sort"
      phx-value-key={@key}
      title={"Sort by #{String.downcase(AlertTable.label(@key))}"}
      class={[
        "inline-flex items-center gap-1 uppercase tracking-wide hover:text-base-content",
        @align_right && "w-full justify-end",
        elem(@sort, 0) == @key && "text-base-content"
      ]}
    >
      {render_slot(@inner_block)}
      <.icon name={sort_icon(@sort, @key)} class="size-3.5" />
    </button>
    """
  end

  attr :column, :string, required: true
  attr :alert, :map, required: true
  attr :dom_id, :string, required: true
  attr :owners, :map, required: true

  defp cell(%{column: "title"} = assigns) do
    ~H"""
    <td class="max-w-0">
      <span class="flex items-center gap-2">
        <span class="flex w-1 shrink-0">
          <.rule_color_mark id={"#{@dom_id}-color"} alert={@alert} />
        </span>
        <.link
          navigate={~p"/alerts/#{@alert.id}"}
          class="min-w-0 truncate font-medium hover:underline"
        >
          {@alert.title}
        </.link>
      </span>
    </td>
    """
  end

  defp cell(%{column: "source"} = assigns) do
    ~H"""
    <td class="max-w-48 truncate text-base-content/70">
      {source(@alert)}
      <span :if={source_type(@alert)} class="text-xs text-base-content/40">
        · {source_type(@alert)}
      </span>
    </td>
    """
  end

  defp cell(%{column: "owner"} = assigns) do
    ~H"""
    <td class="max-w-48 truncate text-base-content/70">{AlertTable.owner_label(@owners, @alert)}</td>
    """
  end

  defp cell(%{column: "rule"} = assigns) do
    ~H"""
    <td class="max-w-48 truncate text-base-content/70">{(@alert.rule && @alert.rule.name) || "—"}</td>
    """
  end

  defp cell(%{column: "severity"} = assigns) do
    ~H"""
    <td><.severity_badge severity={@alert.severity} /></td>
    """
  end

  defp cell(%{column: "status"} = assigns) do
    ~H"""
    <td class="text-base-content/70">
      {status_label(@alert.status, not is_nil(@alert.closed_at))}
    </td>
    """
  end

  defp cell(%{column: "count"} = assigns) do
    ~H"""
    <td id={"#{@dom_id}-count"} class="text-right tabular-nums">{@alert.count}</td>
    """
  end

  defp cell(%{column: "first_seen"} = assigns) do
    ~H"""
    <td class="text-base-content/70">
      <.local_time id={"#{@dom_id}-first-seen"} at={@alert.first_seen} />
    </td>
    """
  end

  defp cell(%{column: "last_seen"} = assigns) do
    ~H"""
    <td class="text-base-content/70">
      <.local_time id={"#{@dom_id}-last-seen"} at={@alert.last_seen} />
    </td>
    """
  end

  attr :columns, :list, required: true

  defp columns_menu(assigns) do
    ~H"""
    <div id="columns-menu" class="relative" phx-hook=".ColumnLayout">
      <button
        id="columns-button"
        type="button"
        class="btn btn-sm btn-outline gap-1 font-normal"
        phx-click={JS.toggle(to: "#columns-panel")}
        aria-controls="columns-panel"
      >
        <.icon name="hero-view-columns-mini" class="size-4" /> Columns
      </button>
      <div
        id="columns-panel"
        class="absolute right-0 z-40 mt-1 hidden w-72 border border-base-300 bg-base-100 p-3 text-sm shadow-lg"
        phx-click-away={JS.hide(to: "#columns-panel")}
      >
        <p class="px-1 pb-2 text-xs text-base-content/50">Shown, in order</p>
        <ol id="columns-shown" class="space-y-0.5">
          <li
            :for={{column, index} <- Enum.with_index(@columns)}
            id={"columns-shown-#{column}"}
            class="flex items-center gap-2 px-1 py-1 hover:bg-base-200"
          >
            <input
              type="checkbox"
              class="checkbox checkbox-xs"
              checked
              disabled={AlertTable.required?(column)}
              phx-click="toggle_column"
              phx-value-id={column}
              aria-label={"Show #{AlertTable.label(column)}"}
            />
            <span class="flex-1">{AlertTable.label(column)}</span>
            <button
              type="button"
              id={"move-#{column}-up"}
              phx-click="move_column"
              phx-value-id={column}
              phx-value-direction="up"
              disabled={index == 0}
              class="btn btn-ghost btn-xs px-1"
              aria-label={"Move #{AlertTable.label(column)} left"}
            >
              <.icon name="hero-arrow-up-micro" class="size-4" />
            </button>
            <button
              type="button"
              id={"move-#{column}-down"}
              phx-click="move_column"
              phx-value-id={column}
              phx-value-direction="down"
              disabled={index == length(@columns) - 1}
              class="btn btn-ghost btn-xs px-1"
              aria-label={"Move #{AlertTable.label(column)} right"}
            >
              <.icon name="hero-arrow-down-micro" class="size-4" />
            </button>
          </li>
        </ol>
        <div :if={AlertTable.hidden(@columns) != []}>
          <p class="px-1 pt-3 pb-2 text-xs text-base-content/50">More columns</p>
          <ul id="columns-hidden" class="space-y-0.5">
            <li
              :for={column <- AlertTable.hidden(@columns)}
              id={"columns-hidden-#{column}"}
              class="flex items-center gap-2 px-1 py-1 hover:bg-base-200"
            >
              <input
                type="checkbox"
                class="checkbox checkbox-xs"
                phx-click="toggle_column"
                phx-value-id={column}
                aria-label={"Show #{AlertTable.label(column)}"}
              />
              <span class="flex-1 text-base-content/70">{AlertTable.label(column)}</span>
            </li>
          </ul>
        </div>
        <button
          type="button"
          id="reset-columns"
          phx-click="reset_columns"
          class="mt-3 px-1 text-xs underline text-base-content/60 hover:text-base-content"
        >
          Reset to default
        </button>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".ColumnLayout">
        const key = "minion:alert-columns"
        export default {
          mounted() {
            let saved = null
            try { saved = JSON.parse(localStorage.getItem(key) || "null") } catch (_error) {}
            if (Array.isArray(saved)) this.pushEvent("set_columns", {columns: saved})
            this.handleEvent("columns_saved", ({columns}) => {
              try { localStorage.setItem(key, JSON.stringify(columns)) } catch (_error) {}
            })
          }
        }
      </script>
    </div>
    """
  end
end
