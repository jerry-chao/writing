defmodule WritingWeb.PageController do
  use WritingWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
