import {Deck, OrthographicView} from "@deck.gl/core"
import {LineLayer, ScatterplotLayer} from "@deck.gl/layers"
import {tableFromIPC} from "apache-arrow"
import {Socket} from "phoenix"

import {ThreadrGraphWasmEngine} from "../wasm/threadr_graph_exec_runtime"

const STATE_COLORS = {
  0: [245, 158, 11, 230],
  1: [56, 189, 248, 230],
  2: [34, 197, 94, 230],
  3: [148, 163, 184, 210],
}

export const TenantGraphExplorer = {
  mounted() {
    this.state = {
      filters: JSON.parse(this.el.dataset.initialFilters || "{}"),
      filterLabels: JSON.parse(this.el.dataset.filterLabels || "{}"),
      graph: null,
      deck: null,
      channel: null,
      socket: null,
      summaryEl: null,
      detailsEl: null,
      wasmEngine: null,
      wasmReady: false,
      selectedNodeIndex: null,
      selectedNode: null,
    }

    this.setupDom()
    this.initWasm()
    this.connectChannel()

    this.handleEvent("tenant_graph:set_filters", ({filters}) => {
      this.state.filters = {...this.state.filters, ...(filters || {})}
      this.renderGraph()
    })
  },

  destroyed() {
    this.state.channel?.leave()
    this.state.socket?.disconnect()
    this.state.deck?.finalize()
  },

  setupDom() {
    this.el.classList.add("relative")

    this.canvasEl = document.createElement("div")
    this.canvasEl.className = "absolute inset-0"

    this.state.summaryEl = document.createElement("div")
    this.state.summaryEl.className =
      "absolute left-4 top-4 rounded-box bg-base-100/85 px-3 py-2 text-xs shadow-sm backdrop-blur"
    this.state.summaryEl.textContent = "Connecting graph stream..."

    this.state.detailsEl = document.createElement("div")
    this.state.detailsEl.className =
      "absolute bottom-4 right-4 max-w-sm rounded-box bg-base-100/90 p-3 text-xs shadow-sm backdrop-blur"
    this.state.detailsEl.innerHTML = "<div class=\"font-semibold\">Selection</div><div>No node selected.</div>"

    this.el.appendChild(this.canvasEl)
    this.el.appendChild(this.state.summaryEl)
    this.el.appendChild(this.state.detailsEl)
  },

  initWasm() {
    ThreadrGraphWasmEngine.init()
      .then((engine) => {
        this.state.wasmEngine = engine
        this.state.wasmReady = true
      })
      .catch(() => {
        this.state.wasmReady = false
      })
  },

  connectChannel() {
    this.state.socket = new Socket("/socket", {
      params: {token: this.el.dataset.socketToken},
    })
    this.state.socket.connect()

    this.state.channel = this.state.socket.channel(this.el.dataset.topic, {})
    this.state.channel.on("snapshot_meta", (payload) => {
      this.state.summaryEl.textContent =
        `revision=${payload.revision} nodes=${payload.node_count} edges=${payload.edge_count}`
    })
    this.state.channel.on("snapshot", (payload) => this.handleSnapshot(payload))
    this.state.channel.on("snapshot_error", () => {
      this.state.summaryEl.textContent = "Graph snapshot unavailable"
    })
    this.state.channel.join()
      .receive("ok", () => {
        this.state.summaryEl.textContent = "Waiting for graph snapshot..."
      })
      .receive("error", () => {
        this.state.summaryEl.textContent = "Unauthorized graph stream"
      })
  },

  handleSnapshot(message) {
    const snapshot = this.parseSnapshotMessage(message)
    const graph = this.decodeArrowGraph(snapshot.payload)
    this.state.graph = graph
    this.state.summaryEl.textContent =
      `revision=${snapshot.revision} nodes=${graph.nodes.length} edges=${graph.edges.length} backend=${this.rendererMode()}`
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

  renderGraph() {
    if (!this.state.graph) return
    if (!this.state.deck) this.ensureDeck()

    const visibilityMask = this.visibilityMask()
    const traversalMask = this.traversalMask()
    const nodes = this.state.graph.nodes
    const edges = this.state.graph.edges.map((edge) => ({
      ...edge,
      sourceNode: nodes[edge.source],
      targetNode: nodes[edge.target],
    }))

    this.state.deck.setProps({
      layers: [
        new LineLayer({
          id: "tenant-graph-edges",
          data: edges,
          pickable: false,
          getSourcePosition: (edge) => [edge.sourceNode?.x || 0, edge.sourceNode?.y || 0],
          getTargetPosition: (edge) => [edge.targetNode?.x || 0, edge.targetNode?.y || 0],
          getColor: (edge) => {
            const sourceVisible = visibilityMask[edge.source] === 1
            const targetVisible = visibilityMask[edge.target] === 1
            const traversed =
              !traversalMask ||
              (traversalMask[edge.source] === 1 && traversalMask[edge.target] === 1)

            if (!sourceVisible || !targetVisible || !traversed) return [100, 116, 139, 40]
            return edge.kind === "participation" ? [56, 189, 248, 120] : [248, 113, 113, 140]
          },
          getWidth: (edge) => Math.max(1, Math.min(8, Math.log2(edge.weight + 1))),
          widthUnits: "pixels",
        }),
        new ScatterplotLayer({
          id: "tenant-graph-nodes",
          data: nodes,
          pickable: true,
          stroked: true,
          filled: true,
          radiusUnits: "pixels",
          lineWidthUnits: "pixels",
          getPosition: (node) => [node.x, node.y],
          getRadius: (node) => node.size,
          getLineWidth: (node) => (this.state.selectedNodeIndex === node.index ? 3 : 1),
          getLineColor: (node) =>
            this.state.selectedNodeIndex === node.index ? [255, 255, 255, 255] : [15, 23, 42, 220],
          getFillColor: (node) => {
            const base = STATE_COLORS[node.state] || STATE_COLORS[3]
            const visible = visibilityMask[node.index] === 1
            const traversed = !traversalMask || traversalMask[node.index] === 1
            if (!visible || !traversed) return [base[0], base[1], base[2], 40]
            return base
          },
          onClick: ({object}) => this.handlePick(object),
          updateTriggers: {
            getFillColor: [visibilityMask, traversalMask, this.state.selectedNodeIndex],
            getLineWidth: [this.state.selectedNodeIndex],
            getLineColor: [this.state.selectedNodeIndex],
          },
        }),
      ],
    })
  },

  ensureDeck() {
    this.state.deck = new Deck({
      parent: this.canvasEl,
      controller: true,
      views: [new OrthographicView({id: "threadr-graph"})],
      initialViewState: this.initialViewState(),
      getTooltip: ({object}) =>
        object
          ? {
              text: object.label || object.details?.name || object.details?.handle || "node",
            }
          : null,
    })
  },

  initialViewState() {
    const nodes = this.state.graph?.nodes || []
    if (nodes.length === 0) return {target: [0, 0, 0], zoom: 0}

    const xs = nodes.map((node) => node.x)
    const ys = nodes.map((node) => node.y)
    const minX = Math.min(...xs)
    const maxX = Math.max(...xs)
    const minY = Math.min(...ys)
    const maxY = Math.max(...ys)
    const width = this.el.clientWidth || 1200
    const height = this.el.clientHeight || 700
    const spanX = Math.max(1, maxX - minX)
    const spanY = Math.max(1, maxY - minY)
    const scale = Math.min(width / spanX, height / spanY) * 0.6
    const zoom = Math.log2(scale)

    return {
      target: [(minX + maxX) / 2, (minY + maxY) / 2, 0],
      zoom,
    }
  },

  visibilityMask() {
    const states = Uint8Array.from((this.state.graph?.nodes || []).map((node) => node.state))

    if (this.state.wasmReady && this.state.wasmEngine) {
      try {
        return this.state.wasmEngine.computeStateMask(states, this.state.filters)
      } catch (_error) {
        this.state.wasmReady = false
      }
    }

    return Uint8Array.from(
      states,
      (state) =>
        this.state.filters[
          state === 0 ? "root_cause" : state === 1 ? "affected" : state === 2 ? "healthy" : "unknown"
        ]
          ? 1
          : 0,
    )
  },

  traversalMask() {
    if (this.state.selectedNodeIndex == null || !this.state.graph) return null

    if (this.state.wasmReady && this.state.wasmEngine) {
      try {
        return this.state.wasmEngine.computeThreeHopMask(
          this.state.graph.nodes.length,
          this.state.graph.edgeSourceIndex,
          this.state.graph.edgeTargetIndex,
          this.state.selectedNodeIndex,
        )
      } catch (_error) {
        this.state.wasmReady = false
      }
    }

    return null
  },

  handlePick(node) {
    if (!node) return
    this.state.selectedNodeIndex = node.index
    this.state.selectedNode = node
    this.state.detailsEl.innerHTML = `
      <div class="font-semibold mb-1">${this.escapeHtml(node.label || "node")}</div>
      <div>Type: ${this.escapeHtml(node.kind || "other")}</div>
      <div>Platform: ${this.escapeHtml(node.details?.platform || "unknown")}</div>
      <div>Handle: ${this.escapeHtml(node.details?.handle || node.details?.name || "unknown")}</div>
      <div>Messages: ${this.escapeHtml(String(node.details?.message_count ?? "0"))}</div>
    `
    this.renderGraph()
  },

  escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll("\"", "&quot;")
  },

  rendererMode() {
    return typeof navigator !== "undefined" && navigator.gpu ? "webgpu-capable" : "fallback"
  },
}
