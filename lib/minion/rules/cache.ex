defmodule Minion.Rules.Cache do
  use GenServer

  require Logger

  import Ecto.Query

  alias Minion.Repo
  alias Minion.Rules.Rule

  @table __MODULE__
  @reload_interval_ms 5_000

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @spec all() :: [Rule.t()]
  def all do
    case :ets.lookup(@table, :rules) do
      [{:rules, rules}] -> rules
      [] -> []
    end
  end

  def reload, do: GenServer.call(__MODULE__, :reload)

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :protected, read_concurrency: true])
    Phoenix.PubSub.subscribe(Minion.PubSub, Minion.Rules.topic())
    load!()
    schedule_reload()
    {:ok, nil}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    load!()
    {:reply, :ok, state}
  end

  @impl true
  def handle_info(:reload, state) do
    safe_load()
    schedule_reload()
    {:noreply, state}
  end

  def handle_info({:rules_changed, _rule_id}, state) do
    safe_load()
    {:noreply, state}
  end

  defp safe_load do
    load!()
  rescue
    error -> Logger.error("Reloading rules failed, keeping previous rules: #{inspect(error)}")
  end

  defp load! do
    rules = Repo.all(from r in Rule, where: r.enabled)
    :ets.insert(@table, {:rules, rules})
  end

  defp schedule_reload, do: Process.send_after(self(), :reload, @reload_interval_ms)
end
