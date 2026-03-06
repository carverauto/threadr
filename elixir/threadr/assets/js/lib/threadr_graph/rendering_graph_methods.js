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
    const selectionEmphasis = this.selectionEmphasis(shapedGraph)
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
          getSourceColor: (edge) => this.edgeColor(edge, visibilityMask, selectionEmphasis, "source"),
          getTargetColor: (edge) => this.edgeColor(edge, visibilityMask, selectionEmphasis, "target"),
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
          getFillColor: (node) => this.nodeColor(node, visibilityMask, selectionEmphasis),
          onClick: ({object}) => this.handlePick(object),
          updateTriggers: {
            getFillColor: [visibilityMask, selectionEmphasis?.key || "none", this.state.selectedNodeIndex],
            getLineWidth: [this.state.selectedNodeIndex],
            getLineColor: [this.state.selectedNodeIndex],
          },
        }),
      ],
    })

    this.updateSummary(
      `shape=${shapedGraph.shape} zoom=${this.state.zoomMode === "auto" ? this.state.zoomTier : this.state.zoomMode} nodes=${nodes.length} edges=${edges.length} focus=${selectionEmphasis?.mode || "none"} renderer=${this.rendererMode()}`,
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

  nodeColor(node, visibilityMask, selectionEmphasis) {
    const base = STATE_COLORS[node.state] || STATE_COLORS[3]
    const visible = visibilityMask[node.index] === 1
    if (!visible) return [base[0], base[1], base[2], 28]

    const emphasis = this.nodeEmphasis(node, selectionEmphasis)
    if (emphasis === "selected") return [255, 255, 255, 255]
    if (emphasis === "dossier") return [base[0], base[1], base[2], 245]
    if (emphasis === "community") return [base[0], base[1], base[2], 210]
    if (emphasis === "component") return [base[0], base[1], base[2], 128]
    if (emphasis === "dim") return [base[0], base[1], base[2], 36]
    return base
  },

  edgeColor(edge, visibilityMask, selectionEmphasis, end = "source") {
    const sourceVisible = visibilityMask[edge.source] === 1
    const targetVisible = visibilityMask[edge.target] === 1
    if (!sourceVisible || !targetVisible) return [100, 116, 139, 24]

    const sourceEmphasis = this.nodeEmphasis(edge.sourceNode, selectionEmphasis)
    const targetEmphasis = this.nodeEmphasis(edge.targetNode, selectionEmphasis)
    const edgeFocused = this.edgeEmphasis(sourceEmphasis, targetEmphasis)
    if (edgeFocused === "dim") return [100, 116, 139, 30]

    if (edge.kind === "relationship") {
      if (edge.label === "MENTIONED") {
        return end === "source"
          ? [248, 113, 113, edgeFocused === "strong" ? 220 : 140]
          : [251, 146, 60, edgeFocused === "strong" ? 208 : 124]
      }
      if (edge.label === "CO_MENTIONED") return [251, 191, 36, edgeFocused === "strong" ? 200 : 132]
      return [244, 114, 182, edgeFocused === "strong" ? 196 : 128]
    }

    if (edge.kind === "authored") {
      return end === "source"
        ? [250, 204, 21, edgeFocused === "strong" ? 216 : 164]
        : [253, 224, 71, edgeFocused === "strong" ? 172 : 88]
    }

    if (edge.kind === "in_channel") {
      return end === "source"
        ? [56, 189, 248, edgeFocused === "strong" ? 210 : 154]
        : [125, 211, 252, edgeFocused === "strong" ? 160 : 96]
    }

    return [148, 163, 184, edgeFocused === "strong" ? 164 : 120]
  },

  selectionEmphasis(graph) {
    const selectedNode = this.state.selectedNode
    if (!graph || !selectedNode) return null

    const selectedId = selectedNode.details?.id || null
    const selectedProfile = selectedNode.details?.graph_profile || {}
    const focusIds = this.collectFocusIds(this.state.selectedNodeDetail)

    return {
      key: `${selectedId || "cluster"}:${selectedProfile.community_id || "none"}:${selectedProfile.component_id || "none"}:${focusIds.size}`,
      mode: focusIds.size > 0 ? "dossier" : selectedProfile.community_id ? "community" : "selected",
      selectedId,
      selectedIndex: this.state.selectedNodeIndex,
      communityId: selectedProfile.community_id || null,
      componentId: selectedProfile.component_id || null,
      focusIds,
    }
  },

  collectFocusIds(detail) {
    const ids = new Set()
    if (!detail || detail.error) return ids

    const push = (value) => {
      if (value) ids.add(String(value))
    }

    push(detail.focal?.id)
    ;(detail.recent_messages || []).forEach((item) => push(item.id))
    ;(detail.top_channels || []).forEach((item) => push(item.channel_id))
    ;(detail.top_actors || []).forEach((item) => push(item.actor_id))
    ;(detail.top_relationships || []).forEach((item) => {
      push(item.from_actor_id)
      push(item.to_actor_id)
      push(item.source_message_id)
    })
    ;(detail.neighborhood?.actors || []).forEach((item) => push(item.actor_id))
    ;(detail.neighborhood?.messages || []).forEach((item) => push(item.message_id))

    return ids
  },

  nodeEmphasis(node, selectionEmphasis) {
    if (!selectionEmphasis || !node) return "normal"
    if (this.state.selectedNodeIndex === node.index) return "selected"

    const nodeId = node.details?.id ? String(node.details.id) : null
    const profile = node.details?.graph_profile || {}

    if (nodeId && selectionEmphasis.focusIds.has(nodeId)) return "dossier"
    if (selectionEmphasis.communityId && profile.community_id === selectionEmphasis.communityId) return "community"
    if (selectionEmphasis.componentId && profile.component_id === selectionEmphasis.componentId) return "component"
    return "dim"
  },

  edgeEmphasis(sourceEmphasis, targetEmphasis) {
    const strongStates = new Set(["selected", "dossier"])
    if (strongStates.has(sourceEmphasis) && strongStates.has(targetEmphasis)) return "strong"
    if (sourceEmphasis === "dim" || targetEmphasis === "dim") return "dim"
    return "soft"
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
