defmodule Writing.Trending do
  @moduledoc false

  alias Writing.Trending.{Analyzer, Article, Content, GitHub, Repository, Schedule}
  alias Writing.Wechat.Drafts

  def generate_markdown(%Date{} = date) do
    repo_path = Application.fetch_env!(:writing, :trending_repo_path)
    article_path = article_path(repo_path, date)

    with false <- File.exists?(article_path),
         {:ok, _article} <- generate_article(date, article_path) do
      {:ok, article_path}
    else
      true -> {:error, :article_already_exists}
      {:error, _reason} = error -> error
    end
  end

  def run(%Date{} = date) do
    repo_path = Application.fetch_env!(:writing, :trending_repo_path)
    article_path = article_path(repo_path, date)
    cover_path = Path.join(repo_path, "content/assets/github-trending/cover.jpg")

    with :ok <- Content.check_git(repo_path, article_path),
         {:ok, article} <- generate_article(date, article_path),
         html <- Article.html(article),
         :ok <- validate_html(html),
         {:ok, ids} <- Drafts.upsert(article, html, cover_path),
         article <- %{
           article
           | draft_media_id: ids.draft_media_id,
             thumb_media_id: ids.thumb_media_id
         },
         :ok <- Content.write(article_path, article),
         :ok <- Content.commit(repo_path, article_path, article.slug) do
      :ok
    end
  end

  defp generate_article(date, article_path) do
    periods = Schedule.periods_for(date)

    with {:ok, pages} <- fetch_pages(periods),
         {:ok, details} <- fetch_all_details(pages),
         groups <- build_groups(periods, pages, details),
         {:ok, analysis} <- Analyzer.analyze(groups),
         {:ok, article} <- Article.build(date, groups, analysis),
         {:ok, existing} <- Content.load(article_path),
         article <- preserve_wechat_ids(article, existing),
         :ok <- Content.write(article_path, article) do
      {:ok, article}
    end
  end

  defp article_path(repo_path, date) do
    Path.join(repo_path, "content/drafts/#{Date.to_iso8601(date)}-github-trending.md")
  end

  defp fetch_pages(periods) do
    Enum.reduce_while(periods, {:ok, %{}}, fn period, {:ok, pages} ->
      with {:ok, elixir} <- GitHub.fetch_trending("elixir", Atom.to_string(period)),
           {:ok, all_languages} <- GitHub.fetch_trending(nil, Atom.to_string(period)) do
        {:cont, {:ok, Map.put(pages, period, {elixir, all_languages})}}
      else
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp fetch_all_details(pages) do
    repositories =
      pages
      |> Map.values()
      |> Enum.flat_map(fn {elixir, all_languages} -> elixir ++ all_languages end)
      |> Enum.uniq_by(& &1.full_name)

    repositories
    |> Task.async_stream(
      fn repository -> {repository.full_name, GitHub.fetch_details(repository)} end,
      max_concurrency: 4,
      timeout: :infinity,
      ordered: true
    )
    |> Enum.reduce_while({:ok, %{}}, fn
      {:ok, {full_name, {:ok, repository}}}, {:ok, acc} ->
        {:cont, {:ok, Map.put(acc, full_name, repository)}}

      {:ok, {_full_name, {:error, reason}}}, _acc ->
        {:halt, {:error, reason}}

      {:exit, reason}, _acc ->
        {:halt, {:error, {:github_enrichment_task_failed, reason}}}
    end)
  end

  defp build_groups(periods, pages, details) do
    Enum.map(periods, fn period ->
      {elixir_page, all_languages_page} = Map.fetch!(pages, period)

      elixir =
        elixir_page
        |> Enum.take(10)
        |> Enum.map(&enriched_copy(&1, details))

      ai =
        all_languages_page
        |> Enum.map(&enriched_copy(&1, details))
        |> Enum.filter(&ai_project?/1)
        |> Enum.take(10)

      {Atom.to_string(period), elixir, ai}
    end)
  end

  defp enriched_copy(repository, details) do
    enriched = Map.fetch!(details, repository.full_name)

    %{
      enriched
      | rank: repository.rank,
        period: repository.period,
        period_stars: repository.period_stars
    }
  end

  defp ai_project?(%Repository{} = repository) do
    strong_topics =
      ~w(ai artificial-intelligence machine-learning deep-learning llm generative-ai ai-agents rag embeddings inference)

    topics = Enum.map(repository.topics, &String.downcase/1)
    text = Enum.join([repository.description || "", repository.readme || ""], "\n")

    Enum.any?(topics, &(&1 in strong_topics)) or
      Regex.match?(
        ~r/\b(artificial intelligence|machine learning|deep learning|large language model|LLM|RAG|AI agent|generative AI|computer vision|natural language processing)\b|人工智能|机器学习|大语言模型/i,
        text
      )
  end

  defp preserve_wechat_ids(article, nil), do: article

  defp preserve_wechat_ids(article, %{fields: fields}) do
    %{
      article
      | draft_media_id: Map.get(fields, "draft_media_id"),
        thumb_media_id: Map.get(fields, "thumb_media_id")
    }
  end

  defp validate_html(html) do
    with {:ok, document} <- Floki.parse_document(html),
         true <- String.length(html) < 18_000,
         true <- byte_size(html) < 1_000_000,
         [] <- Floki.find(document, "a") do
      :ok
    else
      false -> {:error, :article_exceeds_wechat_content_limits}
      [_ | _] -> {:error, :article_contains_clickable_links}
      {:error, reason} -> {:error, {:article_html_invalid, reason}}
    end
  end
end
