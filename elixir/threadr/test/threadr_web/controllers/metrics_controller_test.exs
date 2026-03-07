defmodule ThreadrWeb.MetricsControllerTest do
  use ThreadrWeb.ConnCase

  test "GET /metrics", %{conn: conn} do
    _conn = get(conn, "/health/ready")

    conn =
      Phoenix.ConnTest.build_conn()
      |> get("/metrics")

    assert response_content_type(conn, :txt) =~ "text/plain"

    body = response(conn, 200)
    assert body =~ "# TYPE phoenix_router_dispatch_stop_duration histogram"
    assert body =~ "threadr_repo_query_total_time"
  end
end
