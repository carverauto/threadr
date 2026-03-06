defmodule ThreadrWeb.MetricsController do
  use ThreadrWeb, :controller

  def show(conn, _params) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, TelemetryMetricsPrometheus.Core.scrape(:threadr_prometheus_metrics))
  end
end
