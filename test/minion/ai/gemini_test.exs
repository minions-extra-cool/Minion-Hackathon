defmodule Minion.AI.GeminiTest do
  use ExUnit.Case, async: true

  alias Minion.AI.Gemini

  test "asks for JSON and a larger answer when told to" do
    Req.Test.stub(Gemini, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      assert %{
               "generationConfig" => %{
                 "responseMimeType" => "application/json",
                 "maxOutputTokens" => 4096
               }
             } = Jason.decode!(body)

      Req.Test.json(conn, %{"candidates" => [%{"content" => %{"parts" => [%{"text" => "{}"}]}}]})
    end)

    assert {:ok, "{}"} = Gemini.generate("hi", json: true, max_output_tokens: 4096)
  end

  test "returns the text of the first candidate" do
    Req.Test.stub(Gemini, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert %{"contents" => [%{"parts" => [%{"text" => "hi"}]}]} = Jason.decode!(body)

      Req.Test.json(conn, %{
        "candidates" => [%{"content" => %{"parts" => [%{"text" => "  disk nearly full  "}]}}]
      })
    end)

    assert {:ok, "disk nearly full"} = Gemini.generate("hi")
  end

  test "reports an API error status" do
    Req.Test.stub(Gemini, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(429, Jason.encode!(%{"error" => %{"message" => "quota exceeded"}}))
    end)

    assert {:error, {:api_error, 429, "quota exceeded"}} = Gemini.generate("hi")
  end

  test "reports a missing key without calling the API" do
    previous = Application.get_env(:minion, :gemini)
    Application.put_env(:minion, :gemini, Keyword.put(previous, :api_key, nil))
    on_exit(fn -> Application.put_env(:minion, :gemini, previous) end)

    assert {:error, :not_configured} = Gemini.generate("hi")
  end

  test "reports an unreachable API" do
    Req.Test.stub(Gemini, &Req.Test.transport_error(&1, :econnrefused))

    assert {:error, {:unreachable, message}} = Gemini.generate("hi")
    assert is_binary(message)
  end
end
