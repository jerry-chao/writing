defmodule Writing.Trending.Article do
  @moduledoc false

  alias Writing.Trending.Repository

  def build(date, groups, analysis) do
    entries = Map.new(value(analysis, "projects"), &{value(&1, "full_name"), &1})

    with :ok <- validate_groups(groups, entries) do
      title = "GitHub 趋势 | #{Date.to_iso8601(date)}"

      article = %{
        title: title,
        digest: truncate(value(analysis, "digest"), 120),
        slug: "github-trending-#{Date.to_iso8601(date)}",
        date: Date.to_iso8601(date),
        author: "写作应用",
        cover: "content/assets/github-trending/cover.jpg",
        tags: ["GitHub", "Trending", "Elixir", "AI"],
        draft_media_id: nil,
        thumb_media_id: nil,
        published_at: nil,
        article_url: nil,
        groups: groups,
        overview: truncate(value(analysis, "overview"), 500),
        analyses: entries
      }

      {:ok, article}
    end
  end

  def markdown(article) do
    frontmatter =
      [
        {"title", article.title},
        {"author", article.author},
        {"digest", article.digest},
        {"slug", article.slug},
        {"date", article.date},
        {"cover", article.cover},
        {"tags", article.tags},
        {"content_source_url", nil},
        {"need_open_comment", 0},
        {"only_fans_can_comment", 0},
        {"draft_media_id", article.draft_media_id},
        {"thumb_media_id", article.thumb_media_id},
        {"published_at", article.published_at},
        {"article_url", article.article_url}
      ]
      |> Enum.map_join("\n", fn {key, value} -> "#{key}: #{yaml_value(value)}" end)

    markdown = """
    ---
    #{frontmatter}
    ---

    #{body_markdown(article)}
    """

    String.trim_trailing(markdown, "\n") <> "\n"
  end

  def html(article) do
    sections =
      Enum.map_join(article.groups, "\n", fn {period, elixir, ai} ->
        period_section(period, elixir, ai, article.analyses)
      end)

    overview = escape(article.overview)

    """
    <section style="font-size:16px;line-height:1.75;color:#273244;">
      <p>本期根据 GitHub Trending 页面整理，项目排名沿用页面顺序。项目地址以纯文本展示，不是可点击链接。</p>
      #{sections}
      <h2>整体观察</h2>
      <p>#{overview}</p>
      <p style="color:#748094;font-size:13px;">榜单按页面所示日榜、周榜或月榜统计；不是对历史自然周或自然月的回溯计算。</p>
    </section>
    """
  end

  def llm_projects(groups) do
    groups
    |> Enum.flat_map(fn {_period, elixir, ai} -> elixir ++ ai end)
    |> Enum.uniq_by(& &1.full_name)
  end

  defp period_section(period, elixir, ai, analyses) do
    period_title =
      case period do
        "daily" -> "日榜"
        "weekly" -> "周榜"
        "monthly" -> "月榜"
      end

    elixir_section = repository_list("Elixir", elixir, analyses)
    ai_section = if ai == [], do: "", else: repository_list("AI（全语言）", ai, analyses)

    """
    <h2>#{period_title}</h2>
    #{elixir_section}
    #{ai_section}
    """
  end

  defp repository_list(title, repositories, analyses) do
    projects =
      Enum.map_join(repositories, "\n", fn %Repository{} = repository ->
        analysis = Map.fetch!(analyses, repository.full_name)

        """
        <article style="margin:16px 0;padding-bottom:12px;border-bottom:1px solid #e8edf3;">
          <h3>#{repository.rank}. #{escape(repository.full_name)}</h3>
          <p>项目地址：<code>#{escape(repository.url)}</code></p>
          <p>语言：#{escape(repository.language || "未标注")} · Stars：#{escape(repository.total_stars || "暂无")} · #{escape(repository.period_stars || "周期增量未标注")}</p>
          <p><strong>用途：</strong>#{escape(analysis_text(analysis, "purpose"))}</p>
          <p><strong>主要技术：</strong>#{escape(analysis_text(analysis, "technology"))}</p>
          <p><strong>适用场景：</strong>#{escape(analysis_text(analysis, "use_case"))}</p>
          <p><strong>热度观察：</strong>#{escape(analysis_text(analysis, "why_trending"))}</p>
        </article>
        """
      end)

    """
    <h3>#{title} Top #{length(repositories)}</h3>
    #{projects}
    """
  end

  defp body_markdown(article) do
    sections =
      Enum.map_join(article.groups, "\n", fn {period, elixir, ai} ->
        header =
          case period do
            "daily" -> "## 日榜"
            "weekly" -> "## 周榜"
            "monthly" -> "## 月榜"
          end

        [
          header,
          markdown_list("Elixir", elixir, article.analyses),
          markdown_list("AI（全语言）", ai, article.analyses)
        ]
        |> Enum.reject(&(&1 == ""))
        |> Enum.join("\n\n")
      end)

    "#{sections}\n\n## 整体观察\n\n#{article.overview}\n"
  end

  defp markdown_list(_title, [], _analyses), do: ""

  defp markdown_list(title, repositories, analyses) do
    items =
      Enum.map_join(repositories, "\n\n", fn repository ->
        analysis = Map.fetch!(analyses, repository.full_name)

        """
        ### #{repository.rank}. #{repository.full_name}

        项目地址：`#{repository.url}`\\
        语言：#{repository.language || "未标注"} · Stars：#{repository.total_stars || "暂无"} · #{repository.period_stars || "周期增量未标注"}

        - 用途：#{analysis_text(analysis, "purpose")}
        - 主要技术：#{analysis_text(analysis, "technology")}
        - 适用场景：#{analysis_text(analysis, "use_case")}
        - 热度观察：#{analysis_text(analysis, "why_trending")}
        """
      end)

    "### #{title} Top #{length(repositories)}\n\n#{items}"
  end

  defp validate_groups(groups, entries) do
    missing =
      groups
      |> llm_projects()
      |> Enum.reject(&Map.has_key?(entries, &1.full_name))

    if missing == [],
      do: :ok,
      else: {:error, {:missing_analysis, Enum.map(missing, & &1.full_name)}}
  end

  defp truncate(text, limit) when is_binary(text), do: String.slice(text, 0, limit)

  defp analysis_text(analysis, field), do: analysis |> value(field) |> truncate(110)

  defp yaml_value(nil), do: "null"
  defp yaml_value(value) when is_binary(value), do: Jason.encode!(value)
  defp yaml_value(value) when is_list(value), do: Jason.encode!(value)
  defp yaml_value(value), do: to_string(value)

  defp escape(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp value(map, key) do
    Map.get(map, key) || Map.get(map, atom_key(key))
  end

  defp atom_key("digest"), do: :digest
  defp atom_key("overview"), do: :overview
  defp atom_key("projects"), do: :projects
  defp atom_key("full_name"), do: :full_name
  defp atom_key("purpose"), do: :purpose
  defp atom_key("technology"), do: :technology
  defp atom_key("use_case"), do: :use_case
  defp atom_key("why_trending"), do: :why_trending
end
