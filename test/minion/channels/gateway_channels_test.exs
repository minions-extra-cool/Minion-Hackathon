defmodule Minion.Channels.GatewayChannelsTest do
  use ExUnit.Case, async: true

  alias Minion.Accounts.Person
  alias Minion.Alerts.Alert
  alias Minion.Channels.{Gateway, Phone, Sms}

  @alert %Alert{
    id: "0b6c3f4e-2d0a-4a43-9d8e-6f1c2a7b9e11",
    severity: :critical,
    title: "Disk full on web-1"
  }
  @piotr %Person{name: "Piotr", phone: "+48400500600"}

  defp capture_request do
    test_pid = self()

    Req.Test.stub(Gateway, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:gateway_request, Jason.decode!(body)})
      Req.Test.json(conn, %{id: 1})
    end)
  end

  test "an SMS posts the severity, title and a link to the alert to the gateway" do
    capture_request()

    assert Sms.deliver(@alert, @piotr) == :ok

    assert_received {:gateway_request,
                     %{
                       "channel" => "sms",
                       "to" => "+48400500600",
                       "text" => text
                     }}

    assert text =~ ~r"^\[CRITICAL\] Disk full on web-1 http://\S+/alerts/#{@alert.id}$"
  end

  test "a phone call posts a spoken message to the gateway" do
    capture_request()

    assert Phone.deliver(@alert, @piotr) == :ok

    assert_received {:gateway_request,
                     %{"channel" => "phone", "to" => "+48400500600", "text" => text}}

    assert text =~ "critical alert: Disk full on web-1"
  end

  test "a gateway error status is returned as an error" do
    Req.Test.stub(Gateway, &Plug.Conn.send_resp(&1, 503, "down"))

    assert Sms.deliver(@alert, @piotr) == {:error, {:gateway_status, 503}}
  end

  test "an unreachable gateway is returned as an error" do
    Req.Test.stub(Gateway, &Req.Test.transport_error(&1, :econnrefused))

    assert {:error, {:gateway_unreachable, _message}} = Phone.deliver(@alert, @piotr)
  end

  test "a person without a phone number cannot get an SMS or a call" do
    assert Sms.deliver(@alert, %Person{phone: nil}) == {:error, :no_phone_number}
    assert Phone.deliver(@alert, %Person{phone: ""}) == {:error, :no_phone_number}
  end
end
