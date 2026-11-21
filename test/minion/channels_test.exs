defmodule Minion.ChannelsTest do
  use ExUnit.Case, async: true

  alias Minion.Channels

  test "the configured channels drive names, modules and labels" do
    assert [:email, :sms, :phone | _] = Channels.names()
    assert Channels.module_for(:sms) == Minion.Channels.Sms
    assert Channels.module_for("email") == Minion.Channels.Email
    assert Channels.module_for("pigeon") == nil
    assert Channels.label(:phone) == "Phone call"
    assert {"sms", "SMS"} in Channels.options()
  end

  test "each channel says which errors are not worth retrying" do
    assert Channels.permanent_error?(:email, :no_email_address)
    assert Channels.permanent_error?(:sms, :no_phone_number)
    refute Channels.permanent_error?(:sms, :timeout)
  end

  test "every configured channel implements the behaviour" do
    for name <- Channels.names() do
      module = Channels.module_for(name)
      Code.ensure_loaded!(module)
      assert function_exported?(module, :label, 0), "#{module} has no label/0"
      assert function_exported?(module, :deliver, 2), "#{module} has no deliver/2"
    end
  end
end
