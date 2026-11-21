defmodule MinionWeb.AlertLive do
  use MinionWeb, :live_view

  import MinionWeb.AlertComponents

  alias Minion.Alerts
  alias Minion.Rules.Template

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    alert = Alerts.get_alert!(id)
    if connected?(socket), do: Alerts.subscribe(alert)

    {:ok,
     socket
     |> assign(page_title: alert.title, alert: alert, owner: Alerts.owner_name(alert))
     |> stream(:deliveries, Alerts.list_deliveries(alert))}
  end

  @impl true
  def handle_event("acknowledge", _params, socket) do
    socket.assigns.alert.id
    |> Alerts.acknowledge()
    |> after_transition(socket, "Someone already acknowledged or resolved this alert.")
  end

  def handle_event("resolve", _params, socket) do
    socket.assigns.alert.id
    |> Alerts.resolve()
    |> after_transition(socket, "This alert is already resolved.")
  end

  defp after_transition({:ok, alert}, socket, _conflict_message),
    do: {:noreply, assign(socket, :alert, %{alert | rule: socket.assigns.alert.rule})}

  defp after_transition({:error, _reason}, socket, conflict_message) do
    {:noreply,
     socket
     |> assign(:alert, Alerts.get_alert!(socket.assigns.alert.id))
     |> put_flash(:info, conflict_message)}
  end

  @impl true
  def handle_info({:alert, _event, %{id: id} = alert}, %{assigns: %{alert: %{id: id}}} = socket),
    do: {:noreply, assign(socket, :alert, %{alert | rule: socket.assigns.alert.rule})}

  def handle_info({:alert, _event, _other_alert}, socket), do: {:noreply, socket}

  def handle_info({:delivery, %{alert_id: id}}, %{assigns: %{alert: %{id: id}}} = socket),
    do:
      {:noreply,
       stream(socket, :deliveries, Alerts.list_deliveries(socket.assigns.alert), reset: true)}

  def handle_info({:delivery, _other}, socket), do: {:noreply, socket}

  defp fields(%{rule: %{present: %{"fields" => paths}}} = alert) when is_list(paths) do
    Enum.map(paths, &{&1, Template.render("{{#{&1}}}", alert.sample_event)})
  end

  defp fields(_alert), do: []

  defp delivery_icon(:delivered), do: "hero-check-circle-micro"
  defp delivery_icon(:pending), do: "hero-arrow-path-micro"
  defp delivery_icon(:failed), do: "hero-x-circle-micro"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:dashboard}>
      <.link
        navigate={~p"/"}
        id="back-to-dashboard"
        class="inline-flex items-center gap-1 text-sm text-base-content/60 hover:text-base-content"
      >
        <.icon name="hero-arrow-left-mini" class="size-4" /> Dashboard
      </.link>

      <div class="flex flex-wrap items-start justify-between gap-4">
        <div class="flex items-start gap-3">
          <span class="pt-2.5">
            <.status_light
              status={@alert.status}
              severity={@alert.severity}
              closed={not is_nil(@alert.closed_at)}
            />
          </span>
          <div>
            <h1 id="alert-title" class="text-2xl font-semibold tracking-tight">{@alert.title}</h1>
            <p class="mt-1 text-sm text-base-content/60">
              {status_label(@alert.status, not is_nil(@alert.closed_at))}
            </p>
          </div>
        </div>
        <div class="flex gap-2">
          <button
            :if={@alert.status == :open}
            id="acknowledge"
            phx-click="acknowledge"
            class="btn btn-sm btn-outline"
          >
            Acknowledge
          </button>
          <button
            :if={@alert.status != :resolved}
            id="resolve"
            phx-click="resolve"
            class="btn btn-sm btn-primary"
          >
            Resolve
          </button>
        </div>
      </div>

      <dl id="alert-facts" class="grid grid-cols-[9rem_minmax(0,1fr)] text-sm">
        <.fact label="Status">
          <span id="alert-status" data-status={@alert.status}>
            {status_label(@alert.status, not is_nil(@alert.closed_at))}
          </span>
        </.fact>
        <.fact label="Severity"><.severity_badge severity={@alert.severity} /></.fact>
        <.fact :if={@alert.body not in [nil, ""]} label="Body">
          <p id="alert-body" class="whitespace-pre-line">{@alert.body}</p>
        </.fact>
        <.fact :for={{path, value} <- fields(@alert)} label={path |> String.split(".") |> List.last()}>
          <span class="font-mono text-xs">{value}</span>
          <span class="ml-2 text-xs text-base-content/40">{path}</span>
        </.fact>
        <.fact label="Source">
          {source(@alert)}
          <span :if={source_type(@alert)} class="text-base-content/50">via {source_type(@alert)}</span>
        </.fact>
        <.fact label="Rule">
          <span class="inline-flex flex-wrap items-center gap-3">
            {(@alert.rule && @alert.rule.name) || "deleted rule"}
            <.rule_color_swatch alert={@alert} />
          </span>
        </.fact>
        <.fact label="Owner">
          {@owner || "unknown"}
          <span class="text-base-content/50">({@alert.owner_type})</span>
        </.fact>
        <.fact label="Events">
          <span id="alert-count" class="tabular-nums">{@alert.count}</span>
        </.fact>
        <.fact label="First event">
          <.local_time id="alert-first-seen" at={@alert.first_seen} format="absolute" />
        </.fact>
        <.fact label="Last event">
          <.local_time id="alert-last-seen" at={@alert.last_seen} format="absolute" />
          <span class="text-base-content/50">
            (<.local_time id="alert-last-seen-relative" at={@alert.last_seen} />)
          </span>
        </.fact>
        <.fact :if={@alert.closed_at} label="Quiet since">
          <.local_time id="alert-closed-at" at={@alert.closed_at} format="absolute" />
          <span class="text-base-content/50">
            · the next matching event opens a new alert
          </span>
        </.fact>
        <.fact label="Deliveries">
          <ul id="deliveries" phx-update="stream" class="space-y-1.5">
            <li id="deliveries-empty" class="hidden only:block text-base-content/50">
              Nobody was notified: this alert is shown in the feed only.
            </li>
            <li
              :for={{dom_id, delivery} <- @streams.deliveries}
              id={dom_id}
              class="flex flex-wrap items-center gap-2"
            >
              <span class="inline-flex w-24 items-center gap-1 text-base-content/70">
                <.icon
                  name={delivery_icon(delivery.status)}
                  class={[
                    "size-4",
                    delivery.status == :delivered && "text-success",
                    delivery.status == :pending && "text-base-content/50",
                    delivery.status == :failed && "text-base-content"
                  ]}
                />
                {delivery.status}
              </span>
              <span class="font-medium">{delivery.person.name}</span>
              <span class="text-base-content/60">by {delivery.channel}</span>
              <span :if={delivery.attempts > 1} class="text-xs text-base-content/50">
                {delivery.attempts} attempts
              </span>
              <span :if={delivery.last_error} class="font-mono text-xs text-base-content/50">
                {delivery.last_error}
              </span>
            </li>
          </ul>
        </.fact>
        <.fact label="Raw event">
          <details id="alert-sample-event">
            <summary class="cursor-pointer text-base-content/60 hover:text-base-content">
              Show the first event that opened this alert
            </summary>
            <pre class="mt-2 overflow-x-auto rounded-box bg-base-200 p-4 font-mono text-xs">{Jason.encode!(@alert.sample_event, pretty: true)}</pre>
          </details>
          <.link
            id="rule-from-event"
            navigate={~p"/rules/new?#{[from_alert: @alert.id]}"}
            class="mt-2 inline-flex items-center gap-1 text-sm underline hover:text-base-content"
          >
            <.icon name="hero-plus-mini" class="size-4" /> Create a rule from this event
          </.link>
        </.fact>
      </dl>
    </Layouts.app>
    """
  end

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp fact(assigns) do
    ~H"""
    <dt class="border-r border-base-300 py-2.5 pr-5 text-right text-base-content/55">{@label}</dt>
    <dd class="min-w-0 py-2.5 pl-5">{render_slot(@inner_block)}</dd>
    """
  end
end
