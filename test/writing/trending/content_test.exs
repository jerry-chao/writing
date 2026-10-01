defmodule Writing.Trending.ContentTest do
  use ExUnit.Case, async: true

  alias Writing.Trending.Content

  test "backwrites WeChat identifiers while preserving edited Markdown" do
    path =
      Path.join(
        System.tmp_dir!(),
        "trending-#{System.unique_integer([:positive])}.md"
      )

    markdown = """
    ---
    title: "Trending"
    draft_media_id: null
    thumb_media_id: null
    ---

    ## Human-edited analysis
    """

    File.write!(path, markdown)
    on_exit(fn -> File.rm(path) end)

    assert :ok =
             Content.backwrite_wechat_ids(path, %{
               draft_media_id: "draft-id",
               thumb_media_id: "cover-id"
             })

    assert {:ok, %{fields: fields, body: body}} = Content.load(path)
    assert fields["draft_media_id"] == "draft-id"
    assert fields["thumb_media_id"] == "cover-id"
    assert body =~ "Human-edited analysis"
  end
end
