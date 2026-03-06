defmodule Threadr.TenantData.GraphSnapshot.Native do
  @moduledoc """
  Rust NIF bindings for tenant graph Arrow snapshot encoding and bitmap packing.
  """

  use Rustler, otp_app: :threadr, crate: "threadr_graph_nif"

  def encode_snapshot(_schema_version, _revision, _nodes, _edges, _bitmap_sizes),
    do: :erlang.nif_error(:nif_not_loaded)

  def build_roaring_bitmaps(_states), do: :erlang.nif_error(:nif_not_loaded)
end
