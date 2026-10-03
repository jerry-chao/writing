defmodule Writing.Content.TrendingDraft do
  @moduledoc """
  Renders a verified GitHub Trending snapshot into a deterministic article draft.

  This module produces content only. It never fetches data, writes files, or
  calls the WeChat API.
  """

  alias Writing.Trending.Repository

  @title "GitHub Elixir 日榜 Top 10"
  @author "写作应用"
  @digest "按 GitHub Trending 页面顺序整理 Elixir 日榜前十，列出项目简介与页面显示的 Stars 数据；榜单顺序不等于今日新增 Stars 排名。"

  @type rendered_draft :: %{
          date: Date.t(),
          slug: String.t(),
          filename: String.t(),
          cover_path: String.t(),
          title: String.t(),
          markdown: String.t()
        }

  @doc "Renders exactly ten ordered repositories as one Markdown article."
  @spec render([Repository.t()], keyword()) :: {:ok, rendered_draft()} | {:error, atom()}
  def render(repositories, opts \\ []) do
    date = Keyword.get(opts, :date, Date.utc_today())

    with :ok <- validate_date(date),
         :ok <- validate_top_ten(repositories),
         {:ok, source_url} <- source_url(repositories, opts) do
      slug = "github-elixir-trending-#{Date.to_iso8601(date) |> String.replace("-", "")}"
      cover_path = "content/assets/#{slug}/cover.jpg"

      {:ok,
       %{
         date: date,
         slug: slug,
         filename: "#{Date.to_iso8601(date)}-#{slug}.md",
         cover_path: cover_path,
         title: @title,
         markdown: render_markdown(repositories, date, slug, cover_path, source_url)
       }}
    end
  end

  defp validate_date(%Date{}), do: :ok
  defp validate_date(_date), do: {:error, :invalid_date}

  defp validate_top_ten(repositories) when is_list(repositories) do
    ranks = Enum.map(repositories, & &1.rank)

    if ranks == Enum.to_list(1..10) do
      :ok
    else
      {:error, :expected_ordered_top_ten}
    end
  end

  defp validate_top_ten(_repositories), do: {:error, :expected_ordered_top_ten}

  defp source_url(repositories, opts) do
    source_url = Keyword.get(opts, :source_url) || List.first(repositories).source_url

    case URI.parse(source_url) do
      %URI{scheme: "https", host: "github.com"} ->
        {:ok, source_url}

      _ ->
        {:error, :invalid_source_url}
    end
  end

  defp render_markdown(repositories, date, slug, cover_path, source_url) do
    frontmatter = [
      "---",
      "title: #{yaml_string(@title)}",
      "author: #{yaml_string(@author)}",
      "digest: #{yaml_string(@digest)}",
      "slug: #{yaml_string(slug)}",
      "date: #{yaml_string(Date.to_iso8601(date))}",
      "cover: #{yaml_string(cover_path)}",
      "tags: [GitHub, Elixir, 开源项目, Trending]",
      "content_source_url: #{yaml_string(source_url)}",
      "need_open_comment: 0",
      "only_fans_can_comment: 0",
      "",
      "# 脚本回写，勿手填",
      "# draft_media_id:",
      "# thumb_media_id:",
      "---"
    ]

    body =
      [
        "",
        "GitHub Trending 的 Elixir 日榜快照，抓取日期为 #{Date.to_iso8601(date)}。以下按页面当前展示顺序整理；GitHub 页面结构和榜单会变化，本列表不代表按今日新增 Stars 重新排序。",
        "",
        "## 今日榜单前十",
        ""
      ] ++
        Enum.flat_map(repositories, &render_repository/1) ++
        [
          "## 阅读说明",
          "",
          "Stars 与今日新增 Stars 按抓取时页面显示记录。项目简介来自 Trending 页面，不构成项目质量或维护状态评估；选型前请进一步查看项目文档、近期维护情况和许可证。",
          ""
        ]

    Enum.join(frontmatter ++ body, "\n")
  end

  defp render_repository(repository) do
    daily_stars =
      case repository.stars_today do
        count when is_integer(count) -> "今日新增 Stars：#{count}"
        nil -> "页面未显示今日新增 Stars"
      end

    description =
      case clean_description(repository.description) do
        "" -> "页面未提供简介。"
        text -> text
      end

    [
      "### #{repository.rank}. `#{repository.full_name}`",
      "",
      description,
      "",
      "页面显示总 Stars：#{repository.stars}；#{daily_stars}。",
      ""
    ]
  end

  defp clean_description(nil), do: ""

  defp clean_description(description) do
    description
    |> String.replace(~r/https?:\/\/\S+/u, "（链接已省略）")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> escape_markdown()
  end

  defp escape_markdown(text) do
    Enum.reduce(["`", "[", "]", "(", ")", "*", "_", "#", "<", ">"], text, fn char, acc ->
      String.replace(acc, char, "")
    end)
  end

  defp yaml_string(value), do: Jason.encode!(value)
end
