defmodule Writing.Trending.ArticleTest do
  use ExUnit.Case, async: true

  alias Writing.Trending.{Article, Content, Repository}

  test "renders a Markdown draft with YAML frontmatter and non-clickable GitHub URLs" do
    repository = %Repository{
      full_name: "owner/project",
      url: "https://github.com/owner/project",
      rank: 1,
      language: "Elixir",
      total_stars: "1,234",
      period_stars: "20 stars today",
      topics: [],
      description: "Example",
      readme: "README",
      period: "daily"
    }

    analysis = %{
      "digest" => "今日 Elixir 与 AI 项目趋势",
      "overview" => "工具链和 AI 集成项目较多。",
      "projects" => [
        %{
          "full_name" => "owner/project",
          "purpose" => "处理数据",
          "technology" => "Elixir",
          "use_case" => "构建服务",
          "why_trending" => "榜单显示近期关注增加"
        }
      ]
    }

    assert {:ok, article} =
             Article.build(~D[2026-10-01], [{"daily", [repository], []}], analysis)

    markdown = Article.markdown(article)
    assert {:ok, %{fields: fields}} = Content.parse(markdown)
    assert fields["title"] == article.title
    assert fields["date"] == "2026-10-01"
    assert fields["cover"] == "content/assets/github-trending/cover.jpg"
    assert markdown =~ "`https://github.com/owner/project`"

    html = Article.html(article)
    assert html =~ "<code>https://github.com/owner/project</code>"
    assert {:ok, document} = Floki.parse_document(html)
    assert Floki.find(document, "a") == []
  end

  test "rejects generated analysis that omits a listed repository" do
    analysis = %{"digest" => "摘要", "overview" => "趋势", "projects" => []}

    assert {:error, {:missing_analysis, ["owner/project"]}} =
             Article.build(
               ~D[2026-10-01],
               [{"daily", [repository()], []}],
               analysis
             )
  end

  defp repository do
    %Repository{full_name: "owner/project", url: "https://github.com/owner/project", rank: 1}
  end
end
