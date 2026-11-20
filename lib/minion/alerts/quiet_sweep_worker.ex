defmodule Minion.Alerts.QuietSweepWorker do
  use Oban.Worker, queue: :maintenance, max_attempts: 1

  alias Minion.Alerts.QuietSweep

  @half_minute 30

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    QuietSweep.run()

    if args["schedule_half_minute_run"] do
      %{} |> new(schedule_in: @half_minute) |> Oban.insert!()
    end

    :ok
  end
end
