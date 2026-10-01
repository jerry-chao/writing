defmodule Writing.Trending.Content do
  @moduledoc false

  alias Writing.Trending.Article

  def load(path) do
    case File.read(path) do
      {:ok, markdown} -> parse(markdown)
      {:error, :enoent} -> {:ok, nil}
      {:error, reason} -> {:error, {:read_article_failed, path, reason}}
    end
  end

  def parse(markdown) when is_binary(markdown) do
    case Regex.run(~r/\A---\s*\n(.*?)\n---\s*\n(.*)\z/s, markdown, capture: :all_but_first) do
      [frontmatter, body] ->
        case YamlElixir.read_from_string(frontmatter) do
          {:ok, fields} when is_map(fields) -> {:ok, %{fields: fields, body: body}}
          {:ok, _} -> {:error, :invalid_article_frontmatter}
          {:error, reason} -> {:error, {:invalid_article_frontmatter, reason}}
        end

      _ ->
        {:error, :missing_article_frontmatter}
    end
  end

  def write(path, article) do
    content = Article.markdown(article)
    temporary = path <> ".tmp." <> Integer.to_string(System.unique_integer([:positive]))

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(temporary, content, [:binary, :exclusive]),
         :ok <- File.rename(temporary, path) do
      :ok
    else
      {:error, reason} ->
        File.rm(temporary)
        {:error, {:write_article_failed, path, reason}}
    end
  end

  def backwrite_wechat_ids(path, %{draft_media_id: draft_id, thumb_media_id: thumb_id}) do
    with {:ok, %{fields: fields, body: body}} <- load(path),
         updated_fields <-
           fields
           |> Map.put("draft_media_id", draft_id)
           |> Map.put("thumb_media_id", thumb_id),
         :ok <- write_markdown(path, updated_fields, body) do
      :ok
    else
      {:error, _reason} = error -> error
      {:ok, nil} -> {:error, :article_not_found}
    end
  end

  def check_git(repo_path, article_path) do
    relative_path = Path.relative_to(article_path, repo_path)

    with true <- String.starts_with?(relative_path, "content/drafts/"),
         {:ok, status} <- git(repo_path, ["status", "--porcelain", "--untracked-files=all"]),
         :ok <- only_article_changed(status, relative_path),
         {:ok, staged} <- git(repo_path, ["diff", "--cached", "--name-only"]),
         :ok <- only_staged_article(staged, relative_path) do
      :ok
    else
      false -> {:error, :article_path_outside_drafts}
      {:error, _reason} = error -> error
    end
  end

  def commit(repo_path, article_path, slug) do
    relative_path = Path.relative_to(article_path, repo_path)

    with :ok <- check_git(repo_path, article_path),
         {:ok, _output} <- git(repo_path, ["add", "--", relative_path]),
         {:ok, staged} <- git(repo_path, ["diff", "--cached", "--name-only"]),
         :ok <- only_staged_article(staged, relative_path),
         :ok <- commit_if_changed(repo_path, relative_path, slug) do
      :ok
    else
      {:error, _reason} = error -> error
    end
  end

  defp only_article_changed(status, relative_path) do
    paths =
      status
      |> String.split("\n", trim: true)
      |> Enum.map(&String.slice(&1, 3..-1//1))
      |> Enum.reject(&(&1 == relative_path))

    if paths == [], do: :ok, else: {:error, {:other_git_changes_present, paths}}
  end

  defp only_staged_article(staged, relative_path) do
    paths = String.split(staged, "\n", trim: true) |> Enum.reject(&(&1 == relative_path))
    if paths == [], do: :ok, else: {:error, {:other_staged_changes_present, paths}}
  end

  defp commit_if_changed(repo_path, relative_path, slug) do
    case git(repo_path, ["diff", "--cached", "--quiet", "--", relative_path]) do
      {:ok, _output} ->
        :ok

      {:error, {:git_exit, 1, _output}} ->
        case git(repo_path, ["commit", "-m", "content: 新增 #{slug} 草稿"]) do
          {:ok, _output} -> :ok
          {:error, reason} -> {:error, {:content_commit_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:content_commit_check_failed, reason}}
    end
  end

  defp git(repo_path, args) do
    case System.cmd("git", args, cd: repo_path, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, status} -> {:error, {:git_exit, status, String.trim(output)}}
    end
  end

  defp write_markdown(path, fields, body) do
    frontmatter =
      fields
      |> Enum.sort_by(fn {key, _value} -> to_string(key) end)
      |> Enum.map_join("\n", fn {key, value} -> "#{key}: #{yaml_value(value)}" end)

    content = "---\n#{frontmatter}\n---\n\n#{body}"
    temporary = path <> ".tmp." <> Integer.to_string(System.unique_integer([:positive]))

    with :ok <- File.write(temporary, content, [:binary, :exclusive]),
         :ok <- File.rename(temporary, path) do
      :ok
    else
      {:error, reason} ->
        File.rm(temporary)
        {:error, {:write_article_failed, path, reason}}
    end
  end

  defp yaml_value(nil), do: "null"
  defp yaml_value(value) when is_binary(value), do: Jason.encode!(value)
  defp yaml_value(value) when is_list(value), do: Jason.encode!(value)
  defp yaml_value(%Date{} = value), do: Date.to_iso8601(value)
  defp yaml_value(value) when is_map(value), do: Jason.encode!(value)
  defp yaml_value(value) when is_atom(value), do: value |> Atom.to_string() |> Jason.encode!()
  defp yaml_value(value), do: to_string(value)
end
