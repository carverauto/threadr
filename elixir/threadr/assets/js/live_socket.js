import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/threadr"

import HookModules from "./hooks"

export function buildLiveSocket() {
  const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")

  return new LiveSocket("/live", Socket, {
    longPollFallbackMs: 2500,
    params: {_csrf_token: csrfToken},
    hooks: {...colocatedHooks, ...HookModules},
  })
}
