defmodule Minion.Delivery.WorkerTest do
  use Minion.DataCase

  alias Minion.Accounts.{Person, Team}
  alias Minion.Alerts.Alert
  alias Minion.Delivery.Delivery
  alias Minion.Delivery.Worker
  alias Minion.Repo
  alias Minion.Rules.Rule

  describe "perform/1" do
    test "marks the delivery delivered and counts the attempt" do
      %{delivery: delivery} = fixture(:email)

      Worker.perform(%Oban.Job{args: %{"delivery_id" => delivery.id}})

      delivery = Repo.get(Delivery, delivery.id)
      assert delivery.status == :delivered
      assert delivery.attempts == 1
      assert delivery.last_error == nil
    end

    test "records the error and marks the delivery failed" do
      Req.Test.stub(Minion.Channels.Gateway, &Plug.Conn.send_resp(&1, 503, "down"))
      %{delivery: delivery} = fixture(:sms)

      Worker.perform(%Oban.Job{args: %{"delivery_id" => delivery.id}})

      delivery = Repo.get(Delivery, delivery.id)
      assert delivery.status == :failed
      assert delivery.attempts == 1
      assert delivery.last_error == "{:gateway_status, 503}"
    end

    test "fails an email delivery to a person without an email address" do
      %{delivery: delivery, person: person} = fixture(:email)
      person |> Ecto.Changeset.change(email: nil) |> Repo.update!()

      Worker.perform(%Oban.Job{args: %{"delivery_id" => delivery.id}})

      delivery = Repo.get(Delivery, delivery.id)
      assert delivery.status == :failed
      assert delivery.last_error == ":no_email_address"
    end

    test "escapes names, titles and bodies in the HTML email" do
      %{delivery: delivery, person: person, alert: alert} = fixture(:email)
      person |> Ecto.Changeset.change(name: "<b>Anna</b>") |> Repo.update!()
      alert |> Ecto.Changeset.change(title: "Disk <script>") |> Repo.update!()

      Worker.perform(%Oban.Job{args: %{"delivery_id" => delivery.id}})

      assert_received {:email, email}
      assert email.html_body =~ "&lt;b&gt;Anna&lt;/b&gt;"
      assert email.html_body =~ "Disk &lt;script&gt;"
      refute email.html_body =~ "<script>"
    end

    test "cancels the job when its delivery no longer exists" do
      assert {:cancel, :delivery_not_found} =
               Worker.perform(%Oban.Job{args: %{"delivery_id" => Ecto.UUID.generate()}})
    end

    test "records the error when the mail server is unreachable" do
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

      Worker.perform(%Oban.Job{args: %{"delivery_id" => delivery.id}})

      delivery = Repo.get(Delivery, delivery.id)
      assert delivery.status == :failed
      assert delivery.attempts == 1
      assert delivery.last_error =~ "econnrefused"
    end
  end

  defp fixture(channel) do
    team = Repo.insert!(%Team{name: "ops-#{Ecto.UUID.generate()}"})

    person =
      Repo.insert!(%Person{
        team_id: team.id,
        name: "Anna",
        email: "anna@minion.test",
        phone: "+48100200300"
      })

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

    delivery =
      Repo.insert!(%Delivery{
        alert_id: alert.id,
        person_id: person.id,
        channel: channel
      })

    %{delivery: delivery, alert: alert, person: person}
  end
end
