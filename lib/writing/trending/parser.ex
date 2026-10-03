defmodule Writing.Trending.Parser do
  @moduledoc """
  Parses repository cards from GitHub Trending HTML.

  GitHub's markup is not a stable API. This parser intentionally rejects pages
  that do not contain at least ten valid, unique repository cards rather than
  returning a partial list that could become a misleading article.
  """

  alias Writing.Trending.Repository

  @minimum_repositories 10
  @default_source_url "https://github.com/trending/elixir?since=daily"

  @type parse_error ::
          :not_html
          | :no_repository_cards
          | {:too_few_repositories, non_neg_integer()}
          | {:invalid_repository, pos_integer(), atom()}
          | {:duplicate_repository, String.t()}

  @doc "Parses and validates the first ten repository cards in the page order."
  @spec parse(binary(), keyword()) :: {:ok, [Repository.t()]} | {:error, parse_error()}
  def parse(html, opts \\ [])

  def parse(html, opts) when is_binary(html) do
    language = Keyword.get(opts, :language, "elixir")
    source_url = Keyword.get(opts, :source_url, @default_source_url)
    observed_at = Keyword.get(opts, :observed_at, DateTime.utc_now())

    if String.contains?(html, "<") do
      html
      |> LazyHTML.from_document()
      |> LazyHTML.query("article.Box-row")
      |> parse_cards(language, source_url, observed_at)
    else
      {:error, :not_html}
    end
  end

  def parse(_html, _opts), do: {:error, :not_html}

  defp parse_cards(cards, language, source_url, observed_at) do
    card_count = Enum.count(cards)

    cond do
      card_count == 0 ->
        {:error, :no_repository_cards}

      card_count < @minimum_repositories ->
        {:error, {:too_few_repositories, card_count}}

      true ->
        cards
        |> Enum.take(@minimum_repositories)
        |> Enum.with_index(1)
        |> Enum.reduce_while({:ok, []}, fn {card, rank}, {:ok, repos} ->
          case parse_card(card, rank, language, source_url, observed_at) do
            {:ok, repo} -> {:cont, {:ok, [repo | repos]}}
            {:error, field} -> {:halt, {:error, {:invalid_repository, rank, field}}}
          end
        end)
        |> validate_unique_repositories()
    end
  end

  defp parse_card(card, rank, language, source_url, observed_at) do
    with {:ok, full_name, url} <- repository_identity(card),
         {:ok, stars} <- required_count(card, "a[href$='/stargazers']") do
      {:ok,
       %Repository{
         rank: rank,
         full_name: full_name,
         url: url,
         description: optional_text(card, "p"),
         stars: stars,
         stars_today: optional_daily_stars(card),
         forks: optional_count(card, "a[href$='/forks']"),
         language: optional_text(card, "span[itemprop='programmingLanguage']") || language,
         observed_at: observed_at,
         source_url: source_url
       }}
    end
  end

  defp repository_identity(card) do
    case card |> LazyHTML.query("h2 a") |> LazyHTML.attribute("href") |> List.first() do
      "/" <> path when path != "" ->
        case String.split(path, "/", trim: true) do
          [owner, repo]
          when byte_size(owner) <= 39 and byte_size(repo) <= 100 and owner not in [".", ".."] and
                 repo not in [".", ".."] ->
            if valid_repository_component?(owner) and valid_repository_component?(repo) do
              full_name = "#{owner}/#{repo}"
              {:ok, full_name, "https://github.com/#{full_name}"}
            else
              {:error, :repository_url}
            end

          _ ->
            {:error, :repository_url}
        end

      _ ->
        {:error, :repository_url}
    end
  end

  defp valid_repository_component?(component) do
    Regex.match?(~r/\A[A-Za-z0-9_.-]+\z/, component)
  end

  defp required_count(card, selector) do
    case count_text(card, selector) do
      {:ok, count} -> {:ok, count}
      :error -> {:error, :stars}
    end
  end

  defp optional_count(card, selector) do
    case count_text(card, selector) do
      {:ok, count} -> count
      :error -> nil
    end
  end

  defp count_text(card, selector) do
    text = card |> LazyHTML.query(selector) |> LazyHTML.text() |> String.trim()
    parse_count(text)
  end

  defp parse_count(text) do
    case Regex.run(~r/^([\d,]+)$/, text, capture: :all_but_first) do
      [digits] ->
        case Integer.parse(String.replace(digits, ",", "")) do
          {count, ""} when count >= 0 -> {:ok, count}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  defp optional_text(card, selector) do
    text = card |> LazyHTML.query(selector) |> LazyHTML.text() |> normalize_text()
    if text == "", do: nil, else: text
  end

  defp optional_daily_stars(card) do
    card
    |> LazyHTML.text()
    |> then(&Regex.run(~r/([\d,]+)\s+stars today\b/i, &1, capture: :all_but_first))
    |> case do
      [digits] ->
        case parse_count(digits) do
          {:ok, count} -> count
          :error -> nil
        end

      _ ->
        nil
    end
  end

  defp normalize_text(text) do
    text
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
  end

  defp validate_unique_repositories({:ok, repos}) do
    repos = Enum.reverse(repos)
    names = Enum.map(repos, & &1.full_name)

    case Enum.find(names, fn name -> Enum.count(names, &(&1 == name)) > 1 end) do
      nil -> {:ok, repos}
      duplicate -> {:error, {:duplicate_repository, duplicate}}
    end
  end

  defp validate_unique_repositories(error), do: error
end
