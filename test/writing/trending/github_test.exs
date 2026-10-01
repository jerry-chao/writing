defmodule Writing.Trending.GitHubTest do
  use ExUnit.Case, async: true

  alias Writing.Trending.GitHub

  test "parses repositories in page order and keeps total and period stars separate" do
    html = """
    <article class="Box-row">
      <h2><a href="/owner/first">owner/first</a></h2>
      <p class="col-9">A &amp; B project</p>
      <span itemprop="programmingLanguage">Elixir</span>
      <a href="/owner/first/stargazers">1,234</a>
      <a href="/owner/first/forks">56</a>
      <span class="float-sm-right">25 stars today</span>
    </article>
    <article class="Box-row">
      <h2><a href="/owner/second">owner/second</a></h2>
    </article>
    """

    assert {:ok, [first, second]} = GitHub.parse_trending(html, "daily")
    assert first.full_name == "owner/first"
    assert first.rank == 1
    assert first.description == "A & B project"
    assert first.total_stars == "1,234"
    assert first.period_stars == "25 stars today"
    assert second.rank == 2
    assert second.language == nil
  end

  test "fails explicitly when GitHub changes or blocks the Trending markup" do
    assert {:error, :trending_page_has_no_repositories} =
             GitHub.parse_trending("<html><body>challenge</body></html>", "weekly")
  end
end
