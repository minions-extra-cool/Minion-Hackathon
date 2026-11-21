defmodule Minion.ClusterTest do
  use ExUnit.Case, async: false

  test "does nothing when no cluster nodes are configured" do
    original = Application.get_env(:minion, :cluster_nodes)
    Application.delete_env(:minion, :cluster_nodes)
    on_exit(fn -> if original, do: Application.put_env(:minion, :cluster_nodes, original) end)

    assert Minion.Cluster.start_link([]) == :ignore
  end

  test "does nothing on a node started without a name, even with nodes configured" do
    original = Application.get_env(:minion, :cluster_nodes)
    Application.put_env(:minion, :cluster_nodes, [:other@localhost])
    on_exit(fn -> Application.put_env(:minion, :cluster_nodes, original || []) end)

    refute Node.alive?()
    assert Minion.Cluster.start_link([]) == :ignore
  end
end
