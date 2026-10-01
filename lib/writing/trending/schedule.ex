defmodule Writing.Trending.Schedule do
  @moduledoc false

  def periods_for(%Date{} = date) do
    [:daily]
    |> maybe_add(Date.day_of_week(date) == 1, :weekly)
    |> maybe_add(date.day == 1, :monthly)
  end

  defp maybe_add(periods, true, period), do: periods ++ [period]
  defp maybe_add(periods, false, _period), do: periods
end
