defmodule MinionWeb.UnmatchedLive do
  use MinionWeb, :live_view

  import MinionWeb.AlertComponents

  alias Minion.Unmatched

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Unmatched.subscribe()

    {:ok,
     socket
     |> assign(page_title: "Unmatched events")
     |> stream(:shapes, Unmatched.list_recent())}
  end

  @impl true
  def handle_event("dismiss", %{"id" => id}, socket) do
    :ok = Unmatched.dismiss(id)
    {:noreply, socket}
  end

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

  defp fields_preview(%{paths: []}), do: "plain text"

  defp fields_preview(%{paths: paths}) do
    shown = paths |> Enum.map(&String.replace_prefix(&1, "payload.", "")) |> Enum.take(6)
    more = length(paths) - length(shown)
    Enum.join(shown, ", ") <> if(more > 0, do: " +#{more} more", else: "")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active={:dashboard}>
      <h1 class="text-2xl font-semibold tracking-tight">Live feed</h1>
      <.feed_tabs active={:unmatched} />

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
                  phx-click="dismiss"
                  phx-value-id={shape.id}
                  class="btn btn-xs btn-ghost"
                >
                  Dismiss
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </Layouts.app>
    """
  end
end
