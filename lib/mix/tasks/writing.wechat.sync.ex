defmodule Mix.Tasks.Writing.Wechat.Sync do
  use Mix.Task

  @shortdoc "同步编辑后的 GitHub Trending Markdown 到公众号草稿"

  @impl Mix.Task
  def run([path]) do
    Mix.Task.run("app.config")
    {:ok, _started} = Application.ensure_all_started(:req)

    case Writing.Trending.Sync.sync_file(path) do
      :ok -> Mix.shell().info("公众号草稿已同步，并已创建文章内容提交。")
      {:error, reason} -> Mix.raise("公众号草稿同步失败：#{inspect(reason)}")
    end
  end

  def run(_args) do
    Mix.raise("用法：mix writing.wechat.sync content/drafts/<trending-article>.md")
  end
end
