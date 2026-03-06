defmodule ThreadrWeb.TenantGraphChannel do
  use ThreadrWeb, :channel

  alias Threadr.ControlPlane.Service
  alias Threadr.TenantData.GraphInspector
  alias Threadr.TenantData.GraphSnapshot

  @tick_ms 5_000
  @binary_magic "TGV1"

  @impl true
  def join("graph:" <> subject_name, _payload, socket) do
    user = %{id: socket.assigns.user_id}

    with {:ok, tenant, _membership} <- Service.get_user_tenant_by_subject_name(user, subject_name) do
      send(self(), :tick)
      {:ok, assign(socket, :tenant, tenant)}
    else
      _ -> {:error, %{reason: "unauthorized"}}
    end
  end

  @impl true
  def handle_info(:tick, socket) do
    case GraphSnapshot.latest_snapshot(socket.assigns.tenant) do
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

    Process.send_after(self(), :tick, @tick_ms)
    {:noreply, socket}
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
end
