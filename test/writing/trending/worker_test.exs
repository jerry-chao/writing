defmodule Writing.Trending.WorkerTest do
  use ExUnit.Case, async: true

  alias Writing.Trending.Worker

  test "skips a queued job whose insertion date is no longer today in Beijing" do
    job = %Oban.Job{inserted_at: ~U[2000-01-01 00:00:00Z]}

    assert {:cancel, :missed_run} = Worker.perform(job)
  end
end
