defmodule Minion.Accounts.PersonTest do
  use ExUnit.Case, async: true

  alias Minion.Accounts.Person

  defp errors(attrs) do
    %Person{}
    |> Person.changeset(Map.put_new(attrs, :name, "Anna"))
    |> Map.fetch!(:errors)
    |> Keyword.keys()
  end

  test "accepts the documented preference shape" do
    preferences = %{
      "critical" => [%{"channels" => ["sms"], "hours" => [8, 20]}, %{"channels" => ["email"]}],
      "warning" => [%{"channels" => ["email"], "hours" => [22, 6]}],
      "info" => []
    }

    assert errors(%{preferences: preferences}) == []
  end

  test "rejects unknown channels, severities and malformed hours" do
    assert :preferences in errors(%{preferences: %{"critical" => [%{"channels" => ["pigeon"]}]}})
    assert :preferences in errors(%{preferences: %{"urgent" => []}})

    assert :preferences in errors(%{
             preferences: %{"info" => [%{"channels" => ["email"], "hours" => [8]}]}
           })

    assert :preferences in errors(%{
             preferences: %{"info" => [%{"channels" => ["email"], "hours" => [25, 3]}]}
           })
  end

  test "checks that email and phone look right" do
    assert :email in errors(%{email: "not-an-email"})
    assert :phone in errors(%{phone: "call me"})
    assert errors(%{email: "anna@minion.test", phone: "+48 100 200 300"}) == []
  end
end
