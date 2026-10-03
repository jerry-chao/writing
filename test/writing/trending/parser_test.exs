defmodule Writing.Trending.ParserTest do
  use ExUnit.Case, async: true

  alias Writing.Trending.Parser

  @fixture_path Path.join([__DIR__, "../../fixtures/github_trending/elixir_daily.html"])
  @fixture File.read!(@fixture_path)

  test "parses the first ten repository cards in page order" do
    observed_at = ~U[2026-10-04 08:00:00Z]
    source_url = "https://github.com/trending/elixir?since=daily"

    assert {:ok, repositories} =
             Parser.parse(@fixture,
               language: "elixir",
               source_url: source_url,
               observed_at: observed_at
             )

    assert length(repositories) == 10
    assert Enum.map(repositories, & &1.rank) == Enum.to_list(1..10)
    assert Enum.map(repositories, & &1.full_name) |> List.first() == "fixture-org/alpha"
    assert List.last(repositories).full_name == "fixture-org/kappa"

    first = List.first(repositories)
    assert first.url == "https://github.com/fixture-org/alpha"
    assert first.stars == 1_234
    assert first.stars_today == 0
    assert first.forks == 56
    assert first.description == "First & foremost fixture repository."
    assert first.language == "Elixir"
    assert first.observed_at == observed_at
    assert first.source_url == source_url
  end

  test "preserves missing daily stars and optional fields as nil" do
    assert {:ok, repositories} = Parser.parse(@fixture)
    third = Enum.at(repositories, 2)

    assert third.stars_today == nil
    assert third.forks == nil
    assert third.description == nil
  end

  test "ignores navigation and sponsored Box rows that are not article cards" do
    assert {:ok, repositories} = Parser.parse(@fixture)
    refute Enum.any?(repositories, &(&1.full_name == "not/a/repository"))
    assert length(repositories) == 10
  end

  test "fails closed for empty pages and pages with fewer than ten cards" do
    assert {:error, :no_repository_cards} = Parser.parse("<html><body>Sign in</body></html>")
    assert {:error, {:too_few_repositories, 1}} = Parser.parse(card("one", "1"))
  end

  test "fails closed when a required star count or repository URL is malformed" do
    missing_stars = card("one", nil) <> Enum.map_join(2..10, fn n -> card("repo-#{n}", "1") end)
    assert {:error, {:invalid_repository, 1, :stars}} = Parser.parse(missing_stars)

    invalid_url = String.replace(card("one", "1"), "/fixture-org/one", "/fixture-org/repo?query")
    invalid_url = invalid_url <> Enum.map_join(2..10, fn n -> card("repo-#{n}", "1") end)
    assert {:error, {:invalid_repository, 1, :repository_url}} = Parser.parse(invalid_url)
  end

  test "rejects duplicate repositories instead of publishing duplicate entries" do
    duplicate =
      card("same", "1") <>
        Enum.map_join(2..9, fn n -> card("repo-#{n}", "1") end) <>
        card("same", "1")

    assert {:error, {:duplicate_repository, "fixture-org/same"}} = Parser.parse(duplicate)
  end

  test "rejects non-HTML input" do
    assert {:error, :not_html} = Parser.parse(:not_html)
    assert {:error, :not_html} = Parser.parse("GitHub is temporarily unavailable")
  end

  defp card(repo, stars) do
    stars_link =
      if stars, do: "<a href=\"/fixture-org/#{repo}/stargazers\">#{stars}</a>", else: ""

    """
    <article class="Box-row">
      <h2><a href="/fixture-org/#{repo}">fixture-org / #{repo}</a></h2>
      #{stars_link}
      <span itemprop="programmingLanguage">Elixir</span>
    </article>
    """
  end
end
