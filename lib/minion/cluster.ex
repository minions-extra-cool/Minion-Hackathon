defmodule Minion.Cluster do
  use GenServer

  require Logger

  @retry_ms 3_000

  def start_link(_opts) do
    case {Node.alive?(), nodes()} do
      {true, [_ | _]} -> GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
      _ -> :ignore
    end
  end

  def nodes, do: Application.get_env(:minion, :cluster_nodes, [])

  @impl true
  def init(:ok) do
    :net_kernel.monitor_nodes(true)
    send(self(), :connect)
    {:ok, nil}
  end

  @impl true
  def handle_info(:connect, state) do
    nodes()
    |> Enum.reject(&(&1 == node() or &1 in Node.list()))
    |> Enum.each(&Node.connect/1)

    Process.send_after(self(), :connect, @retry_ms)
    {:noreply, state}
  end

  def handle_info({:nodeup, node}, state) do
    Logger.info("Cluster: #{node} joined; connected to #{inspect(Node.list())}")
    {:noreply, state}
  end

  def handle_info({:nodedown, node}, state) do
    Logger.warning("Cluster: #{node} left; connected to #{inspect(Node.list())}")
    {:noreply, state}
  end
end
