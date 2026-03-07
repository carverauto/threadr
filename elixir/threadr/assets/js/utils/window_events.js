import topbar from "../../vendor/topbar"

export function registerTopbar() {
  topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
  window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300))
  window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide())
}

export function registerLiveReloadHelpers() {
  if (process.env.NODE_ENV !== "development") return

  window.addEventListener("phx:live_reload:attached", ({detail: reloader}) => {
    reloader.enableServerLogs()

    let keyDown
    window.addEventListener("keydown", (event) => (keyDown = event.key))
    window.addEventListener("keyup", () => (keyDown = null))
    window.addEventListener(
      "click",
      (event) => {
        if (keyDown === "c") {
          event.preventDefault()
          event.stopImmediatePropagation()
          reloader.openEditorAtCaller(event.target)
        } else if (keyDown === "d") {
          event.preventDefault()
          event.stopImmediatePropagation()
          reloader.openEditorAtDef(event.target)
        }
      },
      true,
    )

    window.liveReloader = reloader
  })
}
