defmodule Writing.Trending.GitHub do
  @moduledoc false

  alias Writing.Trending.Repository

  @periods ~w(daily weekly monthly)
  @base_url "https://github.com"
  @api_url "https://api.github.com"

  def periods, do: @periods

  def fetch_trending(language, period) when period in @periods do
    path = if language, do: "/trending/#{URI.encode(language)}", else: "/trending"
    url = @base_url <> path <> "?since=#{period}"

    case Req.get(url,
           headers: [{"user-agent", "writing-github-trending"}],
           receive_timeout: 20_000,
           retry: false
         ) do
      {:ok, %{status: 200, body: html}} when is_binary(html) -> parse_trending(html, period)
      {:ok, %{status: status}} -> {:error, {:trending_http_status, status, url}}
      {:error, reason} -> {:error, {:trending_request_failed, url, reason}}
    end
  end

  def parse_trending(html, period) when is_binary(html) and period in @periods do
    with {:ok, document} <- Floki.parse_document(html),
         rows when rows != [] <- Floki.find(document, "article.Box-row"),
         repositories <- rows |> Enum.with_index(1) |> Enum.map(&parse_row(&1, period)),
         true <- Enum.all?(repositories, &match?(%Repository{}, &1)) do
      {:ok, repositories}
    else
      [] -> {:error, :trending_page_has_no_repositories}
      false -> {:error, :trending_page_has_invalid_repository}
      {:error, reason} -> {:error, {:trending_html_parse_failed, reason}}
    end
  end

  def fetch_details(%Repository{} = repository) do
    url = @api_url <> "/repos/" <> repository.full_name

    with {:ok, response} <- github_get(url, [{"accept", "application/vnd.github+json"}]),
         %{status: 200, body: metadata} <- response,
         true <- is_map(metadata),
         {:ok, readme} <- fetch_readme(repository.full_name) do
      total_stars = metadata["stargazers_count"]
      forks = metadata["forks_count"]

      {:ok,
       %{
         repository
         | description: metadata["description"] || repository.description,
           language: metadata["language"] || repository.language,
           total_stars: count_text(total_stars) || repository.total_stars,
           forks: count_text(forks) || repository.forks,
           topics: metadata["topics"] || [],
           readme: String.slice(readme, 0, 8_000)
       }}
    else
      {:ok, %{status: status}} ->
        {:error, {:github_repository_status, status, repository.full_name}}

      false ->
        {:error, {:invalid_github_repository_response, repository.full_name}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_row({row, rank}, period) do
    with [href] <- Floki.attribute(row, "h2 a", "href"),
         [owner, repo] <- href |> String.trim("/") |> String.split("/", parts: 2),
         true <- owner != "" and repo != "" do
      full_name = owner <> "/" <> String.trim_trailing(repo, ".git")

      %Repository{
        full_name: full_name,
        url: @base_url <> "/" <> full_name,
        rank: rank,
        description: text(row, "p.col-9"),
        language: text(row, "span[itemprop='programmingLanguage']"),
        total_stars: text(row, "a[href$='/stargazers']"),
        period_stars: text(row, ".float-sm-right"),
        forks: text(row, "a[href$='/forks']"),
        topics: [],
        readme: nil,
        period: period
      }
    else
      _ -> nil
    end
  end

  defp text(row, selector) do
    case row
         |> Floki.find(selector)
         |> Floki.text(sep: " ")
         |> String.replace(~r/\s+/, " ")
         |> String.trim() do
      "" -> nil
      value -> value
    end
  end

  defp fetch_readme(full_name) do
    url = @api_url <> "/repos/" <> full_name <> "/readme"

    case github_get(url, [{"accept", "application/vnd.github.raw+json"}], decode_body: false) do
      {:ok, %{status: 200, body: readme}} when is_binary(readme) ->
        {:ok, readme}

      {:ok, %{status: 404}} ->
        {:ok, ""}

      {:ok, %{status: status}} ->
        {:error, {:github_readme_status, status, full_name}}

      {:error, reason} ->
        {:error, {:github_readme_request_failed, full_name, reason}}
    end
  end

  defp github_get(url, headers, options \\ []) do
    token = Application.get_env(:writing, :github_token)
    headers = if token, do: [{"authorization", "Bearer " <> token} | headers], else: headers

    request_options =
      [
        headers: [{"user-agent", "writing-github-trending"} | headers],
        receive_timeout: 20_000,
        retry: false
      ] ++ options

    case Req.get(url, request_options) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, {:github_request_failed, url, error_type(reason)}}
    end
  end

  defp error_type(%{__struct__: module}), do: module
  defp error_type(_reason), do: :request_failed

  defp count_text(value) when is_integer(value), do: Integer.to_string(value)
  defp count_text(_value), do: nil
end
