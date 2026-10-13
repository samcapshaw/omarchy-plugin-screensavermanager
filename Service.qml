import QtQuick
import Quickshell
import Quickshell.Io

// Headless half of Screensaver Manager. It owns the plugin's state (read from
// bin/screensaver-manager, which owns the config file), runs the panel's
// actions, and takes over the idle launch when the setup is not the stock one.
//
// Taking over the idle launch: Omarchy's idle service flips
// `screensaverStartedThisCycle` to true and only then starts its own launcher.
// The change signal reaches us first, and our launcher carries the Omarchy
// screensaver class in its arguments from its first instant, so the stock
// launcher's "already running" check sees it and steps aside. The windows we
// open use that same class, so the idle service still tracks them: the lock
// still follows, and dismissing the screensaver still counts as activity.
Item {
  id: root

  // Injected by omarchy-shell.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "io.github.whiskeytangofussell.screensavermanager"
  readonly property string cli: {
    var url = Qt.resolvedUrl("bin/screensaver-manager").toString()
    return decodeURIComponent(url.replace(/^file:\/\//, ""))
  }
  readonly property string home: Quickshell.env("HOME")
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")
  readonly property string configPath: configHome + "/omarchy/screensaver-manager.json"

  // Everything `screensaver-manager status --json` reports.
  property var state: ({})
  property bool loaded: false
  readonly property var savers: state.savers || []
  readonly property var effects: state.effects || []
  readonly property string selected: state.selected || "omarchy"
  readonly property bool managed: state.managed === true
  readonly property bool screensaverEnabled: state.screensaverEnabled !== false
  readonly property int frameRate: state.frameRate || 120
  readonly property bool dismissOnMouse: state.dismissOnMouse !== false

  readonly property var idleService: shell && typeof shell.serviceFor === "function" ? shell.serviceFor("omarchy.idle") : null
  readonly property int idleTimeout: idleService ? idleService.screensaverTimeoutSeconds : 150
  readonly property int lockTimeout: idleService ? idleService.lockTimeoutSeconds : 300
  // PowerCore rewrites the idle timings per power source, so a timeout set
  // here would not stick while it is on.
  readonly property bool timingManagedElsewhere: !!(shell && typeof shell.serviceFor === "function" && shell.serviceFor("gdeyoung.powercore"))

  property string lastError: ""

  function refresh() {
    if (statusProc.running) {
      statusProc.again = true
      return
    }
    statusProc.running = true
  }

  // ---- actions --------------------------------------------------------------

  property var queue: []

  function run(args) {
    var next = root.queue.slice()
    next.push([root.cli].concat(args))
    root.queue = next
    pump()
  }

  function pump() {
    if (actionProc.running || root.queue.length === 0) return
    var next = root.queue.slice()
    actionProc.command = next.shift()
    root.queue = next
    actionProc.running = true
  }

  function select(id) { run(["select", id]) }
  function setEffect(name, on) { run(["effects", on ? "on" : "off", name]) }
  function toggleEffect(name) { run(["effects", "toggle", name]) }
  function allEffects() { run(["effects", "all"]) }
  function onlyEffect(name) { run(["effects", "only", name]) }
  function setFrameRate(fps) { run(["framerate", String(Math.round(fps))]) }
  function setDismissOnMouse(on) { run(["mouse", on ? "on" : "off"]) }
  function addCustom(name, command) { run(["custom", "add", name, command]) }
  function removeCustom(id) { run(["custom", "remove", id]) }
  function setMenu(on) { run(["menu", on ? "install" : "remove"]) }
  function setCliInstalled(on) { run(["cli", on ? "install" : "remove"]) }
  function launchNow() { Quickshell.execDetached([root.cli, "launch"]) }

  function toggleScreensaverEnabled() {
    run(["toggle-enabled"])
  }

  // Installing is always the user's call: this opens a terminal with the
  // package manager command, where they confirm (or not) themselves.
  function install(saver) {
    if (!saver || !saver.install) return
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", saver.install])
  }

  // Removal works the same way: the user sees pacman's list of what goes and
  // confirms it in the terminal.
  function uninstall(saver) {
    if (!saver || !saver.uninstall) return
    Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", saver.uninstall])
  }

  function setIdleTimeout(seconds) {
    if (!shell || typeof shell.mutateShellConfig !== "function") return
    var value = Math.max(10, Math.round(seconds))
    shell.mutateShellConfig(function(config) {
      if (!config.idle || typeof config.idle !== "object") config.idle = {}
      config.idle.screensaver = value
    })
  }

  // ---- previews -------------------------------------------------------------

  property string previewKey: ""

  function preview(id, effect, geometry) {
    var key = id + "|" + (effect || "")
    if (key === root.previewKey) return
    root.previewKey = key
    var args = [root.cli, "preview", id]
    if (effect) args.push("--effect", effect)
    if (geometry) {
      if (geometry.monitor) args.push("--monitor", String(geometry.monitor))
      args.push("--x", String(Math.round(geometry.x)), "--y", String(Math.round(geometry.y)),
                "--width", String(Math.round(geometry.width)), "--height", String(Math.round(geometry.height)))
    }
    Quickshell.execDetached(args)
  }

  function stopPreview() {
    if (root.previewKey === "") return
    root.previewKey = ""
    Quickshell.execDetached([root.cli, "preview", "stop"])
  }

  // ---- idle takeover --------------------------------------------------------

  Connections {
    target: root.idleService
    ignoreUnknownSignals: true
    function onScreensaverStartedThisCycleChanged() {
      if (root.idleService.screensaverCommandManaged === true) return
      if (!root.idleService.screensaverStartedThisCycle) return
      if (!root.managed || idleProc.running) return
      idleProc.running = true
    }
  }

  // Quickshell's IdleMonitor keeps the timeout it was armed with: changing
  // `timeout` later does nothing until the monitor is disabled and enabled
  // again. Omarchy's idle service only updates the timeout, so a new idle
  // timing (from this panel, PowerCore or a hand edit of shell.json) would
  // not take effect until the shell restarts. Flipping stay-awake on and off
  // in one turn, without persisting it, re-arms the monitor with the new
  // timeout. Left alone while stay-awake is really on.
  function rearmIdle() {
    var idle = root.idleService
    if (!idle || idle.stayAwake || typeof idle.applyStayAwake !== "function") return
    idle.applyStayAwake(true, false, "screensaver-manager re-arm")
    idle.applyStayAwake(false, false, "screensaver-manager re-arm")
  }

  Connections {
    target: root.idleService
    ignoreUnknownSignals: true
    function onFirstIdleTimeoutSecondsChanged() { Qt.callLater(root.rearmIdle) }
  }

  Process {
    id: idleProc
    command: [root.cli, "idle-launch", "--marker=org.omarchy.screensaver"]
  }

  // ---- plumbing -------------------------------------------------------------

  Process {
    id: statusProc
    property bool again: false
    command: [root.cli, "status", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          root.state = JSON.parse(text)
          root.loaded = true
        } catch (e) {
          console.warn("screensaver-manager: unreadable status:", e)
        }
      }
    }
    onExited: if (again) {
      again = false
      running = true
    }
  }

  Process {
    id: actionProc
    // The service refreshes itself after each action; no need for the CLI
    // to call back over IPC.
    environment: ({ SSM_FROM_PANEL: "1" })
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.lastError = text.trim()
    }
    onExited: {
      root.refresh()
      root.pump()
    }
  }

  // Changes made from the CLI also nudge the panel over IPC, since the CLI
  // replaces the file rather than writing into it.
  FileView {
    path: root.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: root.refresh()
  }

  Component.onCompleted: refresh()
  Component.onDestruction: if (root.previewKey !== "") Quickshell.execDetached([root.cli, "preview", "stop"])
}
