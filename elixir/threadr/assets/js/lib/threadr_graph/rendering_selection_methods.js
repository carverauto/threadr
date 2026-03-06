export const threadrGraphRenderingSelectionMethods = {
  updateSummary(text) {
    if (this.state.summaryEl) this.state.summaryEl.textContent = text
  },

  updateSelectionDetails(node = null) {
    if (!this.state.detailsEl) return

    if (!node) {
      this.state.detailsEl.innerHTML =
        "<div class=\"font-semibold\">Selection</div><div>No node selected.</div>"
      return
    }

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
          `

    this.state.detailsEl.innerHTML = `
      <div class="font-semibold mb-1">${this.escapeHtml(node.label || "node")}</div>
      <div>Type: ${kind}</div>
      <div>Platform: ${platform}</div>
      <div>Reference: ${handle}</div>
      <div>Messages: ${this.escapeHtml(String(node.details?.message_count ?? "0"))}</div>
      ${clusterMeta}
      ${neighborhoodMeta}
      ${body}
    `
  },

  handlePick(node) {
    if (!node) return
    this.state.selectedNodeIndex = node.index
    this.state.selectedNode = node
    this.updateSelectionDetails(node)
    this.renderGraph()
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
        <div>Dominant neighbor kind: ${this.escapeHtml(profile.dominant_neighbor_kind || "unknown")}</div>
        <div>Dominant relationship: ${this.escapeHtml(profile.dominant_relationship || "unknown")}</div>
        <div>Relationship types: ${relationshipSummary || "none"}</div>
        <div>Adjacent nodes: ${adjacent || "none"}</div>
      </div>
    `
  },
}
