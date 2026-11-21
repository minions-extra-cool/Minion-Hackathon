defmodule Minion.FakeGateway do
  use GenServer

  @topic "fake_gateway"
  @max_messages 200
  @channels ["sms", "phone"]

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  def subscribe, do: Phoenix.PubSub.subscribe(Minion.PubSub, @topic)

  def receive_message(%{"channel" => channel, "to" => to, "text" => text})
      when channel in @channels and is_binary(to) and to != "" and is_binary(text),
      do: GenServer.call(__MODULE__, {:receive, %{channel: channel, to: to, text: text}})

  def receive_message(_invalid), do: {:error, :invalid_message}

  def messages, do: GenServer.call(__MODULE__, :messages)

  def down?, do: GenServer.call(__MODULE__, :down?)

  def set_down(down?) when is_boolean(down?), do: GenServer.call(__MODULE__, {:set_down, down?})

  def clear, do: GenServer.call(__MODULE__, :clear)

  @impl true
  def init(:ok), do: {:ok, %{down?: false, messages: []}}

  @impl true
  def handle_call({:receive, _message}, _from, %{down?: true} = state),
    do: {:reply, {:error, :down}, state}

  def handle_call({:receive, message}, _from, state) do
    message =
      Map.merge(message, %{
        id: System.unique_integer([:positive, :monotonic]),
        received_at: DateTime.utc_now()
      })

    broadcast({:gateway_message, message})

    {:reply, {:ok, message},
     %{state | messages: Enum.take([message | state.messages], @max_messages)}}
  end

  def handle_call(:messages, _from, state), do: {:reply, state.messages, state}

  def handle_call(:down?, _from, state), do: {:reply, state.down?, state}

  def handle_call({:set_down, down?}, _from, state) do
    broadcast({:gateway_down, down?})
    {:reply, :ok, %{state | down?: down?}}
  end

  def handle_call(:clear, _from, state) do
    broadcast(:gateway_cleared)
    {:reply, :ok, %{state | messages: []}}
  end

  defp broadcast(event), do: Phoenix.PubSub.broadcast(Minion.PubSub, @topic, event)
end
