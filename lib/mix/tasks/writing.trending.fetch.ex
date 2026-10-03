defmodule Mix.Tasks.Writing.Trending.Fetch do
  @moduledoc """
  Fetches and parses a GitHub Trending page without writing files.

  The command is read-only by default. `--dry-run` makes that intent explicit;
  draft file generation is handled by a separate task.
  """

  use Mix.Task

  alias Writing.Trending.{GitHub, Parser}

  @shortdoc "Fetches GitHub Trending repositories (read-only)"
  @switches [
    language: :string,
    since: :string,
    format: :string,
    dry_run: :boolean,
    help: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    {opts, rest, invalid} = OptionParser.parse(args, strict: @switches)

    cond do
      opts[:help] ->
        Mix.shell().info(@moduledoc)

      rest != [] or invalid != [] ->
        Mix.raise("invalid arguments: #{inspect({rest, invalid})}")

      true ->
        fetch_and_print(opts)
    end
  end

  defp fetch_and_print(opts) do
    language = Keyword.get(opts, :language, "elixir")
    since = Keyword.get(opts, :since, "daily")
    format = Keyword.get(opts, :format, "text")

    unless format in ["text", "json"] do
      Mix.raise("--format must be either text or json")
    end

    ensure_req_started!()

    with {:ok, snapshot} <- GitHub.fetch(language, since),
         {:ok, repositories} <-
           Parser.parse(snapshot.html,
             language: language,
             source_url: snapshot.source_url,
             observed_at: snapshot.observed_at
           ) do
      print_result(repositories, snapshot, format)
    else
      {:error, reason} -> Mix.raise("GitHub Trending fetch failed: #{format_error(reason)}")
    end
  end

  defp ensure_req_started! do
    case Application.ensure_all_started(:req) do
      {:ok, _started} -> :ok
      {:error, reason} -> Mix.raise("could not start Req: #{inspect(reason)}")
    end
  end

  defp print_result(repositories, snapshot, "json") do
    output = %{
      source_url: snapshot.source_url,
      observed_at: DateTime.to_iso8601(snapshot.observed_at),
      repositories: Enum.map(repositories, &repository_json/1)
    }

    Mix.shell().info(Jason.encode!(output, pretty: true))
  end

  defp print_result(repositories, snapshot, "text") do
    Mix.shell().info("GitHub Trending · #{length(repositories)} repositories · read-only")
    Mix.shell().info("Source: #{snapshot.source_url}")
    Mix.shell().info("Observed at: #{DateTime.to_iso8601(snapshot.observed_at)}")

    Enum.each(repositories, fn repository ->
      today =
        if is_integer(repository.stars_today),
          do: "+#{repository.stars_today} today",
          else: "daily count unavailable"

      Mix.shell().info(
        "#{repository.rank}. #{repository.full_name} — #{repository.stars} stars, #{today}"
      )
    end)
  end

  defp repository_json(repository) do
    %{
      rank: repository.rank,
      full_name: repository.full_name,
      url: repository.url,
      description: repository.description,
      stars: repository.stars,
      stars_today: repository.stars_today,
      forks: repository.forks,
      language: repository.language
    }
  end

  defp format_error({:http_status, status}), do: "unexpected HTTP status #{status}"

  defp format_error({:unexpected_content_type, types}),
    do: "unexpected content type #{inspect(types)}"

  defp format_error({:request_failed, %Req.TransportError{reason: reason}}),
    do: "network request failed (#{inspect(reason)})"

  defp format_error({:request_failed, _reason}), do: "network request failed"
  defp format_error(reason), do: inspect(reason)
end
