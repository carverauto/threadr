defmodule ThreadrWeb.PageControllerTest do
  use ThreadrWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    html = html_response(conn, 200)
    assert html =~ "Build tenant-scoped intelligence graphs from live chat streams."
    assert html =~ "Create an account"
    assert html =~ "Graph explorer"
  end
end
