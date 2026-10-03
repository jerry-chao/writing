defmodule Writing.Trending.GitHub do
  @moduledoc """
  Fetches a GitHub Trending HTML page.

  GitHub does not provide an official Trending API, so callers must treat the
  returned HTML as an unstable external input and validate parsed results.
  """

  @base_url "https://github.com/trending"
  @user_agent "writing-trending-fetcher/0.1 (+https://github.com/jerry-chao/writing)"
  @allowed_ranges ~w(daily weekly monthly)
  @max_language_length 64

  @type result :: %{
          html: binary(),
          source_url: String.t(),
          observed_at: DateTime.t()
        }

  @doc "Fetches a language's Trending page for the selected range."
  @spec fetch(String.t(), String.t(), keyword()) :: {:ok, result()} | {:error, term()}
  def fetch(language \\ "elixir", since \\ "daily", opts \\ []) do
    with {:ok, source_url} <- source_url(language, since),
         {:ok, response} <- request(source_url, opts),
         :ok <- successful_status(response),
         :ok <- html_response(response) do
      {:ok,
       %{
         html: response.body,
         source_url: source_url,
         observed_at: DateTime.utc_now()
       }}
    end
  end

  defp source_url(language, since)
       when is_binary(language) and byte_size(language) > 0 and
              byte_size(language) <= @max_language_length and since in @allowed_ranges do
    if String.contains?(language, "/") or String.contains?(language, "..") do
      {:error, :invalid_language}
    else
      encoded_language = URI.encode(language, &URI.char_unreserved?/1)
      {:ok, "#{@base_url}/#{encoded_language}?since=#{since}"}
    end
  end

  defp source_url(_language, since) when since not in @allowed_ranges,
    do: {:error, :invalid_range}

  defp source_url(_language, _since), do: {:error, :invalid_language}

  defp request(url, opts) do
    request_opts = [
      headers: %{"user-agent" => @user_agent},
      retry: :safe_transient,
      max_retries: 2,
      receive_timeout: 15_000
    ]

    request_opts = Keyword.merge(request_opts, Keyword.get(opts, :req_options, []))

    case Req.get(url, request_opts) do
      {:ok, response} -> {:ok, response}
      {:error, reason} -> {:error, {:request_failed, reason}}
    end
  end

  defp successful_status(%Req.Response{status: 200}), do: :ok
  defp successful_status(%Req.Response{status: status}), do: {:error, {:http_status, status}}

  defp html_response(response) do
    content_types = Req.Response.get_header(response, "content-type")

    if Enum.any?(content_types, &html_content_type?/1) do
      :ok
    else
      {:error, {:unexpected_content_type, content_types}}
    end
  end

  defp html_content_type?(content_type) do
    content_type = String.downcase(content_type)

    String.starts_with?(content_type, "text/html") or
      String.starts_with?(content_type, "application/xhtml+xml")
  end
end
