export const threadrGraphRenderingSelectionMethods = {
  updateSummary(text) {
    if (this.state.summaryEl) this.state.summaryEl.textContent = text
  },

  updateSelectionDetails(node = null) {
    if (!this.state.detailsEl) return

    if (!node) {
      this.state.selectedNodeDetail = null
      this.state.detailsEl.innerHTML =
        "<div class=\"font-semibold\">Selection</div><div>No node selected.</div>"
      this.updateFocusControls()
      return
    }

    const detail = this.state.selectedNodeDetail
    const isLoading =
      node.details?.type !== "cluster" &&
      (!detail || detail.focal?.id !== (node.details?.id || null))

    const kind = this.escapeHtml(node.kind || "other")
    const platform = this.escapeHtml(node.details?.platform || "unknown")
    const handle = this.escapeHtml(
      node.details?.handle ||
      node.details?.name ||
      node.details?.display_name ||
      node.details?.external_id ||
      "unknown",
    )
    const body =
      node.kind === "message" && typeof node.details?.body === "string"
        ? `<div class="mt-2 text-base-content/70">${this.escapeHtml(node.details.body)}</div>`
        : ""
    const clusterMeta =
      node.details?.cluster_scope
        ? `<div>Cluster: ${this.escapeHtml(node.details.cluster_scope)} (${this.escapeHtml(String(node.details.cluster_count || 0))} nodes)</div>`
        : ""
    const neighborhoodMeta =
      node.details?.type !== "cluster"
        ? this.renderNeighborhoodSummary(node)
        : `
            <div>Dominant neighbor kind: ${this.escapeHtml(node.details?.dominant_neighbor_kind || "unknown")}</div>
            <div>Dominant relationship: ${this.escapeHtml(node.details?.dominant_relationship || "unknown")}</div>
            <div>Degree band: ${this.escapeHtml(node.details?.degree_band || "unknown")}</div>
            <div>Component: ${this.escapeHtml(String(node.details?.component_id || "unknown"))}</div>
            <div>Community: ${this.escapeHtml(String(node.details?.community_id || "unknown"))}</div>
            <div>Community role: ${this.escapeHtml(String(node.details?.community_role || "unknown"))}</div>
          `
    const dossier = node.details?.type !== "cluster" ? this.renderNodeDossier(detail, isLoading) : ""

    this.state.detailsEl.innerHTML = `
      <div class="font-semibold mb-1">${this.escapeHtml(node.label || "node")}</div>
      <div>Type: ${kind}</div>
      <div>Platform: ${platform}</div>
      <div>Reference: ${handle}</div>
      <div>Messages: ${this.escapeHtml(String(node.details?.message_count ?? "0"))}</div>
      ${clusterMeta}
      ${neighborhoodMeta}
      ${body}
      ${dossier}
    `
    this.updateFocusControls()
  },

  handlePick(node) {
    if (!node) return
    this.state.selectedNodeIndex = node.index
    this.state.selectedNode = node
    this.state.selectedNodeDetail = this.cachedDetailFor(node)
    this.updateSelectionDetails(node)
    this.requestNodeDetail(node)
    this.renderGraph()
  },

  togglePinFocus() {
    const node = this.state.selectedNode
    if (!node || node.details?.type === "cluster") return

    const nodeId = node.details?.id
    if (!nodeId) return

    if (this.state.pinnedNodeId === nodeId) {
      this.clearPinnedFocus()
      return
    }

    this.state.pinnedNodeId = nodeId
    this.state.pinnedNodeKind = node.kind
    this.state.pinnedNodeLabel = node.label || nodeId
    this.state.pinnedNodeDetail = this.cachedDetailFor(node) || this.state.selectedNodeDetail || null
    this.updateFocusControls()
    this.centerOnFocusContext()
    this.renderGraph()
  },

  clearPinnedFocus() {
    this.state.pinnedNodeId = null
    this.state.pinnedNodeKind = null
    this.state.pinnedNodeLabel = null
    this.state.pinnedNodeDetail = null
    this.updateFocusControls()
    this.renderGraph()
  },

  updateFocusControls() {
    if (!this.state.focusStatusEl || !this.state.focusButtonEl) return

    const selectedNode = this.state.selectedNode
    const pinned = Boolean(this.state.pinnedNodeId)
    const selectable = selectedNode && selectedNode.details?.type !== "cluster" && selectedNode.details?.id

    this.state.focusStatusEl.textContent = pinned
      ? `Focus pinned to ${this.state.pinnedNodeLabel || "node"}`
      : "Focus follows selection"

    this.state.focusButtonEl.disabled = !selectable
    this.state.focusButtonEl.textContent =
      pinned && selectedNode?.details?.id === this.state.pinnedNodeId
        ? "Release focus"
        : pinned
          ? "Repin focus"
          : "Pin focus"
  },

  activeFocusNode() {
    if (this.state.pinnedNodeId) {
      return this.nodeById(this.state.pinnedNodeId) || this.state.selectedNode
    }

    return this.state.selectedNode
  },

  activeFocusDetail() {
    if (this.state.pinnedNodeId) {
      return this.state.pinnedNodeDetail || this.state.detailCache[this.state.pinnedNodeId] || null
    }

    return this.state.selectedNodeDetail
  },

  nodeById(nodeId) {
    if (!nodeId) return null
    return (this.state.graph?.nodes || []).find((node) => node.details?.id === nodeId) || null
  },

  syncSelectionState(graph) {
    if (!graph) return

    const refreshNode = (nodeId, fallbackIndex = null) => {
      if (!nodeId) {
        return fallbackIndex != null ? graph.nodes[fallbackIndex] || null : null
      }

      return graph.nodes.find((node) => node.details?.id === nodeId) || null
    }

    const selectedNodeId = this.state.selectedNode?.details?.id || null
    const nextSelectedNode = refreshNode(selectedNodeId, this.state.selectedNodeIndex)

    this.state.selectedNode = nextSelectedNode
    this.state.selectedNodeIndex = nextSelectedNode ? nextSelectedNode.index : null

    if (this.state.pinnedNodeId && !refreshNode(this.state.pinnedNodeId)) {
      this.state.pinnedNodeId = null
      this.state.pinnedNodeKind = null
      this.state.pinnedNodeLabel = null
      this.state.pinnedNodeDetail = null
    }

    this.updateFocusControls()
  },

  centerOnFocusContext() {
    const graph = this.state.graph
    if (!graph) return

    const focusNode = this.activeFocusNode()
    if (!focusNode) return

    const detail = this.activeFocusDetail()
    const focusIds = this.collectFocusIds(detail)
    const focusProfile = focusNode.details?.graph_profile || {}

    const focusNodes = graph.nodes.filter((node) => {
      const nodeId = node.details?.id || null
      const profile = node.details?.graph_profile || {}

      if (node.index === focusNode.index) return true
      if (nodeId && focusIds.has(String(nodeId))) return true
      if (focusProfile.community_id && profile.community_id === focusProfile.community_id) return true
      return false
    })

    if (focusNodes.length === 0) return

    const xs = focusNodes.map((node) => node.x)
    const ys = focusNodes.map((node) => node.y)
    const minX = Math.min(...xs)
    const maxX = Math.max(...xs)
    const minY = Math.min(...ys)
    const maxY = Math.max(...ys)
    const width = this.rootEl.clientWidth || 1200
    const height = this.rootEl.clientHeight || 700
    const spanX = Math.max(120, maxX - minX)
    const spanY = Math.max(120, maxY - minY)
    const scale = Math.min(width / spanX, height / spanY) * 0.42

    this.state.viewState = {
      target: [(minX + maxX) / 2, (minY + maxY) / 2, 0],
      zoom: Math.log2(scale),
    }
  },

  escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll("\"", "&quot;")
  },

  renderNeighborhoodSummary(node) {
    const profile = node.details?.graph_profile

    if (!profile) {
      throw new Error(`missing graph_profile for node ${node.label || node.id || "unknown"}`)
    }

    const relationshipSummary = Object.entries(profile.relationship_counts || {})
      .sort((a, b) => b[1] - a[1])
      .slice(0, 4)
      .map(([label, count]) => `${this.escapeHtml(label)} (${this.escapeHtml(String(count))})`)
      .join(", ")

    const adjacent = Array.isArray(profile.adjacent_labels)
      ? profile.adjacent_labels.map((label) => this.escapeHtml(label)).join(", ")
      : ""

    return `
      <div class="mt-2 border-t border-base-300/50 pt-2">
        <div class="font-semibold mb-1">Neighborhood</div>
        <div>Neighbors: ${this.escapeHtml(String(profile.adjacent_count || 0))}</div>
        <div>Degree: ${this.escapeHtml(String(profile.degree || 0))} (${this.escapeHtml(profile.degree_band || "unknown")})</div>
        <div>Component: ${this.escapeHtml(String(profile.component_id || "unknown"))}</div>
        <div>Component size: ${this.escapeHtml(String(profile.component_size || 0))}</div>
        <div>Community: ${this.escapeHtml(String(profile.community_id || "unknown"))}</div>
        <div>Community role: ${this.escapeHtml(String(profile.community_role || "unknown"))}</div>
        <div>Distance to anchor: ${this.escapeHtml(String(profile.distance_to_anchor ?? "unknown"))}</div>
        <div>Hop reach: 1=${this.escapeHtml(String(profile.one_hop_count || 0))}, 2=${this.escapeHtml(String(profile.two_hop_count || 0))}, 3=${this.escapeHtml(String(profile.three_hop_count || 0))}</div>
        <div>Dominant neighbor kind: ${this.escapeHtml(profile.dominant_neighbor_kind || "unknown")}</div>
        <div>Dominant relationship: ${this.escapeHtml(profile.dominant_relationship || "unknown")}</div>
        <div>Relationship types: ${relationshipSummary || "none"}</div>
        <div>Adjacent nodes: ${adjacent || "none"}</div>
      </div>
    `
  },

  requestNodeDetail(node) {
    if (!node || node.details?.type === "cluster") return
    if (!this.state.channel) return

    const nodeId = node.details?.id
    const nodeKind = node.kind
    if (!nodeId || !nodeKind) return

    const cached = this.cachedDetailFor(node)
    if (cached) {
      this.state.selectedNodeDetail = cached
      this.updateSelectionDetails(node)
      return
    }

    this.state.channel
      .push("inspect_node", {id: nodeId, kind: nodeKind})
      .receive("ok", ({detail}) => {
        this.state.detailCache[nodeId] = detail

        if (this.state.selectedNode?.details?.id === nodeId) {
          this.state.selectedNodeDetail = detail
          this.updateSelectionDetails(this.state.selectedNode)
        }

        if (this.state.pinnedNodeId === nodeId) {
          this.state.pinnedNodeDetail = detail
          this.centerOnFocusContext()
          this.renderGraph()
        }
      })
      .receive("error", () => {
        if (this.state.selectedNode?.details?.id === nodeId) {
          this.state.selectedNodeDetail = {error: "detail_unavailable"}
          this.updateSelectionDetails(this.state.selectedNode)
        }

        if (this.state.pinnedNodeId === nodeId) {
          this.state.pinnedNodeDetail = {error: "detail_unavailable"}
          this.renderGraph()
        }
      })
  },

  cachedDetailFor(node) {
    const nodeId = node?.details?.id
    if (!nodeId) return null
    return this.state.detailCache[nodeId] || null
  },

  renderNodeDossier(detail, isLoading) {
    if (isLoading) {
      return `
        <div class="mt-2 border-t border-base-300/50 pt-2">
          <div class="font-semibold mb-1">Dossier</div>
          <div>Loading server-backed neighborhood…</div>
        </div>
      `
    }

    if (!detail) return ""

    if (detail.error) {
      return `
        <div class="mt-2 border-t border-base-300/50 pt-2">
          <div class="font-semibold mb-1">Dossier</div>
          <div>Server-backed detail unavailable.</div>
        </div>
      `
    }

    const summary = detail.summary || {}
    const topRelationships = Array.isArray(detail.top_relationships) ? detail.top_relationships.slice(0, 4) : []
    const topChannels = Array.isArray(detail.top_channels) ? detail.top_channels.slice(0, 4) : []
    const topActors = Array.isArray(detail.top_actors) ? detail.top_actors.slice(0, 4) : []
    const recentMessages = Array.isArray(detail.recent_messages) ? detail.recent_messages.slice(0, 4) : []
    const neighborhood = detail.neighborhood || {}

    return `
      <div class="mt-2 border-t border-base-300/50 pt-2">
        <div class="font-semibold mb-1">Dossier</div>
        <div>Recent messages: ${this.escapeHtml(String(summary.message_count || recentMessages.length || 0))}</div>
        <div>Neighborhood actors: ${this.escapeHtml(String(summary.related_actor_count || neighborhood.actors?.length || 0))}</div>
        <div>Neighborhood relationships: ${this.escapeHtml(String(summary.related_relationship_count || neighborhood.relationships?.length || 0))}</div>
        ${this.renderListSection("Top relationships", topRelationships, (item) =>
          `${this.escapeHtml(item.relationship_type || "unknown")} ${this.escapeHtml(item.from_actor_handle || "unknown")} → ${this.escapeHtml(item.to_actor_handle || "unknown")} (${this.escapeHtml(String(item.weight || 0))})`,
        )}
        ${this.renderListSection("Top channels", topChannels, (item) =>
          `${this.escapeHtml(item.channel_name || "unknown")} (${this.escapeHtml(String(item.message_count || 0))})`,
        )}
        ${this.renderListSection("Top actors", topActors, (item) =>
          `${this.escapeHtml(item.actor_display_name || item.actor_handle || "unknown")} (${this.escapeHtml(String(item.message_count || 0))})`,
        )}
        ${this.renderListSection("Recent messages", recentMessages, (item) =>
          `${this.escapeHtml(item.actor_handle || item.channel_name || "message")} · ${this.escapeHtml((item.body || "").slice(0, 72) || "message")}`,
        )}
      </div>
    `
  },

  renderListSection(title, items, formatter) {
    if (!Array.isArray(items) || items.length === 0) return ""

    const rows = items
      .map((item) => `<li>${formatter(item)}</li>`)
      .join("")

    return `
      <div class="mt-2">
        <div class="font-semibold mb-1">${this.escapeHtml(title)}</div>
        <ul class="list-disc pl-4 space-y-1">${rows}</ul>
      </div>
    `
  },
}
