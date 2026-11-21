defmodule Minion.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MinionWeb.Telemetry,
      Minion.Repo,
      {DNSCluster, query: Application.get_env(:minion, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Minion.PubSub},
      Minion.FakeGateway,
      {Oban, Application.fetch_env!(:minion, Oban)},
      Minion.Kafka,
      Minion.Kafka.Topics
    ]

    children = children ++ pipeline_children() ++ [MinionWeb.Endpoint]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Minion.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp pipeline_children do
    if Application.fetch_env!(:minion, :pipeline)[:enabled] do
      [Minion.Rules.Cache, Minion.Alerts.Pipeline, Minion.Ingest.KafkaSource]
    else
      []
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MinionWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
