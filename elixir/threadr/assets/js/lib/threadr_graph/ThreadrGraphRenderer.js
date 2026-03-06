import {Socket} from "phoenix"

import {ThreadrGraphWasmEngine} from "../../wasm/threadr_graph_exec_runtime"
import {threadrGraphLayoutClusterMethods} from "./layout_cluster_methods"
import {threadrGraphLifecycleStreamMethods} from "./lifecycle_stream_methods"
import {threadrGraphRenderingGraphMethods} from "./rendering_graph_methods"
import {threadrGraphRenderingSelectionMethods} from "./rendering_selection_methods"

export default class ThreadrGraphRenderer {
  constructor(rootEl) {
    this.rootEl = rootEl
    this.state = {
      filters: JSON.parse(rootEl.dataset.initialFilters || "{}"),
      filterLabels: JSON.parse(rootEl.dataset.filterLabels || "{}"),
      graph: null,
      deck: null,
      channel: null,
      socket: null,
      summaryEl: null,
      focusEl: null,
      focusStatusEl: null,
      focusButtonEl: null,
      detailsEl: null,
      wasmEngine: null,
      wasmReady: false,
      selectedNodeIndex: null,
      selectedNode: null,
      selectedNodeDetail: null,
      pinnedNodeId: null,
      pinnedNodeKind: null,
      pinnedNodeLabel: null,
      pinnedNodeDetail: null,
      detailCache: {},
      zoomTier: "local",
      zoomMode: rootEl.dataset.initialZoomMode || "auto",
      edgeLayers: JSON.parse(rootEl.dataset.initialEdgeLayers || "{}"),
    }
  }

  mount() {
    this.setupDom()
    this.initWasm()
    this.connectChannel()
  }

  destroy() {
    this.state.channel?.leave()
    this.state.socket?.disconnect()
    this.state.deck?.finalize()
  }

  setFilters(filters) {
    this.state.filters = {...this.state.filters, ...(filters || {})}
    this.renderGraph()
  }

  setEdgeLayers(layers) {
    this.state.edgeLayers = {...this.state.edgeLayers, ...(layers || {})}
    this.renderGraph()
  }

  setupDom() {
    this.rootEl.classList.add("relative")

    this.canvasEl = document.createElement("div")
    this.canvasEl.className = "absolute inset-0"

    this.state.summaryEl = document.createElement("div")
    this.state.summaryEl.className =
      "absolute left-4 top-4 rounded-box bg-base-100/85 px-3 py-2 text-xs shadow-sm backdrop-blur"
    this.state.focusEl = document.createElement("div")
    this.state.focusEl.className =
      "absolute right-4 top-4 rounded-box bg-base-100/88 px-3 py-2 text-xs shadow-sm backdrop-blur"
    this.state.focusStatusEl = document.createElement("div")
    this.state.focusStatusEl.className = "mb-2 font-medium"
    this.state.focusButtonEl = document.createElement("button")
    this.state.focusButtonEl.type = "button"
    this.state.focusButtonEl.className = "btn btn-xs btn-accent"
    this.state.focusButtonEl.addEventListener("click", () => this.togglePinFocus())
    this.state.focusEl.replaceChildren(this.state.focusStatusEl, this.state.focusButtonEl)
    this.state.detailsEl = document.createElement("div")
    this.state.detailsEl.className =
      "absolute bottom-4 right-4 max-w-sm rounded-box bg-base-100/90 p-3 text-xs shadow-sm backdrop-blur"

    this.rootEl.replaceChildren(this.canvasEl, this.state.summaryEl, this.state.focusEl, this.state.detailsEl)
    this.updateSummary("Connecting graph stream...")
    this.updateSelectionDetails(null)
    this.updateFocusControls()
  }

  initWasm() {
    ThreadrGraphWasmEngine.init()
      .then((engine) => {
        this.state.wasmEngine = engine
        this.state.wasmReady = true
      })
      .catch(() => {
        this.state.wasmReady = false
      })
  }

  connectChannel() {
    this.state.socket = new Socket("/socket", {
      params: {token: this.rootEl.dataset.socketToken},
    })
    this.state.socket.connect()

    this.state.channel = this.state.socket.channel(this.rootEl.dataset.topic, {})
    this.state.channel.on("snapshot_meta", (payload) => {
      this.updateSummary(
        `revision=${payload.revision} nodes=${payload.node_count} edges=${payload.edge_count}`,
      )
    })
    this.state.channel.on("snapshot", (payload) => this.handleSnapshot(payload))
    this.state.channel.on("snapshot_error", () => {
      this.updateSummary("Graph snapshot unavailable")
    })

    this.state.channel
      .join()
      .receive("ok", () => this.updateSummary("Waiting for graph snapshot..."))
      .receive("error", () => this.updateSummary("Unauthorized graph stream"))
  }
}

Object.assign(
  ThreadrGraphRenderer.prototype,
  threadrGraphLayoutClusterMethods,
  threadrGraphLifecycleStreamMethods,
  threadrGraphRenderingGraphMethods,
  threadrGraphRenderingSelectionMethods,
)
