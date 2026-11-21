defmodule Minion.Delivery.WorkerTest do
  use Minion.DataCase
  use Oban.Testing, repo: Minion.Repo

  alias Minion.Accounts.{Person, Team}
  alias Minion.Alerts.Alert
  alias Minion.Channels.Gateway
  alias Minion.Delivery.{Delivery, Worker}
  alias Minion.Rules.Rule

  defp fixture(channel, person_attrs \\ %{}) do
    team = Repo.insert!(%Team{name: "ops-#{Ecto.UUID.generate()}"})

    person =
      Repo.insert!(
        struct(
          %Person{
            team_id: team.id,
            name: "Anna",
            email: "anna@minion.test",
            phone: "+48100200300"
          },
          person_attrs
        )
      )

    rule =
      Repo.insert!(%Rule{
        name: "Disk full",
        owner_type: :team,
        owner_id: team.id,
        severity: :warning,
        conditions: %{},
        notify: [%{"type" => "team", "id" => team.id}]
      })

    alert =
      Repo.insert!(%Alert{
        rule_id: rule.id,
        owner_type: :team,
        owner_id: team.id,
        fingerprint: Ecto.UUID.generate(),
        severity: :warning,
        first_seen: DateTime.utc_now(),
        last_seen: DateTime.utc_now(),
        title: "Disk full on web-1",
        body: "web-1 reported a full disk.",
        sample_event: %{}
      })

    delivery = Repo.insert!(%Delivery{alert_id: alert.id, person_id: person.id, channel: channel})
    Phoenix.PubSub.subscribe(Minion.PubSub, "alerts:team:#{team.id}")

    %{delivery: delivery, alert: alert, person: person}
  end

  defp run(delivery, attempt \\ 1),
    do: perform_job(Worker, %{"delivery_id" => delivery.id}, attempt: attempt)

  defp reload(delivery), do: Repo.get!(Delivery, delivery.id)

  defp deliveries_for(alert),
    do: Repo.all(from d in Delivery, where: d.alert_id == ^alert.id, order_by: d.inserted_at)

  defp gateway_down, do: Req.Test.stub(Gateway, &Plug.Conn.send_resp(&1, 503, "down"))

  test "a successful send marks the delivery delivered and tells subscribers" do
    %{delivery: delivery} = fixture(:email)

    assert :ok = run(delivery)

    assert %Delivery{status: :delivered, attempts: 1, last_error: nil} = reload(delivery)
    assert_received {:delivery, %Delivery{status: :delivered}}
  end

  test "a failed attempt keeps the delivery pending, records the error and asks Oban to retry" do
    gateway_down()
    %{delivery: delivery} = fixture(:sms)

    assert {:error, {:gateway_status, 503}} = run(delivery)

    assert %Delivery{status: :pending, attempts: 1, last_error: "{:gateway_status, 503}"} =
             reload(delivery)

    assert_received {:delivery, %Delivery{status: :pending, attempts: 1}}
  end

  test "retries wait 5s, 15s and then 60s" do
    assert Enum.map(1..4, &Worker.backoff(%Oban.Job{attempt: &1})) == [5, 15, 60, 60]
  end

  test "after the last attempt the delivery fails and an email is sent instead" do
    gateway_down()
    %{delivery: delivery, alert: alert, person: person} = fixture(:sms)

    assert {:cancel, {:gateway_status, 503}} = run(delivery, 4)

    assert [
             %Delivery{channel: :sms, status: :failed},
             %Delivery{channel: :email, status: :pending} = fallback
           ] =
             deliveries_for(alert)

    assert fallback.person_id == person.id
    assert_enqueued(worker: Worker, queue: :email, args: %{"delivery_id" => fallback.id})
    assert_received {:delivery, %Delivery{channel: :sms, status: :failed}}
    assert_received {:delivery, %Delivery{channel: :email, status: :pending}}
  end

  test "a person without a phone number fails at once and falls back to email" do
    %{delivery: delivery, alert: alert} = fixture(:phone, %{phone: nil})

    assert {:cancel, :no_phone_number} = run(delivery, 1)

    assert [%Delivery{channel: :phone, status: :failed, attempts: 1}, %Delivery{channel: :email}] =
             deliveries_for(alert)
  end

  test "a person without a Discord webhook fails at once and falls back to email" do
    %{delivery: delivery, alert: alert} = fixture(:discord)

    assert {:cancel, :no_discord_webhook} = run(delivery, 1)

    assert [%Delivery{channel: :discord, status: :failed}, %Delivery{channel: :email}] =
             deliveries_for(alert)
  end

  test "a Discord delivery goes through the registered channel module" do
    url = "https://discord.com/api/webhooks/123/abc-DEF"
    %{delivery: delivery} = fixture(:discord, %{discord_webhook_url: url})
    Req.Test.stub(Minion.Channels.Discord, &Plug.Conn.send_resp(&1, 204, ""))

    assert :ok = run(delivery, 1)
    assert %Delivery{status: :delivered} = reload(delivery)
  end

  test "a failed email has no fallback" do
    %{delivery: delivery, alert: alert} = fixture(:email, %{email: nil})

    assert {:cancel, :no_email_address} = run(delivery, 1)

    assert [%Delivery{channel: :email, status: :failed, last_error: ":no_email_address"}] =
             deliveries_for(alert)
  end

  test "no fallback for a person without an email address" do
    gateway_down()
    %{delivery: delivery, alert: alert} = fixture(:sms, %{email: nil})

    run(delivery, 4)

    assert [%Delivery{channel: :sms, status: :failed}] = deliveries_for(alert)
  end

  test "no second email when the person already gets this alert by email" do
    gateway_down()
    %{delivery: delivery, alert: alert, person: person} = fixture(:sms)
    Repo.insert!(%Delivery{alert_id: alert.id, person_id: person.id, channel: :email})

    run(delivery, 4)

    assert alert |> deliveries_for() |> Enum.count(&(&1.channel == :email)) == 1
  end

  test "a delivery that already finished is not sent again" do
    test_pid = self()

    Req.Test.stub(Gateway, fn conn ->
      send(test_pid, :gateway_called) && Req.Test.json(conn, %{})
    end)

    %{delivery: delivery} = fixture(:sms)
    delivery |> Ecto.Changeset.change(status: :delivered) |> Repo.update!()

    assert :ok = run(delivery)

    refute_received :gateway_called
  end

  test "cancels the job when its delivery no longer exists" do
    assert {:cancel, :delivery_not_found} =
             perform_job(Worker, %{"delivery_id" => Ecto.UUID.generate()})
  end

  test "escapes names, titles and bodies in the HTML email" do
    %{delivery: delivery, person: person, alert: alert} = fixture(:email)
    person |> Ecto.Changeset.change(name: "<b>Anna</b>") |> Repo.update!()
    alert |> Ecto.Changeset.change(title: "Disk <script>") |> Repo.update!()

    run(delivery)

    assert_received {:email, email}
    assert email.html_body =~ "&lt;b&gt;Anna&lt;/b&gt;"
    assert email.html_body =~ "Disk &lt;script&gt;"
    refute email.html_body =~ "<script>"
  end

  test "an unreachable mail server is a retryable failure" do
    mailer_config = Application.fetch_env!(:minion, Minion.Mailer)

    Application.put_env(:minion, Minion.Mailer,
      adapter: Swoosh.Adapters.SMTP,
      relay: "localhost",
      port: 1,
      ssl: false,
      tls: :never,
      auth: :never,
      retries: 0
    )

    on_exit(fn -> Application.put_env(:minion, Minion.Mailer, mailer_config) end)
    %{delivery: delivery} = fixture(:email)

    assert {:error, _reason} = run(delivery)

    assert %Delivery{status: :pending, attempts: 1, last_error: error} = reload(delivery)
    assert error =~ "econnrefused"
  end
end
