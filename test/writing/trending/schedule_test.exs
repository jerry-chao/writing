defmodule Writing.Trending.ScheduleTest do
  use ExUnit.Case, async: true

  alias Writing.Trending.Schedule

  test "daily runs are always due" do
    assert Schedule.periods_for(~D[2026-10-06]) == [:daily]
  end

  test "weekly runs are due on Mondays" do
    assert Schedule.periods_for(~D[2026-10-05]) == [:daily, :weekly]
  end

  test "monthly and weekly runs share one occurrence when the first is Monday" do
    assert Schedule.periods_for(~D[2026-06-01]) == [:daily, :weekly, :monthly]
  end

  test "monthly runs are due on the first day of the month" do
    assert Schedule.periods_for(~D[2026-10-01]) == [:daily, :monthly]
  end
end
