defmodule Writing.Trending.Sync do
  @moduledoc false

  alias Writing.Trending.Content
  alias Writing.Wechat.Drafts

  def sync_file(path) when is_binary(path) do
    repo_path = Application.fetch_env!(:writing, :trending_repo_path)
    path = Path.expand(path, repo_path)
    relative_path = Path.relative_to(path, repo_path)

    with true <- String.starts_with?(relative_path, "content/drafts/"),
         :ok <- ensure_regular_file(path),
         :ok <- Content.check_git(repo_path, path),
         {:ok, %{fields: fields, body: body}} <- Content.load(path),
         :ok <- validate_source(fields, body),
         {:ok, html} <- render_html(body),
         :ok <- validate_html(html),
         article <- article_fields(fields),
         cover_path <- cover_path(repo_path, fields),
         :ok <- ensure_regular_file(cover_path),
         {:ok, ids} <- Drafts.upsert(article, html, cover_path),
         :ok <- Content.backwrite_wechat_ids(path, ids),
         :ok <- Content.commit(repo_path, path, article.slug) do
      :ok
    else
      false -> {:error, :only_draft_files_can_be_synced}
      {:error, _reason} = error -> error
      {:ok, nil} -> {:error, :article_not_found}
    end
  end

  defp validate_source(fields, body) do
    with true <- is_map(fields),
         true <- is_binary(body),
         true <- String.starts_with?(Map.get(fields, "slug", ""), "github-trending-"),
         true <- Map.get(fields, "cover") == "content/assets/github-trending/cover.jpg",
         false <- Regex.match?(~r/!\[[^\]]*\]\([^)]+\)/, body),
         :ok <- required_string(fields, "title"),
         :ok <- required_string(fields, "author"),
         :ok <- required_string(fields, "digest"),
         :ok <- required_string(fields, "slug"),
         :ok <- required_string(fields, "cover"),
         true <- String.length(fields["title"]) <= 32,
         true <- String.length(fields["author"]) <= 16,
         true <- String.length(fields["digest"]) <= 120 do
      :ok
    else
      false -> {:error, :invalid_trending_article_fields}
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_trending_article_fields}
    end
  end

  defp render_html(body) do
    MDEx.to_html(body, sanitize: MDEx.Document.default_sanitize_options())
  end

  defp validate_html(html) do
    with {:ok, document} <- Floki.parse_document(html),
         true <- String.length(html) < 18_000,
         true <- byte_size(html) < 1_000_000,
         :ok <- reject_html_elements(document, "a", :article_contains_clickable_links),
         :ok <- reject_html_elements(document, "img", :article_contains_images) do
      :ok
    else
      false -> {:error, :article_exceeds_wechat_content_limits}
      {:rejected, reason} -> {:error, reason}
      {:error, reason} -> {:error, {:article_html_invalid, reason}}
    end
  end

  defp reject_html_elements(document, selector, reason) do
    if Floki.find(document, selector) == [], do: :ok, else: {:rejected, reason}
  end

  defp article_fields(fields) do
    %{
      title: fields["title"],
      author: fields["author"],
      digest: fields["digest"],
      slug: fields["slug"],
      draft_media_id: fields["draft_media_id"],
      thumb_media_id: fields["thumb_media_id"]
    }
  end

  defp cover_path(repo_path, fields) do
    Path.expand(fields["cover"], repo_path)
  end

  defp required_string(fields, key) do
    case Map.get(fields, key) do
      value when is_binary(value) and value != "" -> :ok
      _ -> {:error, {:missing_article_field, key}}
    end
  end

  defp ensure_regular_file(path) do
    case File.lstat(path) do
      {:ok, %File.Stat{type: :regular}} -> :ok
      {:ok, _stat} -> {:error, {:path_must_be_a_regular_file, path}}
      {:error, reason} -> {:error, {:file_unavailable, path, reason}}
    end
  end
end
