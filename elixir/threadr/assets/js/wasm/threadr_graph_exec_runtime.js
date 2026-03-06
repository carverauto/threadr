const wasmUrl = "/assets/js/threadr_graph_exec.wasm"

export class ThreadrGraphWasmEngine {
  constructor(instance) {
    this.instance = instance
    this.exports = instance.exports
    this.memory = this.exports.memory
  }

  static async init() {
    const response = await fetch(wasmUrl, {cache: "no-store"})
    let result

    if (WebAssembly.instantiateStreaming) {
      try {
        result = await WebAssembly.instantiateStreaming(response, {})
      } catch (_error) {
        const bytes = await (await fetch(wasmUrl, {cache: "no-store"})).arrayBuffer()
        result = await WebAssembly.instantiate(bytes, {})
      }
    } else {
      const bytes = await response.arrayBuffer()
      result = await WebAssembly.instantiate(bytes, {})
    }

    return new ThreadrGraphWasmEngine(result.instance)
  }

  computeStateMask(states, filters) {
    const len = states.length
    const statesPtr = this.exports.alloc_bytes(len)
    const maskPtr = this.exports.alloc_bytes(len)

    try {
      this.writeBytes(statesPtr, states)
      this.exports.compute_state_mask(
        statesPtr,
        len,
        filters.root_cause ? 1 : 0,
        filters.affected ? 1 : 0,
        filters.healthy ? 1 : 0,
        filters.unknown ? 1 : 0,
        maskPtr,
      )
      return new Uint8Array(this.memory.buffer, maskPtr, len).slice()
    } finally {
      this.exports.free_bytes(statesPtr, len)
      this.exports.free_bytes(maskPtr, len)
    }
  }

  computeThreeHopMask(nodeCount, edgeSource, edgeTarget, startNode) {
    if (nodeCount <= 0) return new Uint8Array(0)
    if (startNode < 0 || startNode >= nodeCount) return new Uint8Array(nodeCount)

    const byteLength = edgeSource.byteLength
    const srcPtr = this.exports.alloc_bytes(byteLength)
    const dstPtr = this.exports.alloc_bytes(byteLength)
    const maskPtr = this.exports.alloc_bytes(nodeCount)

    try {
      this.writeBytes(srcPtr, new Uint8Array(edgeSource.buffer, edgeSource.byteOffset, byteLength))
      this.writeBytes(dstPtr, new Uint8Array(edgeTarget.buffer, edgeTarget.byteOffset, byteLength))
      this.exports.compute_three_hop_mask(
        nodeCount,
        srcPtr,
        dstPtr,
        edgeSource.length,
        startNode,
        maskPtr,
      )
      return new Uint8Array(this.memory.buffer, maskPtr, nodeCount).slice()
    } finally {
      this.exports.free_bytes(srcPtr, byteLength)
      this.exports.free_bytes(dstPtr, byteLength)
      this.exports.free_bytes(maskPtr, nodeCount)
    }
  }

  writeBytes(ptr, bytes) {
    const view = new Uint8Array(this.memory.buffer, ptr, bytes.length)
    view.set(bytes)
  }
}
