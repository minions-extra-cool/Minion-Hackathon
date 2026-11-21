defmodule Minion.Channels.Email do
  @behaviour Minion.Channel

  alias Minion.Accounts.Person
  alias Minion.Alerts.Alert
  alias Minion.Mailer
  alias Minion.Runbooks
  alias MinionWeb.{Links, Markdown}

  @from "minion@minion.test"

  @impl Minion.Channel
  def deliver(%Alert{}, %Person{email: email}) when email in [nil, ""],
    do: {:error, :no_email_address}

  def deliver(%Alert{} = alert, %Person{} = person) do
    alert
    |> build_email(person)
    |> Mailer.deliver()
    |> case do
      {:ok, _meta} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec build_email(Alert.t(), Person.t()) :: Swoosh.Email.t()
  def build_email(alert, person) do
    runbook = rendered_runbook(alert)

    Swoosh.Email.new()
    |> Swoosh.Email.to(person.email)
    |> Swoosh.Email.from(@from)
    |> Swoosh.Email.subject("[#{String.upcase(to_string(alert.severity))}] #{alert.title}")
    |> Swoosh.Email.text_body(text_body(alert, person, runbook))
    |> Swoosh.Email.html_body(html_body(alert, person, runbook))
  end

  defp rendered_runbook(alert) do
    runbook = Runbooks.get_for_rule(alert.rule_id)
    if Runbooks.blank?(runbook), do: nil, else: Runbooks.render(runbook, alert.sample_event)
  end

  defp text_body(alert, person, runbook) do
    """
    Hello #{person.name},

    #{alert.title}

    Severity: #{alert.severity}
    #{alert.body}
    #{text_runbook(runbook)}
    Open the alert: #{Links.alert_url(alert)}
    """
  end

  defp text_runbook(nil), do: ""
  defp text_runbook(runbook), do: "\nWhat to do:\n#{runbook}\n"

  defp html_body(alert, person, runbook) do
    """
    <p>Hello #{escape(person.name)},</p>
    <h2>#{escape(alert.title)}</h2>
    <p><strong>Severity:</strong> #{alert.severity}</p>
    <p>#{escape(alert.body)}</p>
    #{html_runbook(runbook)}
    <p><a href="#{escape(Links.alert_url(alert))}">Open the alert in Minion</a></p>
    """
  end

  defp html_runbook(nil), do: ""

  defp html_runbook(runbook) do
    "<h3>What to do</h3>\n" <> Phoenix.HTML.safe_to_string(Markdown.to_html(runbook))
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()
end
