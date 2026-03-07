defmodule ThreadrWeb.HealthControllerTest do
  use ThreadrWeb.ConnCase

  test "GET /health/live", %{conn: conn} do
    conn = get(conn, "/health/live")

    assert json_response(conn, 200) == %{"status" => "ok"}
  end

  test "GET /health/ready", %{conn: conn} do
    conn = get(conn, "/health/ready")

    assert json_response(conn, 200) == %{"status" => "ok"}
  end
end
