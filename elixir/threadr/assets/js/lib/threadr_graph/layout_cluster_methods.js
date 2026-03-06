export const threadrGraphLayoutClusterMethods = {
  resolveZoomTier(zoom) {
    if (zoom < -0.25) return "global"
    if (zoom < 0.9) return "regional"
    return "local"
  },

  setZoomTier(nextTier, forceRender = false) {
    if (!nextTier) return
    if (!forceRender && this.state.zoomTier === nextTier) return

    this.state.zoomTier = nextTier
    if (nextTier !== "local") this.state.selectedNodeIndex = null
    this.updateSelectionDetails(null)
    if (this.state.graph) this.renderGraph()
  },

  setZoomMode(mode) {
    this.state.zoomMode = mode || "auto"
    if (this.state.deck) {
      const currentZoom = Number(this.state.deck.viewState?.zoom || 0)
      this.setZoomTier(this.resolveZoomTier(currentZoom), true)
      return
    }
    this.renderGraph()
  },

  reshapeGraph(graph) {
    const tier = this.state.zoomMode === "auto" ? this.state.zoomTier : this.state.zoomMode
    if (tier === "local") return {shape: "local", ...graph}
    if (tier === "global") return this.reclusterByNeighborhood(graph)
    return this.reclusterByGrid(graph)
  },

  reclusterByNeighborhood(graph) {
    const clusters = new Map()
    const clusterByNode = new Array(graph.nodes.length)

    graph.nodes.forEach((node, index) => {
      const profile = this.graphProfileForNode(node)
      const key =
        `neighborhood:${node.kind}:${node.state}:${profile.component_id || "none"}:${profile.degree_band}:${profile.dominant_neighbor_kind}:${profile.dominant_relationship}`
      const existing = clusters.get(key) || this.emptyCluster(key)
      existing.profile = profile
      this.mergeNodeIntoCluster(existing, node)
      clusters.set(key, existing)
      clusterByNode[index] = key
    })

    const nodes = Array.from(clusters.values()).map((cluster, index) =>
      this.clusterToNode(cluster, index, `${cluster.kind} neighborhood`, "global"),
    )
    const nodeIndexByCluster = new Map(nodes.map((node, index) => [node.id, index]))
    const edges = this.clusterEdges(graph.edges, clusterByNode, nodeIndexByCluster)

    return {shape: "global", nodes, edges}
  },

  reclusterByGrid(graph) {
    const cell = 180
    const clusters = new Map()
    const clusterByNode = new Array(graph.nodes.length)

    graph.nodes.forEach((node, index) => {
      const gx = Math.floor(node.x / cell)
      const gy = Math.floor(node.y / cell)
      const key = `grid:${gx}:${gy}`
      const existing = clusters.get(key) || this.emptyCluster(key)
      existing.grid = {x: gx, y: gy}
      this.mergeNodeIntoCluster(existing, node)
      clusters.set(key, existing)
      clusterByNode[index] = key
    })

    const nodes = Array.from(clusters.values()).map((cluster, index) =>
      this.clusterToNode(
        cluster,
        index,
        `grid ${cluster.grid?.x ?? 0},${cluster.grid?.y ?? 0}`,
        "regional",
      ),
    )
    const nodeIndexByCluster = new Map(nodes.map((node, index) => [node.id, index]))
    const edges = this.clusterEdges(graph.edges, clusterByNode, nodeIndexByCluster)

    return {shape: "regional", nodes, edges}
  },

  emptyCluster(id) {
    return {
      id,
      sumX: 0,
      sumY: 0,
      count: 0,
      dominantStateCount: {0: 0, 1: 0, 2: 0, 3: 0},
      kindCount: {},
      sampleNode: null,
      kind: "other",
      profile: null,
    }
  },

  mergeNodeIntoCluster(cluster, node) {
    cluster.sumX += Number(node.x || 0)
    cluster.sumY += Number(node.y || 0)
    cluster.count += 1
    cluster.dominantStateCount[node.state] = (cluster.dominantStateCount[node.state] || 0) + 1
    cluster.kindCount[node.kind] = (cluster.kindCount[node.kind] || 0) + 1
    cluster.kind = Object.entries(cluster.kindCount).sort((a, b) => b[1] - a[1])[0]?.[0] || "other"
    if (!cluster.sampleNode) cluster.sampleNode = node
  },

  clusterToNode(cluster, index, labelSuffix, scope) {
    const dominantState = [0, 1, 2, 3].sort(
      (a, b) => (cluster.dominantStateCount[b] || 0) - (cluster.dominantStateCount[a] || 0),
    )[0]

    return {
      id: cluster.id,
      index,
      x: cluster.sumX / Math.max(1, cluster.count),
      y: cluster.sumY / Math.max(1, cluster.count),
      state: dominantState,
      kind: cluster.kind,
      size: Math.min(34, 12 + ((cluster.count - 1) * 0.75)),
      label: `${this.kindDisplayName(cluster.kind)} ${labelSuffix}`,
      clusterCount: cluster.count,
      details: {
        type: "cluster",
        cluster_scope: scope,
        cluster_count: cluster.count,
        cluster_kind: cluster.kind,
        sample_label: cluster.sampleNode?.label || null,
        dominant_neighbor_kind: cluster.profile?.dominant_neighbor_kind || null,
        dominant_relationship: cluster.profile?.dominant_relationship || null,
        degree_band: cluster.profile?.degree_band || null,
        component_id: cluster.profile?.component_id || null,
      },
    }
  },

  clusterEdges(edges, clusterByNode, nodeIndexByCluster) {
    const acc = new Map()

    edges.forEach((edge) => {
      const sourceCluster = clusterByNode[edge.source]
      const targetCluster = clusterByNode[edge.target]
      if (!sourceCluster || !targetCluster || sourceCluster === targetCluster) return

      const left = sourceCluster < targetCluster ? sourceCluster : targetCluster
      const right = sourceCluster < targetCluster ? targetCluster : sourceCluster
      const key = `${left}|${right}|${edge.kind}`
      const current = acc.get(key) || {
        source: nodeIndexByCluster.get(left),
        target: nodeIndexByCluster.get(right),
        weight: 0,
        label: edge.kind,
        kind: edge.kind,
        labelCounts: {},
      }
      current.weight += Number(edge.weight || 1)
      current.labelCounts[edge.label] = (current.labelCounts[edge.label] || 0) + Number(edge.weight || 1)
      current.label = Object.entries(current.labelCounts).sort((a, b) => b[1] - a[1])[0]?.[0] || edge.kind
      acc.set(key, current)
    })

    return Array.from(acc.values()).filter((edge) => Number.isInteger(edge.source) && Number.isInteger(edge.target))
  },

  graphProfileForNode(node) {
    const profile = node?.details?.graph_profile

    if (!profile) {
      throw new Error(`missing graph_profile for node ${node?.label || node?.id || "unknown"}`)
    }

    return profile
  },

  kindDisplayName(kind) {
    if (kind === "actor") return "Actor"
    if (kind === "channel") return "Channel"
    if (kind === "message") return "Message"
    return "Graph"
  },
}
