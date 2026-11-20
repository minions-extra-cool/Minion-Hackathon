defmodule Minion.Channels.Email do
  @moduledoc false

  @behaviour Minion.Channel

  alias Minion.Accounts.Person
  alias Minion.Alerts.Alert
  alias Minion.Mailer

  @from "minion@minion.test"

  @impl Minion.Channel
  def deliver(%Alert{} = alert, %Person{} = person) do
    alert
    |> build_email(person)
    |> Mailer.deliver()
    |> case do
      {:ok, _meta} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_email(alert, person) do
    Swoosh.Email.new()
    |> Swoosh.Email.to(person.email)
    |> Swoosh.Email.from(@from)
    |> Swoosh.Email.subject("[#{String.upcase(to_string(alert.severity))}] #{alert.title}")
    |> Swoosh.Email.text_body(text_body(alert, person))
    |> Swoosh.Email.html_body(html_body(alert, person))
  end

  defp text_body(alert, person) do
    """
    Hello #{person.name},

    #{alert.title}

    Severity: #{alert.severity}
    #{alert.body}

    View the alert in Minion.
    """
  end

  defp html_body(alert, person) do
    title =
      alert.title
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    body =
      alert.body
      |> Phoenix.HTML.html_escape()
      |> Phoenix.HTML.Safe.to_iodata()
      |> IO.iodata_to_binary()

    """
    <p>Hello #{person.name},</p>
    <h2>#{title}</h2>
    <p><strong>Severity:</strong> #{alert.severity}</p>
    <p>#{body}</p>
    """
  end
end
