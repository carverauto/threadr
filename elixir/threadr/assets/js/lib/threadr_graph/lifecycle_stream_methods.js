import {tableFromIPC} from "apache-arrow"

export const threadrGraphLifecycleStreamMethods = {
  handleSnapshot(message) {
    const snapshot = this.parseSnapshotMessage(message)
    const graph = this.decodeArrowGraph(snapshot.payload)
    this.state.graph = graph
    this.syncSelectionState(graph)
    if (this.state.pinnedNodeId) this.centerOnFocusContext()
    this.updateSummary(
      `revision=${snapshot.revision} nodes=${graph.nodes.length} edges=${graph.edges.length} renderer=${this.rendererMode()}`,
    )
    this.renderGraph()
  },

  parseSnapshotMessage(msg) {
    const buffer =
      msg instanceof ArrayBuffer
        ? msg
        : ArrayBuffer.isView(msg)
          ? msg.buffer.slice(msg.byteOffset, msg.byteOffset + msg.byteLength)
          : msg?.binary instanceof ArrayBuffer
            ? msg.binary
            : null

    if (!buffer) throw new Error("invalid snapshot payload")

    const bytes = new Uint8Array(buffer)
    if (bytes.byteLength < 53) throw new Error("short snapshot frame")

    const magic = String.fromCharCode(bytes[0], bytes[1], bytes[2], bytes[3])
    if (magic !== "TGV1") throw new Error("invalid snapshot frame magic")

    const view = new DataView(buffer)
    return {
      schemaVersion: view.getUint8(4),
      revision: Number(view.getBigUint64(5, false)),
      generatedAtMs: Number(view.getBigInt64(13, false)),
      payload: bytes.slice(53),
    }
  },

  decodeArrowGraph(bytes) {
    const table = tableFromIPC(bytes)
    const rowType = table.getChild("row_type")
    const nodeX = table.getChild("node_x")
    const nodeY = table.getChild("node_y")
    const nodeState = table.getChild("node_state")
    const nodeLabel = table.getChild("node_label")
    const nodeKind = table.getChild("node_kind")
    const nodeSize = table.getChild("node_size")
    const nodeDetails = table.getChild("node_details")
    const edgeSource = table.getChild("edge_source")
    const edgeTarget = table.getChild("edge_target")
    const edgeWeight = table.getChild("edge_weight")
    const edgeLabel = table.getChild("edge_label")
    const edgeKind = table.getChild("edge_kind")

    const nodes = []
    const edges = []
    const edgeSourceIndex = []
    const edgeTargetIndex = []

    for (let i = 0; i < (table.numRows || 0); i += 1) {
      if (rowType?.get(i) === 0) {
        let details = {}
        const rawDetails = nodeDetails?.get(i)

        if (typeof rawDetails === "string" && rawDetails.trim() !== "") {
          try {
            details = JSON.parse(rawDetails)
          } catch (_error) {
            details = {}
          }
        }

        nodes.push({
          index: nodes.length,
          x: Number(nodeX?.get(i) || 0),
          y: Number(nodeY?.get(i) || 0),
          state: Number(nodeState?.get(i) || 3),
          label: String(nodeLabel?.get(i) || `node-${nodes.length + 1}`),
          kind: String(nodeKind?.get(i) || "other"),
          size: Number(nodeSize?.get(i) || 12),
          details,
        })
      } else if (rowType?.get(i) === 1) {
        const source = Number(edgeSource?.get(i) || 0)
        const target = Number(edgeTarget?.get(i) || 0)

        edges.push({
          source,
          target,
          weight: Number(edgeWeight?.get(i) || 1),
          label: String(edgeLabel?.get(i) || ""),
          kind: String(edgeKind?.get(i) || "relationship"),
        })
        edgeSourceIndex.push(source)
        edgeTargetIndex.push(target)
      }
    }

    return {
      nodes,
      edges,
      edgeSourceIndex: Uint32Array.from(edgeSourceIndex),
      edgeTargetIndex: Uint32Array.from(edgeTargetIndex),
    }
  },
}
