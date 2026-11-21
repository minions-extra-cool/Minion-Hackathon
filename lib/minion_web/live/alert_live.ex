defmodule MinionWeb.AlertLive do
  use MinionWeb, :live_view

  import MinionWeb.AlertComponents

  alias Minion.AI.Summary
  alias Minion.{Alerts, Runbooks}
  alias Minion.Rules.Template

  alias Phoenix.LiveView.AsyncResult

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    alert = Alerts.get_alert!(id)
    if connected?(socket), do: Alerts.subscribe(alert)

    {:ok,
     socket
     |> assign(
       page_title: alert.title,
       alert: alert,
       owner: Alerts.owner_name(alert),
       runbook: Runbooks.get_for_rule(alert.rule_id),
       resolve_step: nil,
       runbook_expanded: false,
       ai_summary: %AsyncResult{}
     )
     |> stream(:deliveries, Alerts.list_deliveries(alert))}
  end

  @impl true
  def handle_event("acknowledge", _params, socket) do
    socket.assigns.alert.id
    |> Alerts.acknowledge()
    |> after_transition(socket, "Someone already acknowledged or resolved this alert.")
  end

  def handle_event("ask_resolve", _params, socket),
    do: {:noreply, assign(socket, :resolve_step, :confirm)}

  def handle_event("expand_runbook", _params, socket),
    do: {:noreply, assign(socket, :runbook_expanded, true)}

  def handle_event("collapse_runbook", _params, socket),
    do: {:noreply, assign(socket, :runbook_expanded, false)}

  def handle_event("close_resolve", _params, socket),
    do: {:noreply, assign(socket, :resolve_step, nil)}

  def handle_event("confirm_resolve", _params, socket) do
    case Alerts.resolve(socket.assigns.alert.id) do
      {:ok, _alert} = resolved ->
        after_transition(resolved, assign(socket, :resolve_step, :resolved), nil)

      error ->
        after_transition(
          error,
          assign(socket, :resolve_step, nil),
          "This alert is already resolved."
        )
    end
  end

  def handle_event("summarize", _params, socket) do
    alert = socket.assigns.alert

    socket =
      socket
      |> assign(ai_summary: AsyncResult.loading())
      |> assign(ai_summary_html: nil)

    {:noreply, start_async(socket, :ai_summary, fn -> Summary.summarize(alert) end)}
  end

  @impl true
  def handle_async(:ai_summary, {:ok, {:ok, text}}, socket),
    do:
      {:noreply,
       socket
       |> assign(ai_summary: AsyncResult.ok(socket.assigns.ai_summary, text))
       |> assign(ai_summary_html: MinionWeb.Markdown.to_html(text))}

  def handle_async(:ai_summary, {:ok, {:error, reason}}, socket),
    do:
      {:noreply,
       socket
       |> assign(ai_summary: AsyncResult.failed(socket.assigns.ai_summary, reason))
       |> assign(ai_summary_html: nil)}

  def handle_async(:ai_summary, {:exit, reason}, socket),
    do:
      {:noreply,
       socket
       |> assign(ai_summary: AsyncResult.failed(socket.assigns.ai_summary, {:exit, reason}))
       |> assign(ai_summary_html: nil)}

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

  defp channel_label(:sms), do: "SMS"
  defp channel_label(:phone), do: "phone call"
  defp channel_label(channel), do: to_string(channel)

  defp summarize_label(%AsyncResult{loading: true}), do: "Summarising…"
  defp summarize_label(%AsyncResult{ok?: true}), do: "Regenerate summary"
  defp summarize_label(_result), do: "Summarise with Gemini"

  defp describe_failure(:not_configured),
    do: "Gemini is not configured. Set GEMINI_API_KEY and restart the server."

  defp describe_failure({:unreachable, message}), do: "Gemini could not be reached: #{message}"

  defp describe_failure({:api_error, status, message}),
    do: "Gemini answered #{status}: #{message}"

  defp describe_failure(_reason), do: "Could not summarise this alert."

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
            phx-click="ask_resolve"
            class="btn btn-sm btn-primary"
          >
            Resolve
          </button>
        </div>
      </div>

      <div class={[
        "grid gap-8",
        @alert.status != :resolved && "lg:grid-cols-[minmax(0,3fr)_minmax(0,2fr)]"
      ]}>
        <dl id="alert-facts" class="grid h-fit grid-cols-[9rem_minmax(0,1fr)] text-sm">
          <.fact label="Status">
            <span id="alert-status" data-status={@alert.status}>
              {status_label(@alert.status, not is_nil(@alert.closed_at))}
            </span>
          </.fact>
          <.fact label="Severity"><.severity_badge severity={@alert.severity} /></.fact>
          <.fact :if={@alert.body not in [nil, ""]} label="Body">
            <p id="alert-body" class="whitespace-pre-line">{@alert.body}</p>
          </.fact>
          <.fact
            :for={{path, value} <- fields(@alert)}
            label={path |> String.split(".") |> List.last()}
          >
            <span class="font-mono text-xs">{value}</span>
            <span class="ml-2 text-xs text-base-content/40">{path}</span>
          </.fact>
          <.fact label="Source">
            {source(@alert)}
            <span :if={source_type(@alert)} class="text-base-content/50">via {source_type(@alert)}</span>
          </.fact>
          <.fact label="Rule">
            <span class="inline-flex flex-wrap items-center gap-3">
              <.link
                :if={@alert.rule}
                navigate={~p"/rules/#{@alert.rule.id}"}
                id="alert-rule-link"
                class="underline decoration-base-content/30 hover:decoration-base-content"
              >
                {@alert.rule.name}
              </.link>
              <span :if={is_nil(@alert.rule)}>deleted rule</span>
              <.rule_color_swatch alert={@alert} />
            </span>
          </.fact>
          <.fact :if={@alert.status == :resolved and @alert.rule} label="Runbook">
            <.runbook_link alert={@alert} runbook={@runbook} />
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
                <span class="text-base-content/60">by {channel_label(delivery.channel)}</span>
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

        <div :if={@alert.status != :resolved} class="relative order-first lg:order-none">
          <.runbook_panel alert={@alert} runbook={@runbook} />
        </div>
      </div>

      <section id="ai-summary" class="mt-8 border-t border-base-300 pt-6">
        <div class="flex flex-wrap items-center justify-between gap-3">
          <h2 class="text-sm font-semibold uppercase tracking-wider text-base-content/60">
            AI summary
          </h2>
          <button
            id="summarize-alert"
            phx-click="summarize"
            disabled={@ai_summary.loading}
            class="btn btn-sm btn-primary"
          >
            <.icon
              :if={@ai_summary.loading}
              name="hero-arrow-path-mini"
              class="size-4 animate-spin"
            />
            {summarize_label(@ai_summary)}
          </button>
        </div>

        <div
          :if={@ai_summary.ok?}
          id="ai-summary-text"
          class={[
            "mt-3 w-full max-w-4xl text-sm leading-relaxed text-base-content/90 [overflow-wrap:anywhere]",
            "[&_h1]:mt-4 [&_h1]:text-lg [&_h1]:font-semibold",
            "[&_h2]:mt-4 [&_h2]:text-base [&_h2]:font-semibold",
            "[&_h3]:mt-3 [&_h3]:text-sm [&_h3]:font-semibold",
            "[&_p]:my-2",
            "[&_ul]:my-2 [&_ul]:list-disc [&_ul]:space-y-1 [&_ul]:pl-5",
            "[&_ol]:my-2 [&_ol]:list-decimal [&_ol]:space-y-1 [&_ol]:pl-5",
            "[&_li]:leading-relaxed",
            "[&_code]:bg-base-200 [&_code]:px-1 [&_code]:py-0.5 [&_code]:font-mono [&_code]:text-xs",
            "[&_pre]:my-2 [&_pre]:overflow-x-auto [&_pre]:border [&_pre]:border-base-300 [&_pre]:bg-base-200 [&_pre]:p-3",
            "[&_pre_code]:bg-transparent [&_pre_code]:p-0",
            "[&_a]:underline [&_a]:decoration-primary [&_a]:break-words hover:[&_a]:text-primary",
            "[&_blockquote]:my-2 [&_blockquote]:border-l-2 [&_blockquote]:border-primary [&_blockquote]:pl-3 [&_blockquote]:text-base-content/70",
            "[&_hr]:my-4 [&_hr]:border-base-300"
          ]}
        >
          {@ai_summary_html}
        </div>

        <p :if={@ai_summary.failed} id="ai-summary-error" class="mt-3 text-sm text-error">
          {describe_failure(@ai_summary.failed)}
        </p>
      </section>

      <div
        :if={@runbook_expanded}
        id="runbook-dialog"
        phx-hook=".PageScrollLock"
        role="dialog"
        aria-modal="true"
        aria-labelledby="runbook-dialog-title"
        phx-window-keydown="collapse_runbook"
        phx-key="Escape"
        class="fixed inset-0 z-50 flex items-center justify-center bg-base-content/20 p-4 sm:p-8"
      >
        <div
          class="flex h-full max-h-[90vh] w-full max-w-4xl flex-col border-l-4 border-primary bg-base-100 shadow-xl"
          phx-click-away="collapse_runbook"
        >
          <div class="flex items-center justify-between gap-6 border-b border-base-300 px-8 py-5">
            <h2 id="runbook-dialog-title" class="inline-flex items-center gap-2 text-lg font-semibold">
              <.icon name="hero-book-open-mini" class="size-5" /> What to do
            </h2>
            <div class="flex items-center gap-5 text-sm">
              <.runbook_link
                :if={@alert.rule}
                alert={@alert}
                runbook={@runbook}
                id="runbook-dialog-edit"
              />
              <button
                id="runbook-dialog-close"
                type="button"
                phx-click="collapse_runbook"
                aria-label="Close"
                class="text-base-content/50 transition-colors hover:text-base-content"
              >
                <.icon name="hero-x-mark-mini" class="size-5" />
              </button>
            </div>
          </div>
          <div
            id="runbook-dialog-body"
            class="space-y-3 overflow-y-auto overscroll-contain px-8 py-6 leading-relaxed"
          >
            {runbook_html(@runbook, @alert)}
          </div>
        </div>
      </div>

      <div
        :if={@resolve_step}
        id="resolve-confirm-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="resolve-dialog-title"
        phx-window-keydown="close_resolve"
        phx-key="Escape"
        class="fixed inset-0 z-50 flex items-center justify-center overflow-y-auto bg-base-content/20 p-4"
      >
        <div
          class="m-auto w-full max-w-sm bg-base-100 p-8 shadow-xl"
          phx-click-away="close_resolve"
        >
          <div class="flex items-start justify-between gap-6">
            <h2 id="resolve-dialog-title" class="text-lg font-semibold tracking-tight">
              <span :if={@resolve_step == :confirm}>Resolve this alert?</span>
              <span
                :if={@resolve_step == :resolved}
                id="resolve-done-title"
                class="inline-flex items-center gap-2"
              >
                <.icon name="hero-check-circle" class="size-6 text-success" /> Alert resolved
              </span>
            </h2>
            <button
              id="resolve-close"
              type="button"
              phx-click="close_resolve"
              aria-label="Close"
              class="text-base-content/50 transition-colors hover:text-base-content"
            >
              <.icon name="hero-x-mark-mini" class="size-5" />
            </button>
          </div>

          <div :if={@resolve_step == :confirm}>
            <p class="mt-3 text-sm text-base-content/60">
              {@alert.title} will be marked as resolved. The next matching event opens a new alert.
            </p>
            <div class="mt-7 flex justify-end gap-3">
              <button
                id="resolve-cancel"
                type="button"
                phx-click="close_resolve"
                class="btn btn-sm btn-outline"
              >
                Cancel
              </button>
              <button
                id="resolve-confirm"
                type="button"
                phx-click="confirm_resolve"
                class="btn btn-sm btn-primary"
              >
                Yes, resolve
              </button>
            </div>
          </div>

          <div :if={@resolve_step == :resolved} id="resolve-runbook-prompt">
            <p :if={@alert.rule} class="mt-3 text-sm text-base-content/60">
              {if Runbooks.blank?(@runbook),
                do:
                  "Would you like to write a runbook? Note what fixed it, so the next person who gets this alert knows what to do.",
                else:
                  "Would you like to update the runbook? Note anything that was missing or wrong while it's fresh."}
            </p>
            <div class="mt-7 flex justify-end gap-3">
              <button
                id="resolve-done"
                type="button"
                phx-click="close_resolve"
                class="btn btn-sm btn-outline"
              >
                {if @alert.rule, do: "Not now", else: "Done"}
              </button>
              <.link
                :if={@alert.rule}
                id="resolve-update-runbook"
                navigate={runbook_path(@alert)}
                class="btn btn-sm btn-primary"
              >
                {if Runbooks.blank?(@runbook), do: "Write runbook", else: "Update runbook"}
              </.link>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  attr :alert, :map, required: true
  attr :runbook, :map, default: nil

  defp runbook_panel(assigns) do
    ~H"""
    <section
      id="runbook"
      aria-labelledby="runbook-title"
      class="flex flex-col border-l-4 border-primary bg-base-200 p-5 lg:absolute lg:inset-0"
    >
      <div class="flex flex-wrap items-baseline justify-between gap-3">
        <h2 id="runbook-title" class="inline-flex items-center gap-2 font-semibold">
          <.icon name="hero-book-open-mini" class="size-4" /> What to do
        </h2>
        <span :if={@alert.rule} class="text-xs text-base-content/55">
          <span :if={@runbook && @runbook.id}>
            Updated <.local_time id="runbook-updated" at={@runbook.updated_at} /> ·
          </span>
          <.runbook_link alert={@alert} runbook={@runbook} />
        </span>
      </div>
      <div
        :if={not Runbooks.blank?(@runbook)}
        id="runbook-clip"
        phx-hook=".RunbookOverflow"
        class="group relative mt-3 min-h-0 flex-1 overflow-hidden"
      >
        <div id="runbook-body" class="space-y-3 text-sm leading-relaxed">
          {runbook_html(@runbook, @alert)}
        </div>
        <div class="pointer-events-none absolute inset-x-0 bottom-0 hidden h-20 bg-linear-to-t from-base-200 group-data-overflowing:block">
        </div>
        <button
          id="runbook-expand"
          type="button"
          phx-click="expand_runbook"
          class="btn btn-xs btn-outline absolute right-0 bottom-0 hidden bg-base-100 group-data-overflowing:inline-flex"
        >
          <.icon name="hero-arrows-pointing-out-micro" class="size-3.5" /> Expand
        </button>
      </div>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".PageScrollLock">
        export default {
          mounted() {
            const page = document.documentElement
            const scrollbarWidth = window.innerWidth - page.clientWidth
            this.previous = {overflow: page.style.overflow, paddingRight: page.style.paddingRight}
            page.style.overflow = "hidden"
            page.style.paddingRight = `${scrollbarWidth}px`
          },
          destroyed() {
            Object.assign(document.documentElement.style, this.previous)
          }
        }
      </script>
      <script :type={Phoenix.LiveView.ColocatedHook} name=".RunbookOverflow">
        export default {
          mounted() {
            this.observer = new ResizeObserver(() => this.check())
            this.observer.observe(this.el)
            this.observer.observe(this.el.firstElementChild)
            this.check()
          },
          updated() { this.check() },
          destroyed() { this.observer.disconnect() },
          check() {
            this.el.toggleAttribute("data-overflowing", this.el.scrollHeight > this.el.clientHeight + 1)
          }
        }
      </script>
      <p
        :if={Runbooks.blank?(@runbook)}
        id="runbook-missing"
        class="mt-3 text-sm text-base-content/60"
      >
        No runbook for this rule yet. Once you've fixed it, write down what you did so the next person knows.
      </p>
    </section>
    """
  end

  defp runbook_html(runbook, alert),
    do: MinionWeb.Markdown.to_html(Runbooks.render(runbook, alert.sample_event))

  attr :alert, :map, required: true
  attr :runbook, :map, default: nil
  attr :id, :string, default: "runbook-edit"

  defp runbook_link(assigns) do
    ~H"""
    <.link
      id={@id}
      navigate={runbook_path(@alert)}
      class="underline hover:text-base-content"
    >
      {if Runbooks.blank?(@runbook), do: "Write a runbook", else: "Edit runbook"}
    </.link>
    """
  end

  defp runbook_path(alert), do: ~p"/rules/#{alert.rule_id}/runbook?#{[from_alert: alert.id]}"

  attr :label, :string, required: true
  slot :inner_block, required: true

  defp fact(assigns) do
    ~H"""
    <dt class="border-r border-base-300 py-2.5 pr-5 text-right text-base-content/55">{@label}</dt>
    <dd class="min-w-0 py-2.5 pl-5">{render_slot(@inner_block)}</dd>
    """
  end
end
