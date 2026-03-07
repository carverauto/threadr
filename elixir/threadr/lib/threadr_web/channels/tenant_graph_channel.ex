defmodule ThreadrWeb.TenantGraphChannel do
  use ThreadrWeb, :channel

  alias Threadr.ControlPlane.Service
  alias Threadr.TenantData.LiveUpdates
  alias Threadr.TenantData.GraphInspector
  alias Threadr.TenantData.GraphSnapshot

  @binary_magic "TGV1"
  @refresh_debounce_ms 250

  @impl true
  def join("graph:" <> subject_name, payload, socket) do
    user = %{id: socket.assigns.user_id}

    with {:ok, tenant, _membership} <- Service.get_user_tenant_by_subject_name(user, subject_name) do
      :ok = LiveUpdates.subscribe(subject_name)
      send(self(), :refresh_snapshot)

      {:ok,
       socket
       |> assign(:tenant, tenant)
       |> assign(:window, parse_window(payload || %{}))
       |> assign(:refresh_timer_ref, nil)}
    else
      _ -> {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_info(:refresh_snapshot, socket) do
    socket =
      socket
      |> assign(:refresh_timer_ref, nil)
      |> push_snapshot()

    {:noreply, socket}
  end

  def handle_info({:tenant_ingest, payload}, socket) do
    if payload_relevant_to_window?(payload, socket.assigns.window) do
      {:noreply, schedule_snapshot_refresh(socket)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_in("inspect_node", %{"id" => node_id, "kind" => node_kind}, socket) do
    case GraphInspector.describe_node(node_id, node_kind, socket.assigns.tenant.schema_name) do
      {:ok, detail} ->
        {:reply, {:ok, %{detail: detail}}, socket}

      {:error, :not_found} ->
        {:reply, {:error, %{reason: "not_found"}}, socket}

      {:error, {:unsupported_node_kind, _kind}} ->
        {:reply, {:error, %{reason: "unsupported_node_kind"}}, socket}

      {:error, _reason} ->
        {:reply, {:error, %{reason: "detail_unavailable"}}, socket}
    end
  end

  def handle_in("set_window", payload, socket) do
    socket =
      socket
      |> assign(:window, parse_window(payload || %{}))
      |> push_snapshot()

    {:noreply, socket}
  end

  defp push_snapshot(socket) do
    case GraphSnapshot.latest_snapshot(socket.assigns.tenant, socket.assigns.window) do
      {:ok, %{snapshot: snapshot, payload: payload}} ->
        push(socket, "snapshot_meta", %{
          node_count: snapshot.node_count,
          edge_count: snapshot.edge_count,
          revision: snapshot.revision,
          generated_at: snapshot.generated_at,
          bitmap_metadata: snapshot.bitmap_metadata
        })

        push(socket, "snapshot", {:binary, encode_snapshot_frame(snapshot, payload)})

      {:error, _reason} ->
        push(socket, "snapshot_error", %{reason: "snapshot_unavailable"})
    end

    socket
  end

  defp schedule_snapshot_refresh(%{assigns: %{refresh_timer_ref: timer_ref}} = socket)
       when is_reference(timer_ref) do
    socket
  end

  defp schedule_snapshot_refresh(socket) do
    timer_ref = Process.send_after(self(), :refresh_snapshot, @refresh_debounce_ms)
    assign(socket, :refresh_timer_ref, timer_ref)
  end

  defp encode_snapshot_frame(snapshot, payload) do
    generated_at_ms = DateTime.to_unix(snapshot.generated_at, :millisecond)
    root_meta = Map.fetch!(snapshot.bitmap_metadata, :root_cause)
    affected_meta = Map.fetch!(snapshot.bitmap_metadata, :affected)
    healthy_meta = Map.fetch!(snapshot.bitmap_metadata, :healthy)
    unknown_meta = Map.fetch!(snapshot.bitmap_metadata, :unknown)

    <<
      @binary_magic::binary,
      snapshot.schema_version::unsigned-integer-size(8),
      snapshot.revision::unsigned-integer-size(64),
      generated_at_ms::signed-integer-size(64),
      root_meta.bytes::unsigned-integer-size(32),
      affected_meta.bytes::unsigned-integer-size(32),
      healthy_meta.bytes::unsigned-integer-size(32),
      unknown_meta.bytes::unsigned-integer-size(32),
      root_meta.count::unsigned-integer-size(32),
      affected_meta.count::unsigned-integer-size(32),
      healthy_meta.count::unsigned-integer-size(32),
      unknown_meta.count::unsigned-integer-size(32),
      payload::binary
    >>
  end

  defp parse_window(payload) do
    %{
      since: parse_naive_datetime(Map.get(payload, "since")),
      until: parse_naive_datetime(Map.get(payload, "until"))
    }
  end

  defp payload_relevant_to_window?(payload, window) when is_map(window) do
    observed_at =
      payload
      |> Map.get(:observed_at)
      |> normalize_observed_at()

    if is_nil(observed_at) do
      true
    else
      within_since?(observed_at, Map.get(window, :since)) and
        within_until?(observed_at, Map.get(window, :until))
    end
  end

  defp payload_relevant_to_window?(_payload, _window), do: true

  defp normalize_observed_at(%NaiveDateTime{} = observed_at), do: observed_at

  defp normalize_observed_at(%DateTime{} = observed_at),
    do: DateTime.to_naive(observed_at)

  defp normalize_observed_at(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, observed_at} ->
        observed_at

      _ ->
        case DateTime.from_iso8601(value) do
          {:ok, observed_at, _offset} -> DateTime.to_naive(observed_at)
          _ -> nil
        end
    end
  end

  defp normalize_observed_at(_value), do: nil

  defp within_since?(_observed_at, nil), do: true
  defp within_since?(observed_at, %NaiveDateTime{} = since), do: NaiveDateTime.compare(observed_at, since) != :lt

  defp within_until?(_observed_at, nil), do: true
  defp within_until?(observed_at, %NaiveDateTime{} = until), do: NaiveDateTime.compare(observed_at, until) != :gt

  defp parse_naive_datetime(nil), do: nil
  defp parse_naive_datetime(""), do: nil

  defp parse_naive_datetime(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, datetime} -> datetime
      _ -> nil
    end
  end
end
