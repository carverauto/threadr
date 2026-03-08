export const threadrGraphRenderingSelectionMethods = {
  clearSelection(clearPinned = false) {
    this.state.selectedNodeIndex = null
    this.state.selectedNode = null
    this.state.selectedNodeDetail = null

    if (clearPinned) {
      this.state.pinnedNodeId = null
      this.state.pinnedNodeKind = null
      this.state.pinnedNodeLabel = null
      this.state.pinnedNodeDetail = null
    }

    this.updateSelectionDetails(null)
    this.renderGraph()
  },

  updateSelectionDetails(node = null) {
    if (!this.state.detailsEl) return

    if (!node) {
      this.state.selectedNodeDetail = null
      this.state.detailsEl.innerHTML =
        "<div class=\"font-semibold\">Selection</div><div>No node selected.</div>"
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
    const dossier =
      node.details?.type !== "cluster" ? this.renderNodeDossier(node, detail, isLoading) : ""
    const actions = this.renderNodeActions(node, detail)

    this.state.detailsEl.innerHTML = `
      <div class="font-semibold mb-1">${this.escapeHtml(node.label || "node")}</div>
      <div>Type: ${kind}</div>
      <div>Platform: ${platform}</div>
      <div>Reference: ${handle}</div>
      <div>Messages: ${this.escapeHtml(String(node.details?.message_count ?? "0"))}</div>
      ${this.renderFocusControls(node)}
      ${actions}
      ${clusterMeta}
      ${neighborhoodMeta}
      ${body}
      ${dossier}
    `
  },

  handlePick(node) {
    if (!node) return
    this.state.selectedNodeIndex = node.index
    this.state.selectedNode = node
    this.state.selectedNodeDetail = this.cachedDetailFor(node)
    this.ensureNodeFocusMode(node)

    if (node.kind === "channel" || node.kind === "conversation") {
      this.state.pinnedNodeId = node.details?.id || null
      this.state.pinnedNodeKind = node.kind
      this.state.pinnedNodeLabel = node.label || node.details?.id || null
      this.state.pinnedNodeDetail = this.cachedDetailFor(node)
    }

    this.centerOnInvestigationGraph()
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
    this.ensureNodeFocusMode(node)
    this.updateSelectionDetails(this.state.selectedNode || node)
    this.centerOnInvestigationGraph()
    this.renderGraph()
  },

  toggleFocusNeighborhood() {
    const focusNode = this.activeFocusNode()
    if (!focusNode) return

    if (this.state.messageFocusOnly) {
      this.state.messageFocusOnly = false
      this.state.conversationFocusOnly = true
      this.state.focusNeighborhoodOnly = true
      this.state.nodeKinds = {
        ...this.state.nodeKinds,
        conversation: true,
        message: false,
      }
      this.state.edgeLayers = {
        ...this.state.edgeLayers,
        relationship: false,
        conversation: true,
        authored: false,
        in_channel: false,
      }
      this.centerOnInvestigationGraph()
      this.updateSelectionDetails(this.state.selectedNode)
      this.renderGraph()
      return
    }

    this.showChannelOverview()
  },

  clearPinnedFocus() {
    this.state.pinnedNodeId = null
    this.state.pinnedNodeKind = null
    this.state.pinnedNodeLabel = null
    this.state.pinnedNodeDetail = null
    this.updateSelectionDetails(this.state.selectedNode)
    this.renderGraph()
  },

  showMessagesForFocus() {
    const node = this.activeFocusNode() || this.state.selectedNode
    if (!node || node.details?.type === "cluster") return

    if (node.kind === "channel") {
      this.activateConversationFocusMode()
    } else {
      this.activateMessageFocusMode()
    }

    if (!this.state.pinnedNodeId && node.details?.id) {
      this.state.pinnedNodeId = node.details.id
      this.state.pinnedNodeKind = node.kind
      this.state.pinnedNodeLabel = node.label || node.details.id
      this.state.pinnedNodeDetail = this.cachedDetailFor(node) || this.state.selectedNodeDetail || null
    }

    this.centerOnInvestigationGraph()
    this.updateSelectionDetails(this.state.selectedNode || node)
    this.renderGraph()
  },

  showChannelOverview() {
    this.state.selectedNodeIndex = null
    this.state.selectedNode = null
    this.state.selectedNodeDetail = null
    this.state.pinnedNodeId = null
    this.state.pinnedNodeKind = null
    this.state.pinnedNodeLabel = null
    this.state.pinnedNodeDetail = null
    this.state.focusNeighborhoodOnly = false
    this.state.conversationFocusOnly = false
    this.state.messageFocusOnly = false
    this.state.nodeKinds = {...this.state.defaultNodeKinds}
    this.state.edgeLayers = {...this.state.defaultEdgeLayers}
    this.state.viewState = this.initialViewState()
    this.updateSelectionDetails(null)
    this.renderGraph()
  },

  ensureNodeFocusMode(node) {
    if (!node || node.details?.type === "cluster") return

    if (node.kind === "channel") {
      this.activateConversationFocusMode()
      return
    }

    if (node.kind === "conversation" || node.kind === "message") {
      this.activateMessageFocusMode()
      return
    }

    if (!this.state.focusNeighborhoodOnly) return

    this.state.conversationFocusOnly = false
    this.state.messageFocusOnly = false
    this.state.edgeLayers = {
      ...this.state.edgeLayers,
      relationship: true,
    }
  },

  activateMessageFocusMode() {
    this.state.nodeKinds = {
      ...this.state.nodeKinds,
      actor: true,
      conversation: true,
      message: true,
    }
    this.state.edgeLayers = {
      ...this.state.edgeLayers,
      relationship: false,
      conversation: true,
      authored: false,
      in_channel: false,
    }
    this.state.focusNeighborhoodOnly = true
    this.state.conversationFocusOnly = false
    this.state.messageFocusOnly = true
  },

  activateConversationFocusMode() {
    this.state.nodeKinds = {
      ...this.state.nodeKinds,
      actor: false,
      channel: true,
      conversation: true,
      message: false,
    }
    this.state.edgeLayers = {
      ...this.state.edgeLayers,
      relationship: false,
      conversation: true,
      authored: false,
      in_channel: false,
    }
    this.state.focusNeighborhoodOnly = true
    this.state.conversationFocusOnly = true
    this.state.messageFocusOnly = false
  },

  activeFocusNode() {
    if (this.state.pinnedNodeId) {
      return this.nodeById(this.state.pinnedNodeId) || this.state.selectedNode
    }

    return this.state.selectedNode
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
    if (!nextSelectedNode) this.state.selectedNodeDetail = null

    if (this.state.pinnedNodeId && !refreshNode(this.state.pinnedNodeId)) {
      this.state.pinnedNodeId = null
      this.state.pinnedNodeKind = null
      this.state.pinnedNodeLabel = null
      this.state.pinnedNodeDetail = null
    }
  },

  centerOnInvestigationGraph() {
    const graph = this.state.graph
    if (!graph) return

    const focusGraph = this.investigationGraph(graph)
    const nodes = focusGraph?.nodes || []
    if (nodes.length === 0) return

    const xs = nodes.map((node) => Number(node.x || 0))
    const ys = nodes.map((node) => Number(node.y || 0))
    const minX = Math.min(...xs)
    const maxX = Math.max(...xs)
    const minY = Math.min(...ys)
    const maxY = Math.max(...ys)
    const width = this.rootEl.clientWidth || 1200
    const height = this.rootEl.clientHeight || 700
    const spanX = Math.max(180, maxX - minX)
    const spanY = Math.max(180, maxY - minY)
    const scale = Math.min(width / spanX, height / spanY) * 0.5

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
      .slice(0, 3)
      .map(([label, count]) => `${this.escapeHtml(label)} (${this.escapeHtml(String(count))})`)
      .join(", ")

    const adjacent = Array.isArray(profile.adjacent_labels)
      ? profile.adjacent_labels.map((label) => this.escapeHtml(label)).join(", ")
      : ""

    return `
      <div class="mt-2 min-w-0 overflow-hidden border-t border-base-300/50 pt-2">
        <div class="font-semibold mb-1">Local context</div>
        <div>Direct links: ${this.escapeHtml(String(profile.adjacent_count || 0))}</div>
        <div>Main relationship: ${this.escapeHtml(profile.dominant_relationship || "unknown")}</div>
        <div class="break-words">Relationship mix: ${relationshipSummary || "none"}</div>
        <div class="break-words">Connected to: ${adjacent || "none"}</div>
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

  renderNodeDossier(node, detail, isLoading) {
    if (isLoading) {
      return `
        <div class="mt-2 min-w-0 overflow-hidden border-t border-base-300/50 pt-2">
          <div class="font-semibold mb-1">Dossier</div>
          <div>Loading server-backed neighborhood…</div>
        </div>
      `
    }

    if (!detail) return ""

    if (detail.error) {
      return `
        <div class="mt-2 min-w-0 overflow-hidden border-t border-base-300/50 pt-2">
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
      <div class="mt-2 min-w-0 overflow-hidden border-t border-base-300/50 pt-2">
        <div class="font-semibold mb-1">Dossier</div>
        <div>Recent messages: ${this.escapeHtml(String(summary.message_count || recentMessages.length || 0))}</div>
        <div>Neighborhood actors: ${this.escapeHtml(String(summary.related_actor_count || neighborhood.actors?.length || 0))}</div>
        <div>Neighborhood relationships: ${this.escapeHtml(String(summary.related_relationship_count || neighborhood.relationships?.length || 0))}</div>
        ${this.renderTopRelationshipsSection(node, topRelationships)}
        ${this.renderTopChannelsSection(topChannels)}
        ${this.renderTopActorsSection(topActors)}
        ${this.renderRecentMessagesSection(recentMessages)}
      </div>
    `
  },

  renderNodeActions(node, detail) {
    if (node.details?.type === "cluster") return ""

    const subjectName = this.state.subjectName
    const nodeId = node.details?.id
    const nodeKind = node.kind

    if (!subjectName || !nodeId || !nodeKind) return ""

    const actions = []
    const question = this.defaultQuestionForNode(node, detail)
    const qaHref = this.qaHref(question)

    if (nodeKind === "actor" || nodeKind === "channel") {
      actions.push(this.renderActionLink(this.dossierHref(nodeKind, nodeId), "Open dossier"))
      actions.push(this.renderActionLink(this.historyHref(node), "Open history"))
      actions.push(
        this.renderActionButton(
          "show-focus-messages",
          nodeKind === "channel" ? "Show conversations" : "Show messages here",
        ),
      )
    }

    if (nodeKind === "conversation") {
      actions.push(this.renderActionButton("show-focus-messages", "Show messages here"))
    }

    if (nodeKind === "message") {
      actions.push(this.renderActionLink(this.dossierHref(nodeKind, nodeId), "Message dossier"))
    }

    actions.push(this.renderActionLink(qaHref, "Ask in QA"))

    return `
      <div class="mt-2 flex min-w-0 flex-wrap gap-2 overflow-hidden border-t border-base-300/50 pt-2">
        ${actions.join("")}
      </div>
    `
  },

  renderFocusControls(node) {
    if (node.details?.type === "cluster" || !node.details?.id) return ""

    const pinned = this.state.pinnedNodeId && String(this.state.pinnedNodeId) === String(node.details.id)
    const pinLabel = pinned ? "Release focus" : "Pin focus"
    const neighborhoodLabel = this.state.messageFocusOnly ? "Hide messages" : "Back to channels"
    const focusStatus = pinned
      ? `Focus pinned to ${this.escapeHtml(this.state.pinnedNodeLabel || node.label || "node")}`
      : "Focus follows selection"

    return `
      <div class="mt-2 min-w-0 overflow-hidden border-t border-base-300/50 pt-2">
        <div class="font-semibold mb-1">Focus</div>
        <div class="mb-2 text-base-content/70">${focusStatus}</div>
        <div class="flex flex-wrap gap-2">
          ${this.renderActionButton("toggle-pin-focus", pinLabel)}
          ${this.renderActionButton("toggle-focus-neighborhood", neighborhoodLabel)}
        </div>
      </div>
    `
  },

  dossierHref(nodeKind, nodeId) {
    const params = new URLSearchParams()
    if (this.state.since) params.set("since", this.state.since)
    if (this.state.until) params.set("until", this.state.until)
    if (this.state.compareSince) params.set("compare_since", this.state.compareSince)
    if (this.state.compareUntil) params.set("compare_until", this.state.compareUntil)
    const suffix = params.toString()
    return `/control-plane/tenants/${encodeURIComponent(this.state.subjectName)}/dossiers/${encodeURIComponent(nodeKind)}/${encodeURIComponent(nodeId)}${suffix ? `?${suffix}` : ""}`
  },

  qaHref(question) {
    const base = `/control-plane/tenants/${encodeURIComponent(this.state.subjectName)}/qa`
    const params = new URLSearchParams()
    if (question) params.set("question", question)
    if (this.state.since) params.set("since", this.state.since)
    if (this.state.until) params.set("until", this.state.until)
    if (this.state.compareSince) params.set("compare_since", this.state.compareSince)
    if (this.state.compareUntil) params.set("compare_until", this.state.compareUntil)
    const suffix = params.toString()
    return suffix ? `${base}?${suffix}` : base
  },

  historyHref(node) {
    const params = new URLSearchParams()
    const nodeKind = node.kind

    if (nodeKind === "actor") {
      params.set("actor_handle", node.details?.handle || node.label || "")
    } else if (nodeKind === "channel") {
      params.set("channel_name", node.details?.name || node.label || "")
    } else if (nodeKind === "message") {
      params.set("query", node.details?.body || node.label || "")
    }

    params.set("origin_surface", "graph")
    params.set("origin_node_kind", nodeKind)
    params.set("origin_node_id", node.details?.id || "")
    if (this.state.since) params.set("origin_since", this.state.since)
    if (this.state.until) params.set("origin_until", this.state.until)
    if (this.state.compareSince) params.set("origin_compare_since", this.state.compareSince)
    if (this.state.compareUntil) params.set("origin_compare_until", this.state.compareUntil)

    return `/control-plane/tenants/${encodeURIComponent(this.state.subjectName)}/history?${params.toString()}`
  },

  defaultQuestionForNode(node, detail) {
    if (node.kind === "actor") {
      const handle = node.details?.handle || node.label || "this person"
      return `What does ${handle} know?`
    }

    if (node.kind === "channel") {
      const channel = node.details?.name || node.label || "this channel"
      return `What happened in ${channel}?`
    }

    if (node.kind === "conversation") {
      return "What happened in this conversation?"
    }

    if (node.kind === "message") {
      const body =
        detail?.focal?.body ||
        node.details?.body ||
        node.label ||
        "this message"
      return `What is important about this message: ${body}`
    }

    return ""
  },

  renderActionLink(href, label) {
    return `<a class="btn btn-xs btn-outline" href="${this.escapeAttribute(href)}">${this.escapeHtml(label)}</a>`
  },

  renderActionButton(action, label) {
    return `<button type="button" class="btn btn-xs btn-outline" data-threadr-graph-action="${this.escapeAttribute(action)}">${this.escapeHtml(label)}</button>`
  },

  escapeAttribute(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("\"", "&quot;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
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

  renderTopRelationshipsSection(node, items) {
    if (!Array.isArray(items) || items.length === 0) return ""

    const focalId = node?.details?.id ? String(node.details.id) : null
    const rows = items
      .map((item) => {
        const fromId = item.from_actor_id ? String(item.from_actor_id) : null
        const toId = item.to_actor_id ? String(item.to_actor_id) : null
        const targetId = focalId && focalId === fromId ? toId : fromId
        const targetHandle =
          focalId && focalId === fromId ? item.to_actor_handle || "unknown" : item.from_actor_handle || "unknown"

        const links = []
        if (targetId) {
          links.push(this.renderActionLink(this.dossierHref("actor", targetId), "Actor dossier"))
        }
        if (item.source_message_id) {
          links.push(this.renderActionLink(this.dossierHref("message", item.source_message_id), "Source message"))
        }

        return `
          <li class="space-y-1">
            <div>${this.escapeHtml(item.relationship_type || "unknown")} ${this.escapeHtml(item.from_actor_handle || "unknown")} → ${this.escapeHtml(item.to_actor_handle || "unknown")} (${this.escapeHtml(String(item.weight || 0))})</div>
            <div class="flex flex-wrap gap-1">
              ${targetId ? this.renderActionLink(this.qaHref(`What does ${targetHandle} know?`), "Ask in QA") : ""}
              ${links.join("")}
            </div>
          </li>
        `
      })
      .join("")

    return `
      <div class="mt-2">
        <div class="font-semibold mb-1">Top relationships</div>
        <ul class="list-disc pl-4 space-y-2">${rows}</ul>
      </div>
    `
  },

  renderTopChannelsSection(items) {
    if (!Array.isArray(items) || items.length === 0) return ""

    const rows = items
      .map((item) => {
        const channelName = item.channel_name || "unknown"
        return `
          <li class="space-y-1">
            <div>${this.escapeHtml(channelName)} (${this.escapeHtml(String(item.message_count || 0))})</div>
            <div class="flex flex-wrap gap-1">
              ${item.channel_id ? this.renderActionLink(this.dossierHref("channel", item.channel_id), "Channel dossier") : ""}
              ${this.renderActionLink(this.qaHref(`What happened in ${channelName}?`), "Ask in QA")}
            </div>
          </li>
        `
      })
      .join("")

    return `
      <div class="mt-2">
        <div class="font-semibold mb-1">Top channels</div>
        <ul class="list-disc pl-4 space-y-2">${rows}</ul>
      </div>
    `
  },

  renderTopActorsSection(items) {
    if (!Array.isArray(items) || items.length === 0) return ""

    const rows = items
      .map((item) => {
        const handle = item.actor_handle || item.actor_display_name || "unknown"
        return `
          <li class="space-y-1">
            <div>${this.escapeHtml(item.actor_display_name || handle)} (${this.escapeHtml(String(item.message_count || 0))})</div>
            <div class="flex flex-wrap gap-1">
              ${item.actor_id ? this.renderActionLink(this.dossierHref("actor", item.actor_id), "Actor dossier") : ""}
              ${this.renderActionLink(this.qaHref(`What does ${handle} know?`), "Ask in QA")}
            </div>
          </li>
        `
      })
      .join("")

    return `
      <div class="mt-2">
        <div class="font-semibold mb-1">Top actors</div>
        <ul class="list-disc pl-4 space-y-2">${rows}</ul>
      </div>
    `
  },

  renderRecentMessagesSection(items) {
    if (!Array.isArray(items) || items.length === 0) return ""

    const rows = items
      .map((item) => {
        const summary = `${item.actor_handle || item.channel_name || "message"} · ${(item.body || "").slice(0, 72) || "message"}`
        return `
          <li class="space-y-1">
            <div>${this.escapeHtml(summary)}</div>
            <div class="flex flex-wrap gap-1">
              ${item.id ? this.renderActionLink(this.dossierHref("message", item.id), "Message dossier") : ""}
              ${this.renderActionLink(this.qaHref(`What is important about this message: ${item.body || "message"}`), "Ask in QA")}
            </div>
          </li>
        `
      })
      .join("")

    return `
      <div class="mt-2">
        <div class="font-semibold mb-1">Recent messages</div>
        <ul class="list-disc pl-4 space-y-2">${rows}</ul>
      </div>
    `
  },
}
