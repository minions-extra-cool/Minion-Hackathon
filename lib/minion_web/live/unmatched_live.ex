defmodule MinionWeb.UnmatchedLive do
  use MinionWeb, :live_view

  import MinionWeb.AlertComponents

  alias Minion.Unmatched

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Unmatched.subscribe()

    {:ok,
     socket
     |> assign(page_title: "Unmatched events", dismissing: nil)
     |> stream(:shapes, Unmatched.list_recent())}
  end

  @impl true
  def handle_event("ask_dismiss", %{"id" => id, "label" => label}, socket),
    do: {:noreply, assign(socket, dismissing: %{id: id, label: label})}

  def handle_event("cancel_dismiss", _params, socket),
    do: {:noreply, assign(socket, dismissing: nil)}

  def handle_event("confirm_dismiss", _params, %{assigns: %{dismissing: %{id: id}}} = socket) do
    :ok = Unmatched.dismiss(id)
    {:noreply, assign(socket, dismissing: nil)}
  end

  def handle_event("confirm_dismiss", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_info({:unmatched, shape}, socket),
    do: {:noreply, stream_insert(socket, :shapes, shape, at: 0)}

  def handle_info({:dismissed, id}, socket),
    do: {:noreply, stream_delete_by_dom_id(socket, :shapes, "shapes-#{id}")}

  defp kind(shape) do
    case Unmatched.identifying_field(shape) do
      {field, value} -> {String.replace_prefix(field, "payload.", ""), value}
      nil -> nil
    end
  end

  defp label(shape) do
    case kind(shape) do
      {_field, value} -> "#{value} from #{shape.source}"
      nil -> shape.source
    end
  end

  defp fields_preview(%{paths: [], sample_event: %{"payload" => text}}) when is_binary(text),
    do: "text: " <> String.slice(text, 0, 120)

  defp fields_preview(%{paths: []}), do: "no fields"

  defp fields_preview(%{paths: paths}) do
    shown = paths |> Enum.map(&String.replace_prefix(&1, "payload.", "")) |> Enum.take(6)
    more = length(paths) - length(shown)
    Enum.join(shown, ", ") <> if(more > 0, do: " +#{more} more", else: "")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_person={@current_person} people={@people} active={:dashboard}>
      <.feed_header active={:unmatched} />

      <p class="text-sm text-base-content/60">
        Events no enabled rule matched, grouped by source and shape. Turn any of them into alerts with a rule.
      </p>

      <div class="overflow-x-auto border border-base-300 bg-base-100">
        <table id="unmatched-table" class="table table-sm">
          <thead>
            <tr class="text-xs uppercase tracking-wide text-base-content/50">
              <th class="w-48">Source</th>
              <th>Event</th>
              <th class="w-16 text-right">Events</th>
              <th class="w-32">Last seen</th>
              <th class="w-48"><span class="sr-only">Actions</span></th>
            </tr>
          </thead>
          <tbody id="shapes" phx-update="stream">
            <tr id="shapes-empty" class="hidden only:table-row">
              <td colspan="5" class="py-10 text-center text-base-content/50">
                Every recent event matched a rule. Events that match none show up here.
              </td>
            </tr>
            <tr :for={{dom_id, shape} <- @streams.shapes} id={dom_id} class="hover:bg-base-200">
              <td class="truncate">
                {shape.source}
                <span :if={shape.source_type} class="text-xs text-base-content/40">· {shape.source_type}</span>
              </td>
              <td class="max-w-0">
                <div :if={kind(shape)} class="truncate font-medium">
                  {elem(kind(shape), 1)}
                  <span class="text-xs font-normal text-base-content/40">{elem(kind(shape), 0)}</span>
                </div>
                <div class="truncate font-mono text-xs text-base-content/60">
                  {fields_preview(shape)}
                </div>
              </td>
              <td id={"#{dom_id}-count"} class="text-right tabular-nums">{shape.count}</td>
              <td class="text-base-content/70">
                <.local_time id={"#{dom_id}-last-seen"} at={shape.last_seen} />
              </td>
              <td class="text-right">
                <.link
                  id={"#{dom_id}-create-rule"}
                  navigate={~p"/rules/new?#{[from_unmatched: shape.id]}"}
                  class="btn btn-xs btn-primary"
                >
                  Create rule
                </.link>
                <button
                  id={"#{dom_id}-dismiss"}
                  type="button"
                  phx-click="ask_dismiss"
                  phx-value-id={shape.id}
                  phx-value-label={label(shape)}
                  class="btn btn-xs btn-ghost"
                >
                  Dismiss
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div
        :if={@dismissing}
        id="dismiss-dialog"
        role="dialog"
        aria-modal="true"
        aria-labelledby="dismiss-dialog-title"
        phx-window-keydown="cancel_dismiss"
        phx-key="Escape"
        class="fixed inset-0 z-50 flex items-center justify-center bg-base-content/20 p-4"
      >
        <div class="w-full max-w-md bg-base-100 p-8 shadow-xl" phx-click-away="cancel_dismiss">
          <h2 id="dismiss-dialog-title" class="text-lg font-semibold tracking-tight">
            Dismiss {@dismissing.label}?
          </h2>
          <p class="mt-3 text-sm text-base-content/60">
            It comes back if a matching event arrives again.
          </p>
          <div class="mt-7 flex justify-end gap-3">
            <button
              id="dismiss-cancel"
              type="button"
              phx-click="cancel_dismiss"
              class="btn btn-sm btn-outline"
            >
              Cancel
            </button>
            <button
              id="dismiss-confirm"
              type="button"
              phx-click="confirm_dismiss"
              class="btn btn-sm btn-primary"
            >
              Dismiss
            </button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
