defmodule MinionWeb.FakeGatewayLiveTest do
  use MinionWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Minion.FakeGateway

  setup do
    FakeGateway.set_down(false)
    FakeGateway.clear()
    on_exit(fn -> FakeGateway.set_down(false) end)
  end

  test "shows messages as they arrive", %{conn: conn} do
    {:ok, view, html} = live(conn, ~p"/gateway")
    assert html =~ "No messages yet."

    FakeGateway.receive_message(%{
      "channel" => "phone",
      "to" => "+48400500600",
      "text" => "Disk full on web-1"
    })

    html = render(view)
    assert html =~ "Phone call"
    assert html =~ "+48400500600"
    assert html =~ "Disk full on web-1"
  end

  test "the switch takes the gateway down and brings it back", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/gateway")

    view |> element("#toggle-down") |> render_click()
    assert FakeGateway.down?()
    assert view |> element("#gateway-status") |> render() =~ "DOWN"

    view |> element("#toggle-down") |> render_click()
    refute FakeGateway.down?()
    assert view |> element("#gateway-status") |> render() =~ "UP"
  end
end
