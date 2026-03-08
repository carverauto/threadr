import ThreadrGraphRenderer from "../lib/threadr_graph/ThreadrGraphRenderer"

export const TenantGraphExplorer = {
  mounted() {
    this.renderer = new ThreadrGraphRenderer(this.el)
    this.renderer.mount()

    this.handleEvent("tenant_graph:set_filters", ({filters}) => {
      this.renderer.setFilters(filters)
    })

    this.handleEvent("tenant_graph:set_zoom_mode", ({mode}) => {
      this.renderer.setZoomMode(mode)
    })

    this.handleEvent("tenant_graph:set_edge_layers", ({layers}) => {
      this.renderer.setEdgeLayers(layers)
    })

    this.handleEvent("tenant_graph:set_node_kinds", ({node_kinds: nodeKinds}) => {
      this.renderer.setNodeKinds(nodeKinds)
    })

    this.handleEvent("tenant_graph:set_relationship_types", ({relationship_types: relationshipTypes}) => {
      this.renderer.setRelationshipTypes(relationshipTypes)
    })
  },

  updated() {
    this.renderer?.setWindow({
      since: this.el.dataset.since || "",
      until: this.el.dataset.until || "",
      compareSince: this.el.dataset.compareSince || "",
      compareUntil: this.el.dataset.compareUntil || "",
    })
  },

  destroyed() {
    this.renderer?.destroy()
  },
}
