defmodule Writing.Trending.GitHubTest do
  use ExUnit.Case, async: true

  alias Writing.Trending.GitHub

  setup {Req.Test, :verify_on_exit!}

  test "fetches the selected page and returns its provenance" do
    Req.Test.expect(__MODULE__, fn conn ->
      assert conn.request_path == "/trending/elixir"
      assert conn.query_string == "since=daily"
      assert Plug.Conn.get_req_header(conn, "user-agent") != []
      Req.Test.html(conn, "<html><body>trending</body></html>")
    end)

    assert {:ok, result} =
             GitHub.fetch("elixir", "daily", req_options: [plug: {Req.Test, __MODULE__}])

    assert result.html =~ "trending"
    assert result.source_url == "https://github.com/trending/elixir?since=daily"
    assert %DateTime{time_zone: "Etc/UTC"} = result.observed_at
  end

  test "returns a typed error for non-success HTTP status" do
    Req.Test.stub(__MODULE__, fn conn -> Plug.Conn.send_resp(conn, 403, "Forbidden") end)

    assert {:error, {:http_status, 403}} =
             GitHub.fetch("elixir", "daily",
               req_options: [plug: {Req.Test, __MODULE__}, retry: false]
             )
  end

  test "rejects non-HTML successful responses" do
    Req.Test.stub(__MODULE__, &Req.Test.text(&1, "not HTML"))

    assert {:error, {:unexpected_content_type, ["text/plain; charset=utf-8"]}} =
             GitHub.fetch("elixir", "daily",
               req_options: [plug: {Req.Test, __MODULE__}, retry: false]
             )
  end

  test "reports network errors without pretending the page is empty" do
    Req.Test.stub(__MODULE__, &Req.Test.transport_error(&1, :timeout))

    assert {:error, {:request_failed, %Req.TransportError{reason: :timeout}}} =
             GitHub.fetch("elixir", "daily",
               req_options: [plug: {Req.Test, __MODULE__}, retry: false]
             )
  end

  test "rejects invalid language and range before making a request" do
    assert {:error, :invalid_language} = GitHub.fetch("../elixir")
    assert {:error, :invalid_range} = GitHub.fetch("elixir", "yearly")
  end
end
