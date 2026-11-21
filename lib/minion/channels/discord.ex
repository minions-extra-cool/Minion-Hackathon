defmodule Minion.Channels.Discord do
  @behaviour Minion.Channel

  alias Minion.Accounts.Person
  alias Minion.Alerts.Alert
  alias Minion.Rules.Template
  alias Minion.Runbooks

  @severity_colors %{critical: 0xE5484D, warning: 0xF5A524, info: 0x6B8BA4}
  @max_fields 5

  @impl Minion.Channel
  def label, do: "Discord"

  @impl Minion.Channel
  def permanent_errors, do: [:no_discord_webhook]

  @impl Minion.Channel
  def deliver(%Alert{}, %Person{discord_webhook_url: url}) when url in [nil, ""],
    do: {:error, :no_discord_webhook}

  def deliver(%Alert{} = alert, %Person{discord_webhook_url: url}) do
    options =
      [json: message(alert), retry: false, receive_timeout: 10_000] ++
        (:minion |> Application.get_env(__MODULE__, []) |> Keyword.get(:req_options, []))

    case Req.post(url, options) do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      {:ok, %Req.Response{status: status}} -> {:error, {:discord_status, status}}
      {:error, error} -> {:error, {:unreachable, Exception.message(error)}}
    end
  end

  @spec message(Alert.t()) :: map()
  def message(%Alert{} = alert) do
    alert = Minion.Repo.preload(alert, :rule)

    %{
      username: "Minion",
      allowed_mentions: %{parse: []},
      embeds: [
        %{
          title: truncate("[#{String.upcase(to_string(alert.severity))}] #{alert.title}", 256),
          url: MinionWeb.Links.alert_url(alert),
          description: truncate(alert.body || "", 2_000),
          color: Map.get(@severity_colors, alert.severity, 0x6B8BA4),
          fields: fields(alert) ++ runbook_field(alert),
          timestamp: alert.first_seen && DateTime.to_iso8601(alert.first_seen)
        }
      ]
    }
  end

  defp fields(%Alert{rule: %{present: %{"fields" => paths}}} = alert) when is_list(paths) do
    paths
    |> Enum.take(@max_fields)
    |> Enum.map(fn path ->
      %{
        name: truncate(path |> String.split(".") |> List.last(), 256),
        value: truncate(blank_dash(Template.render("{{#{path}}}", alert.sample_event)), 1_024),
        inline: true
      }
    end)
  end

  defp fields(_alert), do: []

  defp runbook_field(alert) do
    runbook = Runbooks.get_for_rule(alert.rule_id)

    if Runbooks.blank?(runbook),
      do: [],
      else: [
        %{
          name: "What to do",
          value: truncate(Runbooks.render(runbook, alert.sample_event), 1_024)
        }
      ]
  end

  defp blank_dash(""), do: "—"
  defp blank_dash(value), do: value

  defp truncate(text, limit) do
    if String.length(text) <= limit, do: text, else: String.slice(text, 0, limit - 1) <> "…"
  end
end
