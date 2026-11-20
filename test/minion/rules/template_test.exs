defmodule Minion.Rules.TemplateTest do
  use ExUnit.Case, async: true

  alias Minion.Rules.Template

  @envelope %{
    "source" => "workflow-engine",
    "payload" => %{
      "workflowName" => "Order-settlement",
      "step" => "validate-counterparty",
      "attempt" => 3,
      "error" => %{"code" => "TIMEOUT"}
    }
  }

  test "fills placeholders with values from the envelope" do
    assert Template.render("{{payload.workflowName}} failed at {{ payload.step }}", @envelope) ==
             "Order-settlement failed at validate-counterparty"
  end

  test "renders numbers, and nested objects as JSON" do
    assert Template.render("attempt {{payload.attempt}}: {{payload.error}}", @envelope) ==
             ~s(attempt 3: {"code":"TIMEOUT"})
  end

  test "a missing field renders as empty text" do
    assert Template.render("rejected {{payload.crrency}}", @envelope) == "rejected "
  end

  test "text without placeholders and a nil template" do
    assert Template.render("Disk full", @envelope) == "Disk full"
    assert Template.render(nil, @envelope) == ""
  end
end
