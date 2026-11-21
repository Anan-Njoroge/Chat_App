defmodule ChatServerWeb.PageController do
  use ChatServerWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
