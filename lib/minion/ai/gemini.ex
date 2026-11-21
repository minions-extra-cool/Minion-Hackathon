defmodule Minion.AI.Gemini do
  @behaviour Minion.AI.Provider

  alias Req.Response

  @default_base_url "https://generativelanguage.googleapis.com"
  @default_model "gemini-2.5-flash"
  @default_max_output_tokens 800

  @impl Minion.AI.Provider
  def generate(prompt, opts \\ []) when is_binary(prompt) do
    with {:ok, api_key} <- api_key(),
         {:ok, response} <- request(prompt, api_key, opts) do
      parse(response)
    end
  end

  defp api_key do
    case config(:api_key) do
      key when is_binary(key) and key != "" -> {:ok, key}
      _ -> {:error, :not_configured}
    end
  end

  defp request(prompt, api_key, opts) do
    generation_config =
      %{
        temperature: 0.2,
        maxOutputTokens: Keyword.get(opts, :max_output_tokens, @default_max_output_tokens)
      }
      |> then(&if(opts[:json], do: Map.put(&1, :responseMimeType, "application/json"), else: &1))

    options =
      [
        headers: [{"x-goog-api-key", api_key}],
        json: %{
          contents: [%{role: "user", parts: [%{text: prompt}]}],
          generationConfig: generation_config
        },
        connect_options: [timeout: 10_000],
        receive_timeout: 30_000,
        retry: false
      ] ++ config(:req_options, [])

    case Req.post(endpoint(), options) do
      {:ok, %Response{status: status} = response} when status in 200..299 ->
        {:ok, response}

      {:ok, %Response{status: status, body: body}} ->
        {:error, {:api_error, status, error_message(body)}}

      {:error, error} ->
        {:error, {:unreachable, Exception.message(error)}}
    end
  end

  defp endpoint do
    base = String.trim_trailing(config(:base_url, @default_base_url), "/")
    "#{base}/v1beta/models/#{config(:model, @default_model)}:generateContent"
  end

  defp parse(%Response{body: body}) do
    case text_of(body) do
      text when is_binary(text) and text != "" -> {:ok, String.trim(text)}
      _ -> {:error, :empty_response}
    end
  end

  defp text_of(%{"candidates" => [%{"content" => %{"parts" => parts}} | _]})
       when is_list(parts) do
    Enum.map_join(parts, "\n", fn
      %{"text" => text} -> text || ""
      _ -> ""
    end)
  end

  defp text_of(_body), do: nil

  defp error_message(%{"error" => %{"message" => message}}) when is_binary(message), do: message
  defp error_message(_body), do: "unexpected response from Gemini"

  defp config(key, default \\ nil) do
    :minion |> Application.get_env(:gemini, []) |> Keyword.get(key, default)
  end
end
