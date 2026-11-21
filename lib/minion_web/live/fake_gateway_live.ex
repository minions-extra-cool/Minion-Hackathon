defmodule MinionWeb.FakeGatewayLive do
  use MinionWeb, :live_view

  alias Minion.FakeGateway

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: FakeGateway.subscribe()

    {:ok,
     socket
     |> assign(down?: FakeGateway.down?(), page_title: "Fake SMS & phone gateway")
     |> stream(:messages, FakeGateway.messages())}
  end

  @impl true
  def handle_event("toggle_down", _params, socket) do
    FakeGateway.set_down(not socket.assigns.down?)
    {:noreply, socket}
  end

  def handle_event("clear", _params, socket) do
    FakeGateway.clear()
    {:noreply, socket}
  end

  @impl true
  def handle_info({:gateway_message, message}, socket),
    do: {:noreply, stream_insert(socket, :messages, message, at: 0)}

  def handle_info({:gateway_down, down?}, socket), do: {:noreply, assign(socket, down?: down?)}

  def handle_info(:gateway_cleared, socket),
    do: {:noreply, stream(socket, :messages, [], reset: true)}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Fake SMS & phone gateway
        <:subtitle>
          Stands in for a real SMS/voice provider. Every SMS and phone call Minion sends lands here.
        </:subtitle>
        <:actions>
          <.button id="toggle-down" phx-click="toggle_down" variant={if @down?, do: "primary"}>
            {if @down?, do: "Bring gateway back up", else: "Take gateway down"}
          </.button>
          <.button id="clear" phx-click="clear">Clear</.button>
        </:actions>
      </.header>

      <div
        id="gateway-status"
        class={["alert mb-6", if(@down?, do: "alert-error", else: "alert-success")]}
      >
        <span :if={@down?}>Gateway is DOWN: every request is answered with 503.</span>
        <span :if={!@down?}>Gateway is UP and accepting messages.</span>
      </div>

      <div id="messages" phx-update="stream" class="space-y-2">
        <div id="messages-empty" class="hidden only:block text-base-content/60">
          No messages yet.
        </div>
        <div
          :for={{dom_id, message} <- @streams.messages}
          id={dom_id}
          class="card card-border bg-base-100 p-3"
        >
          <div class="flex items-center gap-3 text-sm">
            <span class={[
              "badge",
              if(message.channel == "phone", do: "badge-warning", else: "badge-info")
            ]}>
              {if message.channel == "phone", do: "Phone call", else: "SMS"}
            </span>
            <span class="font-mono">{message.to}</span>
            <span class="ml-auto text-base-content/60">
              {Calendar.strftime(message.received_at, "%H:%M:%S")} UTC
            </span>
          </div>
          <p class="mt-2">{message.text}</p>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
