defmodule MinionWeb.RunbookLive do
  use MinionWeb, :live_view

  import MinionWeb.AlertComponents

  alias Minion.{Alerts, Rules, Runbooks}

  @impl true
  def mount(%{"id" => rule_id} = params, _session, socket) do
    rule = Rules.get_rule!(rule_id)
    runbook = Runbooks.get_or_build_for_rule(rule.id)
    alert = from_alert(params["from_alert"], rule)

    {:ok,
     socket
     |> assign(
       page_title: "Runbook: #{rule.name}",
       rule: rule,
       runbook: runbook,
       alert: alert,
       body: runbook.body
     )
     |> assign_form(Runbooks.change_runbook(runbook))}
  end

  defp from_alert(nil, _rule), do: nil

  defp from_alert(alert_id, rule) do
    with {:ok, uuid} <- Ecto.UUID.cast(alert_id),
         %{rule_id: rule_id} = alert when rule_id == rule.id <- Alerts.get_alert(uuid) do
      alert
    else
      _ -> nil
    end
  end

  defp assign_form(socket, changeset), do: assign(socket, :form, to_form(changeset))

  @impl true
  def handle_event("change", %{"runbook" => params}, socket) do
    changeset =
      socket.assigns.runbook
      |> Runbooks.change_runbook(params)
      |> Map.put(:action, :validate)

    {:noreply, socket |> assign(:body, params["body"] || "") |> assign_form(changeset)}
  end

  def handle_event("save", %{"runbook" => params}, socket) do
    case Runbooks.save_runbook(socket.assigns.runbook, params) do
      {:ok, _runbook} ->
        {:noreply,
         socket
         |> put_flash(:info, "Runbook saved.")
         |> push_navigate(to: back_path(socket.assigns))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp back_path(%{alert: %{id: alert_id}}), do: ~p"/alerts/#{alert_id}"
  defp back_path(%{rule: rule}), do: ~p"/rules/#{rule.id}"

  defp back_label(%{alert: nil}), do: "Rule"
  defp back_label(_assigns), do: "Alert"

  defp preview(%{alert: nil, body: body}), do: body

  defp preview(%{alert: alert, runbook: runbook, body: body}),
    do: Runbooks.render(%{runbook | body: body}, alert.sample_event)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={if @alert, do: :dashboard, else: :rules}>
      <.link
        navigate={back_path(assigns)}
        id="runbook-back"
        class="inline-flex items-center gap-1 text-sm text-base-content/60 hover:text-base-content"
      >
        <.icon name="hero-arrow-left-mini" class="size-4" /> {back_label(assigns)}
      </.link>

      <div>
        <h1 class="text-2xl font-semibold tracking-tight">Runbook</h1>
        <p class="mt-1 text-sm text-base-content/60">
          For alerts from the rule <span id="runbook-rule-name" class="font-medium text-base-content">{@rule.name}</span>.
          <span :if={@runbook.id} id="runbook-updated-at">
            Last updated <.local_time id="runbook-updated" at={@runbook.updated_at} />.
          </span>
        </p>
      </div>

      <div class="grid gap-8 lg:grid-cols-2">
        <.form for={@form} id="runbook-form" phx-change="change" phx-submit="save">
          <.input
            field={@form[:body]}
            type="textarea"
            label="Steps"
            rows="18"
            spellcheck="false"
            class="textarea w-full font-mono text-sm leading-relaxed"
            placeholder="1. Check free space on {{payload.host}}\n2. Clear /var/log if it is over 80%\n3. If it fills again within an hour, page the on-call person"
          />
          <p class="mt-2 text-xs text-base-content/55">
            Write it however your team does: numbered steps, Markdown, free text or a wiki link.
            <code class="font-mono">{"{{payload.host}}"}</code>
            is replaced by the value from the alert's event.
          </p>
          <div class="mt-6 flex justify-end gap-3">
            <.link navigate={back_path(assigns)} id="runbook-cancel" class="btn btn-sm btn-outline">
              Cancel
            </.link>
            <button id="runbook-save" type="submit" class="btn btn-sm btn-primary">
              Save runbook
            </button>
          </div>
        </.form>

        <section aria-labelledby="runbook-preview-title">
          <h2 id="runbook-preview-title" class="text-sm font-medium text-base-content/70">
            {if @alert, do: "As shown on #{@alert.title}", else: "Preview"}
          </h2>
          <div class="mt-2 min-h-24 border border-base-300 bg-base-200 p-4 text-sm">
            <p :if={String.trim(@body) == ""} class="text-base-content/50">Nothing written yet.</p>
            <p id="runbook-preview" class="whitespace-pre-line" phx-no-format>{preview(assigns)}</p>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
