defmodule Writing.Trending.Repository do
  @moduledoc """
  A repository observed on GitHub Trending.

  `stars_today` is `nil` when the source page omitted or did not expose the
  daily count. A reported `0` remains a distinct, known value.
  """

  @enforce_keys [:rank, :full_name, :url, :stars, :language, :observed_at, :source_url]
  defstruct [
    :rank,
    :full_name,
    :url,
    :description,
    :stars,
    :stars_today,
    :forks,
    :language,
    :observed_at,
    :source_url
  ]

  @type t :: %__MODULE__{
          rank: pos_integer(),
          full_name: String.t(),
          url: String.t(),
          description: String.t() | nil,
          stars: non_neg_integer(),
          stars_today: non_neg_integer() | nil,
          forks: non_neg_integer() | nil,
          language: String.t(),
          observed_at: DateTime.t(),
          source_url: String.t()
        }
end
