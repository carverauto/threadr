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
  },

  destroyed() {
    this.renderer?.destroy()
  },
}
