defmodule Writing.Content.TrendingDraftTest do
  use ExUnit.Case, async: true

  alias Writing.Content.TrendingDraft
  alias Writing.Trending.Repository

  @observed_at ~U[2026-10-04 08:00:00Z]
  @source_url "https://github.com/trending/elixir?since=daily"

  test "renders a deterministic article with a unique date-based slug and asset path" do
    date = ~D[2026-10-04]
    repositories = repositories()

    assert {:ok, draft} =
             TrendingDraft.render(repositories, date: date, source_url: @source_url)

    assert draft.slug == "github-elixir-trending-20261004"
    assert draft.filename == "2026-10-04-github-elixir-trending-20261004.md"
    assert draft.cover_path == "content/assets/#{draft.slug}/cover.jpg"

    assert {:ok, second_render} =
             TrendingDraft.render(repositories, date: date, source_url: @source_url)

    assert draft.markdown == second_render.markdown
  end

  test "includes valid frontmatter and all ten entries in original rank order" do
    assert {:ok, draft} =
             TrendingDraft.render(repositories(), date: ~D[2026-10-04], source_url: @source_url)

    assert draft.markdown =~ "title: \"GitHub Elixir 日榜 Top 10\""
    assert draft.markdown =~ "content_source_url: \"#{@source_url}\""
    assert length(Regex.scan(~r/^### \d+\./m, draft.markdown)) == 10
    assert draft.markdown =~ "### 1. `fixture-org/repo-1`"
    assert draft.markdown =~ "### 10. `fixture-org/repo-10`"
    refute draft.markdown =~ "]("

    assert String.length(draft.title) <= 32
    assert String.length(frontmatter_value(draft.markdown, "digest")) <= 120
  end

  test "strips URLs from repository descriptions and distinguishes zero from missing daily stars" do
    [first | tail] = repositories()

    first = %{
      first
      | description: "Docs at https://example.com/path and [text](https://example.org)"
    }

    repositories = [first | tail]

    repositories =
      List.replace_at(repositories, 1, %{Enum.at(repositories, 1) | stars_today: nil})

    assert {:ok, draft} =
             TrendingDraft.render(repositories, date: ~D[2026-10-04], source_url: @source_url)

    refute draft.markdown =~ "https://example.com"
    refute draft.markdown =~ "https://example.org"
    assert draft.markdown =~ "今日新增 Stars：0"
    assert draft.markdown =~ "页面未显示今日新增 Stars"
  end

  test "rejects non-top-ten or incorrectly ordered input and invalid source URLs" do
    assert {:error, :expected_ordered_top_ten} =
             TrendingDraft.render(Enum.take(repositories(), 9), date: ~D[2026-10-04])

    out_of_order = List.replace_at(repositories(), 0, %{Enum.at(repositories(), 0) | rank: 2})

    assert {:error, :expected_ordered_top_ten} =
             TrendingDraft.render(out_of_order, date: ~D[2026-10-04], source_url: @source_url)

    assert {:error, :invalid_source_url} =
             TrendingDraft.render(repositories(),
               date: ~D[2026-10-04],
               source_url: "javascript:bad"
             )

    assert {:error, :invalid_source_url} =
             TrendingDraft.render(repositories(),
               date: ~D[2026-10-04],
               source_url: "https://example.com"
             )
  end

  defp repositories do
    for rank <- 1..10 do
      %Repository{
        rank: rank,
        full_name: "fixture-org/repo-#{rank}",
        url: "https://github.com/fixture-org/repo-#{rank}",
        description: "Description for repository #{rank}.",
        stars: rank * 100,
        stars_today: if(rank == 1, do: 0, else: rank),
        forks: rank,
        language: "Elixir",
        observed_at: @observed_at,
        source_url: @source_url
      }
    end
  end

  defp frontmatter_value(markdown, key) do
    [_, value] = Regex.run(~r/^#{Regex.escape(key)}: "(.*)"$/m, markdown)
    value
  end
end
