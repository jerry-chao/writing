defmodule Writing.Trending.Worker do
  use Oban.Worker, queue: :trending, max_attempts: 3

  require Logger

  @timezone "Asia/Shanghai"

  @impl Oban.Worker
  def perform(%Oban.Job{inserted_at: inserted_at}) do
    with {:ok, scheduled_at} <- DateTime.shift_zone(inserted_at, @timezone),
         {:ok, now} <- DateTime.now(@timezone),
         true <- Date.compare(DateTime.to_date(scheduled_at), DateTime.to_date(now)) == :eq do
      Writing.Trending.run(DateTime.to_date(scheduled_at))
    else
      false ->
        Logger.warning("Skipping GitHub Trending job inserted on an earlier Beijing date")
        {:cancel, :missed_run}

      {:error, reason} ->
        {:error, {:timezone_conversion_failed, reason}}
    end
  end
end
