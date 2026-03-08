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
      nodeKinds: JSON.parse(rootEl.dataset.initialNodeKinds || "{}"),
      relationshipTypes: JSON.parse(rootEl.dataset.initialRelationshipTypes || "{}"),
      defaultEdgeLayers: JSON.parse(rootEl.dataset.initialEdgeLayers || "{}"),
      defaultNodeKinds: JSON.parse(rootEl.dataset.initialNodeKinds || "{}"),
      defaultRelationshipTypes: JSON.parse(rootEl.dataset.initialRelationshipTypes || "{}"),
      labelMode: "on",
      defaultLabelMode: "on",
      subjectName: rootEl.dataset.subjectName || "",
      since: rootEl.dataset.since || "",
      until: rootEl.dataset.until || "",
      compareSince: rootEl.dataset.compareSince || "",
      compareUntil: rootEl.dataset.compareUntil || "",
      requestedFocusNodeId: rootEl.dataset.focusNodeId || null,
      requestedFocusNodeKind: rootEl.dataset.focusNodeKind || null,
      requestedFocusApplied: false,
      focusNeighborhoodOnly: Boolean(rootEl.dataset.focusNodeId),
      conversationFocusOnly: false,
      messageFocusOnly: false,
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

  setNodeKinds(nodeKinds) {
    this.state.nodeKinds = {...this.state.nodeKinds, ...(nodeKinds || {})}
    this.renderGraph()
  }

  setRelationshipTypes(relationshipTypes) {
    this.state.relationshipTypes = {...this.state.relationshipTypes, ...(relationshipTypes || {})}
    this.renderGraph()
  }

  setWindow({since, until, compareSince, compareUntil}) {
    const nextSince = since || ""
    const nextUntil = until || ""
    const nextCompareSince = compareSince || ""
    const nextCompareUntil = compareUntil || ""
    if (
      this.state.since === nextSince &&
      this.state.until === nextUntil &&
      this.state.compareSince === nextCompareSince &&
      this.state.compareUntil === nextCompareUntil
    ) {
      return
    }

    this.state.since = nextSince
    this.state.until = nextUntil
    this.state.compareSince = nextCompareSince
    this.state.compareUntil = nextCompareUntil
    this.reconnectChannel()
  }

  setupDom() {
    this.rootEl.classList.add("relative")

    this.canvasEl = document.createElement("div")
    this.canvasEl.className = "absolute inset-0"

    this.hudEl = document.createElement("div")
    this.hudEl.className = "absolute left-4 top-4 flex items-start gap-2"
    this.resetButtonEl = document.createElement("button")
    this.resetButtonEl.type = "button"
    this.resetButtonEl.className = "btn btn-xs btn-outline bg-base-100/90 shadow-sm backdrop-blur"
    this.resetButtonEl.textContent = "Reset view"
    this.resetButtonEl.addEventListener("click", () => this.resetView())
    this.labelToggleButtonEl = document.createElement("button")
    this.labelToggleButtonEl.type = "button"
    this.labelToggleButtonEl.className = "btn btn-xs bg-base-100/90 shadow-sm backdrop-blur"
    this.labelToggleButtonEl.addEventListener("click", () => this.toggleLabelMode())
    this.legendButtonEl = document.createElement("button")
    this.legendButtonEl.type = "button"
    this.legendButtonEl.className = "btn btn-xs btn-outline bg-base-100/90 shadow-sm backdrop-blur"
    this.legendButtonEl.textContent = "Legend"
    this.legendButtonEl.addEventListener("click", () => this.toggleLegendPanel())
    this.hudEl.replaceChildren(this.resetButtonEl, this.labelToggleButtonEl, this.legendButtonEl)

    this.legendPanelEl = document.createElement("div")
    this.legendPanelEl.className =
      "absolute left-4 top-14 hidden w-64 rounded-box border border-base-300 bg-base-100/95 p-3 text-xs shadow-xl backdrop-blur"
    this.legendPanelEl.innerHTML = `
      <div class="mb-2 font-semibold text-base-content">Legend</div>
      <div class="space-y-3 text-base-content/75">
        <div class="space-y-1">
          <div class="font-medium text-base-content">Nodes</div>
          <div class="flex items-center gap-2"><span class="h-3 w-3 rounded-full bg-amber-400 ring-1 ring-white/70"></span><span>Actor</span></div>
          <div class="flex items-center gap-2"><span class="h-3 w-3 rounded-full bg-sky-400 ring-1 ring-white/70"></span><span>Channel</span></div>
          <div class="flex items-center gap-2"><span class="h-3 w-3 rounded-full bg-slate-200 ring-1 ring-white/70"></span><span>Conversation</span></div>
          <div class="flex items-center gap-2"><span class="h-3 w-3 rounded-full bg-emerald-500 ring-1 ring-white/70"></span><span>Message</span></div>
        </div>
        <div class="space-y-1">
          <div class="font-medium text-base-content">Edges</div>
          <div class="flex items-center gap-2"><span class="h-0.5 w-5 rounded bg-slate-200"></span><span>Conversation link</span></div>
          <div class="flex items-center gap-2"><span class="h-0.5 w-5 rounded bg-red-400"></span><span>MENTIONED</span></div>
          <div class="flex items-center gap-2"><span class="h-0.5 w-5 rounded bg-amber-300"></span><span>CO_MENTIONED</span></div>
          <div class="flex items-center gap-2"><span class="h-0.5 w-5 rounded bg-fuchsia-400"></span><span>Other relationship</span></div>
        </div>
      </div>
    `

    const externalDetailsEl = document.getElementById(this.rootEl.dataset.detailsPanelId || "")
    this.state.detailsEl = externalDetailsEl || document.createElement("div")
    if (!externalDetailsEl) {
      this.state.detailsEl.className =
        "absolute bottom-4 right-4 max-h-[70vh] w-[24rem] max-w-[calc(100%-2rem)] overflow-y-auto rounded-box bg-base-100/90 p-3 text-xs shadow-sm backdrop-blur"
    }

    this.state.detailsEl.addEventListener("click", (event) => {
      const button = event.target.closest("[data-threadr-graph-action]")
      if (!button) return

      const action = button.dataset.threadrGraphAction
      if (action === "show-focus-messages") {
        event.preventDefault()
        this.showMessagesForFocus()
      } else if (action === "toggle-pin-focus") {
        event.preventDefault()
        this.togglePinFocus()
      } else if (action === "toggle-focus-neighborhood") {
        event.preventDefault()
        this.toggleFocusNeighborhood()
      }
    })

    if (externalDetailsEl) {
      this.rootEl.replaceChildren(this.canvasEl, this.hudEl, this.legendPanelEl)
    } else {
      this.rootEl.replaceChildren(this.canvasEl, this.hudEl, this.legendPanelEl, this.state.detailsEl)
    }
    this.updateSelectionDetails(null)
    this.updateLabelToggleButton()
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
    this.state.channel?.leave()
    this.state.socket = new Socket("/socket", {
      params: {token: this.rootEl.dataset.socketToken},
    })
    this.state.socket.connect()

    this.state.channel = this.state.socket.channel(this.rootEl.dataset.topic, {
      since: this.state.since,
      until: this.state.until,
    })
    this.state.channel.on("snapshot_meta", () => {})
    this.state.channel.on("snapshot", (payload) => this.handleSnapshot(payload))
    this.state.channel.on("snapshot_error", () => {})

    this.state.channel
      .join()
      .receive("ok", () => {})
      .receive("error", () => {})
  }

  reconnectChannel() {
    this.state.channel?.leave()
    this.state.socket?.disconnect()
    this.connectChannel()
  }

  resetView() {
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
    this.state.relationshipTypes = {...this.state.defaultRelationshipTypes}
    this.state.labelMode = this.state.defaultLabelMode
    this.state.viewState = this.initialViewState()
    this.updateSelectionDetails(null)
    this.updateLabelToggleButton()
    this.renderGraph()
  }

  toggleLabelMode() {
    this.state.labelMode = this.state.labelMode === "off" ? "on" : "off"
    this.updateLabelToggleButton()
    this.renderGraph()
  }

  updateLabelToggleButton() {
    if (!this.labelToggleButtonEl) return
    this.labelToggleButtonEl.textContent = "Labels"
    this.labelToggleButtonEl.classList.toggle("btn-outline", this.state.labelMode !== "on")
    this.labelToggleButtonEl.classList.toggle("btn-primary", this.state.labelMode === "on")
  }

  toggleLegendPanel() {
    if (!this.legendPanelEl) return
    this.legendPanelEl.classList.toggle("hidden")
  }
}

Object.assign(
  ThreadrGraphRenderer.prototype,
  threadrGraphLayoutClusterMethods,
  threadrGraphLifecycleStreamMethods,
  threadrGraphRenderingGraphMethods,
  threadrGraphRenderingSelectionMethods,
)
