defmodule ThreadrWeb.PageController do
  use ThreadrWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
