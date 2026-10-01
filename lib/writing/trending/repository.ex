defmodule Writing.Trending.Repository do
  @enforce_keys [:full_name, :url, :rank]
  defstruct [
    :full_name,
    :url,
    :rank,
    :description,
    :language,
    :total_stars,
    :period_stars,
    :forks,
    :topics,
    :readme,
    :period
  ]

  @type t :: %__MODULE__{
          full_name: String.t(),
          url: String.t(),
          rank: pos_integer(),
          description: String.t() | nil,
          language: String.t() | nil,
          total_stars: String.t() | nil,
          period_stars: String.t() | nil,
          forks: String.t() | nil,
          topics: [String.t()],
          readme: String.t() | nil,
          period: String.t() | nil
        }
end
