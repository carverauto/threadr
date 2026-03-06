import {Deck, OrthographicView} from "@deck.gl/core"
import {ArcLayer, ScatterplotLayer} from "@deck.gl/layers"

const STATE_COLORS = {
  0: [245, 158, 11, 230],
  1: [56, 189, 248, 230],
  2: [34, 197, 94, 230],
  3: [148, 163, 184, 210],
}

export const threadrGraphRenderingGraphMethods = {
  renderGraph() {
    if (!this.state.graph) return
    if (!this.state.deck) this.ensureDeck()

    const shapedGraph = this.reshapeGraph(this.state.graph)
    const visibilityMask = this.visibilityMask()
    const traversalMask = this.traversalMask(shapedGraph)
    const nodes = shapedGraph.nodes
    const edges = shapedGraph.edges
      .filter((edge) => this.edgeLayerVisible(edge.kind))
      .map((edge) => ({
      ...edge,
      sourceNode: nodes[edge.source],
      targetNode: nodes[edge.target],
    }))

    this.state.deck.setProps({
      viewState: this.state.viewState || this.initialViewState(),
      onViewStateChange: ({viewState}) => {
        this.state.viewState = viewState
        if (this.state.zoomMode === "auto") {
          this.setZoomTier(this.resolveZoomTier(Number(viewState.zoom || 0)), false)
        }
      },
      layers: [
        new ArcLayer({
          id: "tenant-graph-edges",
          data: edges,
          pickable: false,
          getSourcePosition: (edge) => [edge.sourceNode?.x || 0, edge.sourceNode?.y || 0],
          getTargetPosition: (edge) => [edge.targetNode?.x || 0, edge.targetNode?.y || 0],
          getSourceColor: (edge) => this.edgeColor(edge, visibilityMask, traversalMask, "source"),
          getTargetColor: (edge) => this.edgeColor(edge, visibilityMask, traversalMask, "target"),
          getWidth: (edge) => Math.max(1, Math.min(8, Math.log2(edge.weight + 1))),
          widthUnits: "pixels",
          greatCircle: false,
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
          getFillColor: (node) => this.nodeColor(node, visibilityMask, traversalMask),
          onClick: ({object}) => this.handlePick(object),
          updateTriggers: {
            getFillColor: [visibilityMask, traversalMask, this.state.selectedNodeIndex],
            getLineWidth: [this.state.selectedNodeIndex],
            getLineColor: [this.state.selectedNodeIndex],
          },
        }),
      ],
    })

    this.updateSummary(
      `shape=${shapedGraph.shape} zoom=${this.state.zoomMode === "auto" ? this.state.zoomTier : this.state.zoomMode} nodes=${nodes.length} edges=${edges.length} renderer=${this.rendererMode()}`,
    )
  },

  ensureDeck() {
    const initialViewState = this.initialViewState()
    this.state.viewState = initialViewState
    this.state.zoomTier = this.resolveZoomTier(Number(initialViewState.zoom || 0))

    this.state.deck = new Deck({
      parent: this.canvasEl,
      controller: true,
      views: [new OrthographicView({id: "threadr-graph"})],
      initialViewState,
      onViewStateChange: ({viewState}) => {
        this.state.viewState = viewState
        if (this.state.zoomMode === "auto") {
          this.setZoomTier(this.resolveZoomTier(Number(viewState.zoom || 0)), false)
        }
      },
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
    const width = this.rootEl.clientWidth || 1200
    const height = this.rootEl.clientHeight || 700
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

  traversalMask(graph) {
    if (this.state.selectedNodeIndex == null || !graph) return null
    if ((graph.shape || "local") !== "local") return null

    if (this.state.wasmReady && this.state.wasmEngine) {
      try {
        return this.state.wasmEngine.computeThreeHopMask(
          graph.nodes.length,
          graph.edgeSourceIndex,
          graph.edgeTargetIndex,
          this.state.selectedNodeIndex,
        )
      } catch (_error) {
        this.state.wasmReady = false
      }
    }

    return null
  },

  nodeColor(node, visibilityMask, traversalMask) {
    const base = STATE_COLORS[node.state] || STATE_COLORS[3]
    const visible = visibilityMask[node.index] === 1
    const traversed = !traversalMask || traversalMask[node.index] === 1
    if (!visible || !traversed) return [base[0], base[1], base[2], 40]
    return base
  },

  edgeColor(edge, visibilityMask, traversalMask, end = "source") {
    const sourceVisible = visibilityMask[edge.source] === 1
    const targetVisible = visibilityMask[edge.target] === 1
    const traversed =
      !traversalMask ||
      (traversalMask[edge.source] === 1 && traversalMask[edge.target] === 1)

    if (!sourceVisible || !targetVisible || !traversed) return [100, 116, 139, 36]

    if (edge.kind === "relationship") {
      if (edge.label === "MENTIONED") return end === "source" ? [248, 113, 113, 160] : [251, 146, 60, 144]
      if (edge.label === "CO_MENTIONED") return [251, 191, 36, 152]
      return [244, 114, 182, 148]
    }

    if (edge.kind === "authored") {
      return end === "source" ? [250, 204, 21, 180] : [253, 224, 71, 96]
    }

    if (edge.kind === "in_channel") {
      return end === "source" ? [56, 189, 248, 170] : [125, 211, 252, 104]
    }

    return [148, 163, 184, 132]
  },

  edgeLayerVisible(kind) {
    if (kind === "relationship") return this.state.edgeLayers.relationship !== false
    if (kind === "authored") return this.state.edgeLayers.authored !== false
    if (kind === "in_channel") return this.state.edgeLayers.in_channel !== false
    return true
  },

  rendererMode() {
    return typeof navigator !== "undefined" && navigator.gpu ? "webgpu-capable" : "fallback"
  },
}
