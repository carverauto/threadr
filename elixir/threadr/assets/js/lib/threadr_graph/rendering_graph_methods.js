import {Deck, OrthographicView} from "@deck.gl/core"
import {LineLayer, ScatterplotLayer, TextLayer} from "@deck.gl/layers"

const STATE_COLORS = {
  0: [245, 158, 11, 230],
  1: [56, 189, 248, 230],
  2: [34, 197, 94, 230],
  3: [226, 232, 240, 225],
}

export const threadrGraphRenderingGraphMethods = {
  renderGraph() {
    if (!this.state.graph) return
    if (!this.state.deck) this.ensureDeck()

    let shapedGraph = this.reshapeGraph(this.state.graph)
    const visibilityMask = this.visibilityMask()
    let selectionEmphasis = this.selectionEmphasis(shapedGraph)
    shapedGraph = this.filterGraphForFocus(shapedGraph, selectionEmphasis)
    selectionEmphasis = this.selectionEmphasis(shapedGraph)
    shapedGraph = this.filterGraphByVisibility(shapedGraph, visibilityMask, selectionEmphasis)
    selectionEmphasis = this.selectionEmphasis(shapedGraph)
    const nodes = shapedGraph.nodes
    const edges = shapedGraph.edges
      .filter((edge) => this.edgeLayerVisible(edge.kind))
      .filter((edge) => this.relationshipVisible(edge))
      .map((edge) => ({
        ...edge,
        sourceNode: nodes[edge.source],
        targetNode: nodes[edge.target],
      }))
    const investigationEdges = this.investigationEdges(edges, selectionEmphasis)

    const currentViewState = this.state.viewState || this.initialViewState()

    this.state.deck.setProps({
      viewState: currentViewState,
      onViewStateChange: ({viewState}) => {
        this.state.viewState = viewState
        this.state.deck?.setProps({viewState})
        if (this.state.zoomMode === "auto") {
          this.setZoomTier(this.resolveZoomTier(Number(viewState.zoom || 0)), false)
        }
      },
      onClick: ({object}) => {
        if (!object) this.clearSelection()
      },
      onDoubleClick: ({object}) => {
        this.handleGraphDoubleClick(object)
      },
      layers: [
        new LineLayer({
          id: "tenant-graph-edges-halo",
          data: investigationEdges,
          pickable: false,
          getSourcePosition: (edge) => [edge.sourceNode?.x || 0, edge.sourceNode?.y || 0],
          getTargetPosition: (edge) => [edge.targetNode?.x || 0, edge.targetNode?.y || 0],
          getColor: (edge) => this.edgeHaloColor(edge, visibilityMask, selectionEmphasis),
          getWidth: (edge) => Math.max(4, Math.min(12, Math.log2(edge.weight + 2) * 2.2)),
          widthUnits: "pixels",
        }),
        new LineLayer({
          id: "tenant-graph-edges",
          data: investigationEdges,
          pickable: false,
          getSourcePosition: (edge) => [edge.sourceNode?.x || 0, edge.sourceNode?.y || 0],
          getTargetPosition: (edge) => [edge.targetNode?.x || 0, edge.targetNode?.y || 0],
          getColor: (edge) => this.edgeColor(edge, visibilityMask, selectionEmphasis),
          getWidth: (edge) => Math.max(2, Math.min(9, Math.log2(edge.weight + 2) * 1.5)),
          widthUnits: "pixels",
        }),
        new TextLayer({
          id: "tenant-graph-edge-labels",
          data: this.edgeLabelData(investigationEdges, visibilityMask, selectionEmphasis),
          pickable: false,
          getPosition: (label) => label.position,
          getText: (label) => label.text,
          getSize: (label) => label.size,
          getColor: (label) => label.color,
          getBackgroundColor: [8, 12, 20, 170],
          background: true,
          billboard: true,
          sizeUnits: "pixels",
          getTextAnchor: "middle",
          getAlignmentBaseline: "center",
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
          getLineWidth: (node) => (this.isSelectedNode(node) ? 4 : 2),
          getLineColor: (node) =>
            this.isSelectedNode(node) ? [255, 255, 255, 255] : [226, 232, 240, 230],
          getFillColor: (node) => this.nodeColor(node, visibilityMask, selectionEmphasis),
          onClick: ({object}) => this.handlePick(object),
          updateTriggers: {
            getFillColor: [visibilityMask, selectionEmphasis?.key || "none", this.state.selectedNodeIndex],
            getLineWidth: [this.state.selectedNodeIndex],
            getLineColor: [this.state.selectedNodeIndex],
          },
        }),
        new TextLayer({
          id: "tenant-graph-node-labels",
          data: this.nodeLabelData(nodes, visibilityMask, selectionEmphasis),
          pickable: false,
          getPosition: (node) => node.position,
          getText: (node) => node.text,
          getSize: (node) => node.size,
          getColor: (node) => node.color,
          getBackgroundColor: [8, 12, 20, 185],
          background: true,
          billboard: true,
          sizeUnits: "pixels",
          getTextAnchor: "middle",
          getAlignmentBaseline: "bottom",
          getPixelOffset: [0, -14],
        }),
      ],
    })
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
        this.state.deck?.setProps({viewState})
        if (this.state.zoomMode === "auto") {
          this.setZoomTier(this.resolveZoomTier(Number(viewState.zoom || 0)), false)
        }
      },
      onClick: ({object}) => {
        if (!object) this.clearSelection()
      },
      onDoubleClick: ({object}) => {
        this.handleGraphDoubleClick(object)
      },
      getTooltip: ({object}) =>
        object
          ? {
              text: this.tooltipText(object),
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

  handleGraphDoubleClick(object) {
    if (!object) return

    this.setZoomMode("local")
    this.state.viewState = {
      target: [object.x || 0, object.y || 0, 0],
      zoom: Math.max(Number(this.state.viewState?.zoom || 0), 1.2),
    }

    if (object.details?.type === "cluster") {
      this.state.deck?.setProps({viewState: this.state.viewState})
      this.renderGraph()
      return
    }

    this.handlePick(object)
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
    const visible = visibilityMask[this.maskIndex(node)] === 1
    if (!visible) return [base[0], base[1], base[2], 40]

    const emphasis = this.nodeEmphasis(node, selectionEmphasis)
    if (emphasis === "selected") return [255, 255, 255, 255]
    if (emphasis === "dossier") return [base[0], base[1], base[2], 255]
    if (emphasis === "community") return [base[0], base[1], base[2], 236]
    if (emphasis === "component") return [base[0], base[1], base[2], 190]
    if (emphasis === "dim") return [base[0], base[1], base[2], 72]
    return [base[0], base[1], base[2], 232]
  },

  edgeColor(edge, visibilityMask, selectionEmphasis) {
    const sourceVisible = visibilityMask[this.maskIndex(edge.sourceNode)] === 1
    const targetVisible = visibilityMask[this.maskIndex(edge.targetNode)] === 1
    if (!sourceVisible || !targetVisible) return [100, 116, 139, 36]

    const sourceEmphasis = this.nodeEmphasis(edge.sourceNode, selectionEmphasis)
    const targetEmphasis = this.nodeEmphasis(edge.targetNode, selectionEmphasis)
    const edgeFocused = this.edgeEmphasis(sourceEmphasis, targetEmphasis)
    if (edgeFocused === "dim") return [148, 163, 184, 72]

    if (edge.kind === "relationship") {
      if (edge.label === "MENTIONED") {
        return [248, 113, 113, edgeFocused === "strong" ? 245 : 205]
      }
      if (edge.label === "CO_MENTIONED") return [251, 191, 36, edgeFocused === "strong" ? 228 : 188]
      return [244, 114, 182, edgeFocused === "strong" ? 224 : 176]
    }

    if (edge.kind === "authored") {
      return [250, 204, 21, edgeFocused === "strong" ? 220 : 176]
    }

    if (edge.kind === "in_channel") {
      return [56, 189, 248, edgeFocused === "strong" ? 220 : 180]
    }

    return [148, 163, 184, edgeFocused === "strong" ? 196 : 156]
  },

  edgeHaloColor(edge, visibilityMask, selectionEmphasis) {
    const sourceVisible = visibilityMask[this.maskIndex(edge.sourceNode)] === 1
    const targetVisible = visibilityMask[this.maskIndex(edge.targetNode)] === 1
    if (!sourceVisible || !targetVisible) return [15, 23, 42, 0]

    const sourceEmphasis = this.nodeEmphasis(edge.sourceNode, selectionEmphasis)
    const targetEmphasis = this.nodeEmphasis(edge.targetNode, selectionEmphasis)
    const edgeFocused = this.edgeEmphasis(sourceEmphasis, targetEmphasis)

    if (edgeFocused === "dim") return [15, 23, 42, 48]
    if (edgeFocused === "strong") return [255, 255, 255, 92]
    return [15, 23, 42, 76]
  },

  selectionEmphasis(graph) {
    const selectedNode = this.state.selectedNode
    if (!graph || !selectedNode) return null

    const selectedId = selectedNode.details?.id || null
    const focusIds = this.collectFocusIds(this.state.selectedNodeDetail)
    const directNeighborIds = this.collectDirectNeighborIds(graph, this.state.selectedNodeIndex)

    return {
      key: `${selectedId || "cluster"}:${focusIds.size}:${directNeighborIds.size}`,
      mode: focusIds.size > 0 || directNeighborIds.size > 0 ? "dossier" : "selected",
      selectedId,
      selectedIndex: this.state.selectedNodeIndex,
      focusIds,
      directNeighborIds,
    }
  },

  collectDirectNeighborIds(graph, selectedIndex) {
    const ids = new Set()
    if (!graph || selectedIndex == null) return ids

    graph.edges.forEach((edge) => {
      if (edge.source !== selectedIndex && edge.target !== selectedIndex) return

      const neighborIndex = edge.source === selectedIndex ? edge.target : edge.source
      const neighbor = graph.nodes[neighborIndex]
      const neighborId = neighbor?.details?.id
      if (neighborId) ids.add(String(neighborId))
    })

    return ids
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
    if (this.isSelectedNode(node)) return "selected"

    const nodeId = node.details?.id ? String(node.details.id) : null

    if (nodeId && selectionEmphasis.focusIds.has(nodeId)) return "dossier"
    if (nodeId && selectionEmphasis.directNeighborIds?.has(nodeId)) return "dossier"
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
    if (kind === "conversation") return this.state.edgeLayers.conversation !== false
    if (kind === "authored") return this.state.edgeLayers.authored !== false
    if (kind === "in_channel") return this.state.edgeLayers.in_channel !== false
    return true
  },

  investigationEdges(edges, selectionEmphasis) {
    if (!Array.isArray(edges) || edges.length === 0) return []

    const nonRelationshipEdges = edges.filter((edge) => edge.kind !== "relationship")
    const relationshipEdges = edges.filter((edge) => edge.kind === "relationship")

    if (relationshipEdges.length === 0) return nonRelationshipEdges

    const scoredEdges = relationshipEdges.map((edge) => ({
      edge,
      score: this.relationshipEdgeScore(edge, selectionEmphasis),
      preserve: this.relationshipEdgePreserve(edge, selectionEmphasis),
    }))

    const preserved = scoredEdges
      .filter((entry) => entry.preserve)
      .sort((left, right) => right.score - left.score)
      .map((entry) => entry.edge)

    const targetCount = this.relationshipEdgeTargetCount(scoredEdges.length, selectionEmphasis)
    if (preserved.length >= targetCount) {
      return [...nonRelationshipEdges, ...preserved.slice(0, targetCount)]
    }

    const preservedKeys = new Set(preserved.map((edge) => this.edgeKey(edge)))
    const ranked = scoredEdges
      .filter((entry) => !preservedKeys.has(this.edgeKey(entry.edge)))
      .sort((left, right) => right.score - left.score)
      .slice(0, Math.max(0, targetCount - preserved.length))
      .map((entry) => entry.edge)

    return [...nonRelationshipEdges, ...preserved, ...ranked]
  },

  relationshipEdgeScore(edge, selectionEmphasis) {
    const baseWeight = Number(edge.weight || 1)
    const sourceEmphasis = this.nodeEmphasis(edge.sourceNode, selectionEmphasis)
    const targetEmphasis = this.nodeEmphasis(edge.targetNode, selectionEmphasis)
    const emphasisScore =
      (sourceEmphasis === "selected" ? 8 : sourceEmphasis === "dossier" ? 6 : 0) +
      (targetEmphasis === "selected" ? 8 : targetEmphasis === "dossier" ? 6 : 0)
    const typeBonus =
      edge.label === "MENTIONED" ? 3 : edge.label === "CO_MENTIONED" ? 1.5 : 0.5

    return baseWeight * 4 + emphasisScore + typeBonus
  },

  relationshipEdgePreserve(edge, selectionEmphasis) {
    if (!selectionEmphasis) return false

    const sourceId = edge.sourceNode?.details?.id ? String(edge.sourceNode.details.id) : null
    const targetId = edge.targetNode?.details?.id ? String(edge.targetNode.details.id) : null
    const focusIds = selectionEmphasis.focusIds || new Set()

    if (sourceId && focusIds.has(sourceId)) return true
    if (targetId && focusIds.has(targetId)) return true
    if (sourceId && selectionEmphasis.selectedId && sourceId === String(selectionEmphasis.selectedId)) return true
    if (targetId && selectionEmphasis.selectedId && targetId === String(selectionEmphasis.selectedId)) return true

    return false
  },

  relationshipEdgeTargetCount(totalCount, selectionEmphasis) {
    if (selectionEmphasis) {
      return Math.min(totalCount, this.state.focusNeighborhoodOnly ? 24 : 36)
    }

    return Math.min(totalCount, 18)
  },

  edgeKey(edge) {
    return `${edge.kind}:${edge.label}:${edge.source}->${edge.target}`
  },

  rendererMode() {
    return typeof navigator !== "undefined" && navigator.gpu ? "webgpu-capable" : "fallback"
  },

  maskIndex(node) {
    return node?.originalIndex ?? node?.index ?? 0
  },

  filterGraphByVisibility(graph, visibilityMask, selectionEmphasis) {
    if (!graph) return graph

    const keepIndexes = new Set()

    graph.nodes.forEach((node) => {
      if (this.nodeVisible(node, visibilityMask, selectionEmphasis)) {
        keepIndexes.add(node.index)
      }
    })

    if (keepIndexes.size === 0 || keepIndexes.size === graph.nodes.length) {
      return graph
    }

    const indexMap = new Map()
    const nodes = graph.nodes
      .filter((node) => keepIndexes.has(node.index))
      .map((node, newIndex) => {
        indexMap.set(node.index, newIndex)
        return {...node, index: newIndex, originalIndex: this.maskIndex(node)}
      })

    const edges = graph.edges
      .filter((edge) => keepIndexes.has(edge.source) && keepIndexes.has(edge.target))
      .map((edge) => ({
        ...edge,
        source: indexMap.get(edge.source),
        target: indexMap.get(edge.target),
      }))

    return {
      ...graph,
      nodes,
      edges,
    }
  },

  filterGraphForFocus(graph, selectionEmphasis) {
    if (!graph || !this.state.focusNeighborhoodOnly || !selectionEmphasis) return graph

    const keepIndexes = new Set()
    const selectedIndex = selectionEmphasis.selectedIndex

    graph.nodes.forEach((node) => {
      const nodeId = node.details?.id ? String(node.details.id) : null
      if (node.index === selectedIndex) keepIndexes.add(node.index)
      if (nodeId && selectionEmphasis.focusIds.has(nodeId)) keepIndexes.add(node.index)
    })

    if (selectedIndex != null) {
      if (this.state.messageFocusOnly) {
        this.expandMessageFocusNeighborhood(graph, keepIndexes, selectedIndex)
      } else {
        this.expandRelationshipFocusNeighborhood(graph, keepIndexes, selectedIndex)
      }
    }

    if (keepIndexes.size === 0 || keepIndexes.size === graph.nodes.length) return graph

    const indexMap = new Map()
    const nodes = graph.nodes
      .filter((node) => keepIndexes.has(node.index))
      .map((node, newIndex) => {
        indexMap.set(node.index, newIndex)
        return {...node, index: newIndex, originalIndex: this.maskIndex(node)}
      })

    const edges = graph.edges
      .filter((edge) => keepIndexes.has(edge.source) && keepIndexes.has(edge.target))
      .map((edge) => ({
        ...edge,
        source: indexMap.get(edge.source),
        target: indexMap.get(edge.target),
      }))

    return {
      ...graph,
      nodes,
      edges,
    }
  },

  expandMessageFocusNeighborhood(graph, keepIndexes, selectedIndex) {
    const adjacency = new Map()

    graph.edges.forEach((edge) => {
      const source = edge.source
      const target = edge.target
      if (!adjacency.has(source)) adjacency.set(source, [])
      if (!adjacency.has(target)) adjacency.set(target, [])
      adjacency.get(source).push(edge)
      adjacency.get(target).push(edge)
    })

    const queue = [{index: selectedIndex, depth: 0}]
    const visited = new Set([selectedIndex])

    while (queue.length > 0) {
      const {index, depth} = queue.shift()
      keepIndexes.add(index)
      if (depth >= 2) continue

      const edges = adjacency.get(index) || []
      edges.forEach((edge) => {
        if (edge.kind === "relationship") return
        const nextIndex = edge.source === index ? edge.target : edge.source
        if (visited.has(nextIndex)) return
        visited.add(nextIndex)
        queue.push({index: nextIndex, depth: depth + 1})
      })
    }
  },

  expandRelationshipFocusNeighborhood(graph, keepIndexes, selectedIndex) {
    const selectedNode = graph.nodes[selectedIndex]
    if (!selectedNode) return

    if (selectedNode.kind === "channel" || selectedNode.kind === "conversation") {
      graph.edges.forEach((edge) => {
        const touchesSelected = edge.source === selectedIndex || edge.target === selectedIndex
        if (!touchesSelected) return
        if (edge.kind !== "conversation") return

        keepIndexes.add(edge.source)
        keepIndexes.add(edge.target)
      })

      return
    }

    graph.edges.forEach((edge) => {
      const touchesSelected = edge.source === selectedIndex || edge.target === selectedIndex
      if (!touchesSelected) return

      if (edge.kind === "authored" || edge.kind === "in_channel") return

      keepIndexes.add(edge.source)
      keepIndexes.add(edge.target)
    })
  },

  tooltipText(object) {
    if (!object) return "node"

    if (object.details?.type === "cluster") {
      const sample = object.details?.sample_label ? `\nExample: ${object.details.sample_label}` : ""
      const count = object.clusterCount || object.details?.cluster_count || 0
      const kind = object.details?.cluster_kind || object.kind || "node"
      return `Cluster: ${count} ${kind}${count === 1 ? "" : "s"}\nScope: ${object.details?.cluster_scope || "unknown"}${sample}`
    }

    if (object.kind === "actor") {
      return `Actor: ${object.label || object.details?.handle || "unknown"}`
    }

    if (object.kind === "channel") {
      return `Channel: ${object.label || object.details?.name || "unknown"}`
    }

    if (object.kind === "conversation") {
      return `Conversation\n${object.details?.message_count || 0} messages · ${object.details?.actor_count || 0} actors`
    }

    if (object.kind === "message") {
      const body = typeof object.details?.body === "string" ? object.details.body : object.label
      return `Message\n${body || ""}`.trim()
    }

    return object.label || object.details?.name || object.details?.handle || "node"
  },

  nodeLabelData(nodes, visibilityMask, selectionEmphasis) {
    return nodes
      .filter((node) => visibilityMask[this.maskIndex(node)] === 1)
      .filter((node) => this.shouldShowNodeLabel(node, selectionEmphasis))
      .map((node) => ({
        position: [node.x, node.y],
        text: this.nodeLabel(node),
        size: node.details?.type === "cluster" ? 12 : 11,
        color: this.nodeLabelColor(node, selectionEmphasis),
      }))
  },

  edgeLabelData(edges, visibilityMask, selectionEmphasis) {
    return edges
      .filter(
        (edge) =>
          visibilityMask[this.maskIndex(edge.sourceNode)] === 1 &&
          visibilityMask[this.maskIndex(edge.targetNode)] === 1,
      )
      .filter((edge) => this.shouldShowEdgeLabel(edge, selectionEmphasis))
      .map((edge) => ({
        position: [
          ((edge.sourceNode?.x || 0) + (edge.targetNode?.x || 0)) / 2,
          ((edge.sourceNode?.y || 0) + (edge.targetNode?.y || 0)) / 2,
        ],
        text: edge.label || edge.kind,
        size: 10,
        color: [248, 250, 252, 215],
      }))
  },

  shouldShowNodeLabel(node, selectionEmphasis) {
    if (this.state.labelMode === "all") {
      return this.shouldShowExpandedLabel(node, selectionEmphasis)
    }

    if (!this.state.focusNeighborhoodOnly) {
      return node.kind === "channel" && node.details?.type !== "cluster"
    }

    const emphasis = this.nodeEmphasis(node, selectionEmphasis)

    if (this.isSelectedNode(node)) return true
    if (emphasis === "dossier") return true
    if (this.shouldShowNeighborhoodLabel(node, emphasis)) return true
    return false
  },

  shouldShowExpandedLabel(node, selectionEmphasis) {
    if (!node || node.details?.type === "cluster") return false
    if (node.kind === "message") return this.isSelectedNode(node)
    if (node.kind === "actor" || node.kind === "channel") return true

    const emphasis = this.nodeEmphasis(node, selectionEmphasis)
    return emphasis !== "dim"
  },

  shouldShowNeighborhoodLabel(node, emphasis) {
    if (!this.state.focusNeighborhoodOnly) return false
    if (!node || node.details?.type === "cluster") return false
    if (node.kind === "message") return false
    if (node.kind === "conversation") return emphasis !== "dim"
    if (emphasis === "dim") return false
    if (node.kind === "channel") return true

    const profile = node.details?.graph_profile || {}
    const majorRole = new Set(["anchor", "hub", "bridge"])
    if (majorRole.has(profile.community_role)) return true
    if ((profile.degree || 0) >= 3) return true
    if (profile.degree_band && profile.degree_band !== "leaf") return true

    return false
  },

  shouldShowEdgeLabel(edge, selectionEmphasis) {
    const sourceEmphasis = this.nodeEmphasis(edge.sourceNode, selectionEmphasis)
    const targetEmphasis = this.nodeEmphasis(edge.targetNode, selectionEmphasis)
    const strong = this.edgeEmphasis(sourceEmphasis, targetEmphasis) === "strong"
    return strong && this.state.selectedNode?.details?.id != null
  },

  nodeLabel(node) {
    if (node.details?.type === "cluster") {
      const count = node.clusterCount || node.details?.cluster_count || 0
      const kind = node.details?.cluster_kind || node.kind || "node"
      return `${count} ${kind}${count === 1 ? "" : "s"}`
    }

    if (node.kind === "actor") return `@${node.label || node.details?.handle || "actor"}`
    if (node.kind === "channel") {
      const raw = node.label || node.details?.name || "channel"
      return raw.startsWith("#") ? raw : `#${raw}`
    }
    if (node.kind === "conversation") {
      const count = Number(node.details?.message_count || 0)
      return `${count} msg${count === 1 ? "" : "s"}`
    }
    if (node.kind === "message") return "msg"

    return node.label || node.details?.name || node.details?.handle || node.details?.external_id || "node"
  },

  nodeLabelColor(node, selectionEmphasis) {
    const emphasis = this.nodeEmphasis(node, selectionEmphasis)
    if (emphasis === "selected") return [255, 255, 255, 255]
    if (emphasis === "dim") return [203, 213, 225, 170]
    return [248, 250, 252, 235]
  },

  isSelectedNode(node) {
    const selectedId = this.state.selectedNode?.details?.id
    const nodeId = node?.details?.id
    if (selectedId && nodeId) return String(selectedId) === String(nodeId)
    return this.state.selectedNodeIndex === node?.index
  },

  nodeVisible(node, visibilityMask, selectionEmphasis) {
    if (visibilityMask[this.maskIndex(node)] !== 1) return false

    if (node.details?.type === "cluster") return true

    const kindVisible = this.state.nodeKinds[node.kind]
    if (kindVisible !== false) return true

    if (selectionEmphasis) {
      const emphasis = this.nodeEmphasis(node, selectionEmphasis)
      if (emphasis === "selected" || emphasis === "dossier") return true
    }

    if (node.kind !== "message") return false

    if (!selectionEmphasis) return false
    const emphasis = this.nodeEmphasis(node, selectionEmphasis)
    return emphasis === "selected" || emphasis === "dossier"
  },

  relationshipVisible(edge) {
    if (edge.kind !== "relationship") return true
    const type = this.relationshipType(edge)
    return this.state.relationshipTypes[type] !== false
  },

  relationshipType(edge) {
    if (edge.label === "MENTIONED") return "mentioned"
    if (edge.label === "CO_MENTIONED") return "co_mentioned"
    if (edge.label === "ACTIVE_IN") return "active_in"
    return "other"
  },
}
