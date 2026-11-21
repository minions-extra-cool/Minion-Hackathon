defmodule Minion.Channels.Gateway do
  @spec send_message(String.t(), String.t(), String.t()) :: :ok | {:error, term()}
  def send_message(channel, to, text) do
    options =
      [json: %{channel: channel, to: to, text: text}, retry: false, receive_timeout: 5_000] ++
        config(:req_options, [])

    case Req.post(config(:url), options) do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      {:ok, %Req.Response{status: status}} -> {:error, {:gateway_status, status}}
      {:error, exception} -> {:error, {:gateway_unreachable, Exception.message(exception)}}
    end
  end

  defp config(key, default \\ nil) do
    :minion |> Application.get_env(__MODULE__, []) |> Keyword.get(key, default)
  end
end
