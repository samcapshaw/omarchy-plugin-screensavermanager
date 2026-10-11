import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar entry for Screensaver Manager: the monitor glyph, and the panel it opens.
// Left click opens the panel, right click starts the screensaver now.
//
// Moving the cursor or the mouse over an installed screensaver, or over one of
// Omarchy's text effects, opens a small live preview beside the panel. All
// state and actions live in Service.qml.
Panel {
  id: root

  readonly property string pluginId: "io.github.whiskeytangofussell.screensavermanager"
  moduleName: pluginId
  ipcTarget: pluginId
  // This panel owns the IPC target so it can add refresh and launch.
  manageIpc: false

  readonly property var service: bar && bar.shell && typeof bar.shell.serviceFor === "function" ? bar.shell.serviceFor(pluginId) : null
  readonly property var state: service ? service.state : ({})
  readonly property var savers: service ? service.savers : []
  readonly property var installedSavers: Model.installed(savers)
  readonly property var missingSavers: Model.missing(savers)
  readonly property var catalogSavers: Model.catalog(savers)
  readonly property var effects: service ? service.effects : []
  readonly property string selected: service ? service.selected : "omarchy"
  readonly property bool screensaverEnabled: service ? service.screensaverEnabled : true

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property color hoverFill: Style.hoverFillFor(fg, Color.accent)
  readonly property color selectedFill: Style.selectedFillFor(fg, Color.accent)

  property bool cursorActive: false
  property string cursorKey: ""
  property bool showMissing: false
  property bool addingCustom: false

  // Both Omarchy screensavers (stock colors and Theme Match) share the effects.
  readonly property bool omarchySelected: Model.isOmarchy(selected)
  readonly property var navKeys: Model.navKeys(installedSavers, catalogSavers, showMissing, omarchySelected ? effects : [])

  function moveCursor(delta) {
    if (!cursorActive) {
      cursorActive = true
      if (cursorKey === "") cursorKey = Model.saverKey(selected)
      return
    }
    cursorKey = Model.step(navKeys, cursorKey, delta)
  }

  function hover(key) {
    cursorActive = true
    cursorKey = key
  }

  function activate(key) {
    var parsed = Model.parseKey(key || cursorKey)
    if (!service) return
    if (parsed.type === "saver") service.select(parsed.id)
    else if (parsed.type === "catalog") {
      var saver = Model.find(savers, parsed.id)
      if (saver && saver.installed) service.uninstall(saver)
      else service.install(saver)
    }
    else if (parsed.type === "more") showMissing = !showMissing
    else if (parsed.type === "effect") service.toggleEffect(parsed.id)
  }

  // ---- preview --------------------------------------------------------------

  readonly property int previewWidth: Style.space(480)
  readonly property int previewHeight: Math.round(previewWidth * 9 / 16)

  // Beside the panel card, on whichever side has room.
  function previewGeometry() {
    var origin = panel.cardOrigin
    var gap = Style.space(12)
    var screenWidth = panel.screen ? panel.screen.width : 0
    var x = origin.x - gap - previewWidth
    if (x < gap && screenWidth > 0) x = origin.x + panel.contentWidth + gap
    var y = origin.y
    if (bar && bar.position === "bottom") y = origin.y + panel.contentHeight - previewHeight
    return {
      monitor: panel.screen ? panel.screen.name : "",
      x: Math.max(0, x),
      y: Math.max(0, y),
      width: previewWidth,
      height: previewHeight
    }
  }

  function showPreview() {
    if (!service || !opened || !cursorActive) return
    var parsed = Model.parseKey(cursorKey)
    if (parsed.type === "saver") service.preview(parsed.id, "", previewGeometry())
    else if (parsed.type === "effect") service.preview(omarchySelected ? selected : "omarchy", parsed.id, previewGeometry())
  }

  onCursorKeyChanged: previewTimer.restart()

  // Long enough that sweeping the mouse down the list does not open a
  // terminal for every row it crosses.
  Timer {
    id: previewTimer
    interval: 350
    onTriggered: root.showPreview()
  }

  // Installs and removals finish in their own terminal, so keep the lists
  // current while the panel is open.
  Timer {
    interval: 3000
    repeat: true
    running: root.opened
    onTriggered: if (root.service) root.service.refresh()
  }

  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      cursorKey = ""
      addingCustom = false
      if (service) service.refresh()
    } else {
      previewTimer.stop()
      if (service) service.stopPreview()
    }
  }

  IpcHandler {
    target: root.pluginId

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { if (root.service) root.service.refresh() }
    function launch(): void { if (root.service) root.service.launchNow() }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // nf-md-monitor_shimmer, the glyph Omarchy uses for its screensaver.
    text: "\u{F1104}"
    opacity: root.screensaverEnabled ? 1.0 : 0.5
    tooltipText: ""
    onPressed: function(b) {
      if (b === Qt.RightButton) {
        if (root.service) root.service.launchNow()
      } else {
        root.toggle()
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: nameField.activeFocus || commandField.activeFocus
      onMoveRequested: function(dx, dy) { root.moveCursor(dy !== 0 ? dy : dx) }
      onActivateRequested: if (root.cursorActive) root.activate()
      onCloseRequested: {
        if (root.addingCustom) root.addingCustom = false
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "s" || t === "S") root.service && root.service.launchNow()
      }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: column.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

        Column {
          id: column
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          // ---------- Hero ----------
          PanelHero {
            id: hero
            width: parent.width
            title: "Screensaver"
            meta: Model.heroMeta(root.state)
            foreground: root.fg
            fontFamily: root.fontFamily
            iconOpacity: root.screensaverEnabled ? 1.0 : 0.5
            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: "\u{F1104}"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
            trailingControl: Component {
              ToggleSwitch {
                id: enabledSwitch
                checked: root.screensaverEnabled
                foreground: root.fg
                onToggled: if (root.service) root.service.toggleScreensaverEnabled()

                PanelToolTip {
                  visible: enabledSwitch.containsMouse
                  text: root.screensaverEnabled ? "Turn the screensaver off" : "Turn the screensaver on"
                  fontFamily: root.fontFamily
                }
              }
            }
          }

          // ---------- Screensavers ----------
          PanelSeparator { foreground: root.fg }

          Column {
            width: parent.width
            spacing: Style.space(4)

            Item {
              width: parent.width
              implicitHeight: saversHeader.implicitHeight

              PanelSectionHeader {
                id: saversHeader
                text: "SCREENSAVER"
                foreground: root.fg
                fontFamily: root.fontFamily
                anchors.left: parent.left
              }

              Text {
                textFormat: Text.PlainText
                text: "\u{F0415} Add command"
                color: addMouse.containsMouse ? root.fg : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: saversHeader.verticalCenter

                MouseArea {
                  id: addMouse
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    root.addingCustom = !root.addingCustom
                    if (root.addingCustom) nameField.forceActiveFocus()
                  }
                }
              }
            }

            Repeater {
              model: root.installedSavers

              SaverRow {
                required property var modelData
                width: column.width
                saver: modelData
              }
            }

            // Add any terminal command as a screensaver.
            Column {
              visible: root.addingCustom
              width: parent.width
              spacing: Style.space(6)
              topPadding: Style.space(6)

              TextField {
                id: nameField
                width: parent.width
                placeholderText: "Name"
                foreground: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                onAccepted: commandField.forceActiveFocus()
              }

              TextField {
                id: commandField
                width: parent.width
                placeholderText: "Command, e.g. cmatrix -ab"
                foreground: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                onAccepted: addButton.submit()
              }

              Row {
                spacing: Style.space(6)
                anchors.right: parent.right

                Button {
                  text: "Cancel"
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  fontSize: Style.font.bodySmall
                  onClicked: root.addingCustom = false
                }

                Button {
                  id: addButton
                  text: "Add"
                  bordered: true
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  fontSize: Style.font.bodySmall
                  enabled: nameField.text.trim() !== "" && commandField.text.trim() !== ""
                  onClicked: submit()

                  function submit() {
                    if (!enabled || !root.service) return
                    root.service.addCustom(nameField.text.trim(), commandField.text.trim())
                    nameField.text = ""
                    commandField.text = ""
                    root.addingCustom = false
                  }
                }
              }
            }

            // The known terminal screensavers, to install or remove.
            CursorSurface {
              visible: root.catalogSavers.length > 0
              width: parent.width
              implicitHeight: moreText.implicitHeight + Style.spacing.lg
              hasCursor: root.cursorActive && root.cursorKey === "more"
              foreground: root.fg
              fill: root.hoverFill

              Text {
                id: moreText
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.leftMargin: Style.space(6)
                anchors.verticalCenter: parent.verticalCenter
                text: (root.showMissing ? "\u{F0140}" : "\u{F0142}") + "  Get more" + (root.missingSavers.length > 0 ? " (" + root.missingSavers.length + " to install)" : "")
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onContainsMouseChanged: if (containsMouse) root.hover("more")
                onClicked: root.activate("more")
              }
            }

            Repeater {
              model: root.showMissing ? root.catalogSavers : []

              CatalogRow {
                required property var modelData
                width: column.width
                saver: modelData
              }
            }
          }

          // ---------- Effects ----------
          PanelSeparator {
            visible: root.omarchySelected
            foreground: root.fg
          }

          Column {
            visible: root.omarchySelected
            width: parent.width
            spacing: Style.space(8)

            Item {
              width: parent.width
              implicitHeight: effectsHeader.implicitHeight

              PanelSectionHeader {
                id: effectsHeader
                text: "EFFECTS  " + Model.enabledCount(root.effects) + "/" + root.effects.length
                foreground: root.fg
                fontFamily: root.fontFamily
                anchors.left: parent.left
              }

              Text {
                textFormat: Text.PlainText
                visible: Model.enabledCount(root.effects) < root.effects.length
                text: "All on"
                color: allMouse.containsMouse ? root.fg : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                anchors.right: parent.right
                anchors.rightMargin: Style.space(6)
                anchors.verticalCenter: effectsHeader.verticalCenter

                MouseArea {
                  id: allMouse
                  anchors.fill: parent
                  anchors.margins: -Style.space(4)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: if (root.service) root.service.allEffects()
                }
              }
            }

            Flow {
              width: parent.width
              spacing: Style.space(4)

              Repeater {
                model: root.effects

                Item {
                  id: chipSlot
                  required property var modelData
                  readonly property string key: Model.effectKey(modelData.name)
                  readonly property bool hasCursor: root.cursorActive && root.cursorKey === key
                  implicitWidth: chip.implicitWidth
                  implicitHeight: chip.implicitHeight

                  Button {
                    id: chip
                    anchors.fill: parent
                    text: chipSlot.modelData.name
                    fontSize: Style.font.caption
                    foreground: root.fg
                    fontFamily: root.fontFamily
                    horizontalPadding: Style.space(7)
                    verticalPadding: Style.space(3)
                    bordered: true
                    active: chipSlot.modelData.enabled
                    opacity: chipSlot.modelData.enabled ? 1.0 : 0.55
                    hasCursor: chipSlot.hasCursor
                    onHovered: function(h) { if (h) root.hover(chipSlot.key) }
                    onClicked: root.activate(chipSlot.key)
                    onRightClicked: if (root.service) root.service.onlyEffect(chipSlot.modelData.name)
                  }

                  // Enabled chips already wear the selected fill, which
                  // outweighs the cursor's hover fill, so the cursor also gets
                  // a ring just outside the chip, as ToggleSwitch does.
                  Rectangle {
                    visible: chipSlot.hasCursor
                    anchors.fill: parent
                    anchors.margins: -Style.space(2)
                    color: "transparent"
                    radius: Style.cornerRadius
                    border.width: Math.max(1, Style.space(1))
                    border.color: root.fg
                  }
                }
              }
            }

            Text {
              textFormat: Text.PlainText
              width: parent.width
              wrapMode: Text.WordWrap
              text: "Click to switch an effect on or off. Right click plays only that one."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // ---------- Timing ----------
          PanelSeparator { foreground: root.fg }

          Column {
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "TIMING"
              foreground: root.fg
              fontFamily: root.fontFamily
            }

            Item {
              width: parent.width
              implicitHeight: timeoutField.implicitHeight

              Text {
                textFormat: Text.PlainText
                text: "Start after idle (seconds)"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              NumberField {
                id: timeoutField
                anchors.right: parent.right
                from: 10
                to: 86400
                stepSize: 30
                value: root.service ? root.service.idleTimeout : 150
                foreground: root.fg
                fontFamily: root.fontFamily
                fontSize: Style.font.bodySmall
                enabled: root.service && !root.service.timingManagedElsewhere
                onModified: function(v) { if (root.service) root.service.setIdleTimeout(v) }
              }
            }

            Text {
              textFormat: Text.PlainText
              visible: root.service && (root.service.timingManagedElsewhere || root.service.idleTimeout >= root.service.lockTimeout)
              width: parent.width
              wrapMode: Text.WordWrap
              text: root.service && root.service.timingManagedElsewhere
                ? "PowerCore sets the idle timings for each power source, so change them there."
                : "The screen locks before this, so the screensaver will not show."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Item {
              width: parent.width
              implicitHeight: mouseSwitch.implicitHeight

              Text {
                textFormat: Text.PlainText
                text: "Dismiss on mouse movement"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              ToggleSwitch {
                id: mouseSwitch
                anchors.right: parent.right
                checked: root.service ? root.service.dismissOnMouse : true
                foreground: root.fg
                onToggled: if (root.service) root.service.setDismissOnMouse(!checked)
              }
            }

            Item {
              visible: root.omarchySelected
              width: parent.width
              implicitHeight: fpsRow.implicitHeight

              Text {
                textFormat: Text.PlainText
                text: "Frame rate"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
              }

              Row {
                id: fpsRow
                anchors.right: parent.right
                spacing: Style.space(4)

                Repeater {
                  model: [30, 60, 120]

                  Button {
                    required property var modelData
                    text: modelData + " fps"
                    fontSize: Style.font.caption
                    foreground: root.fg
                    fontFamily: root.fontFamily
                    horizontalPadding: Style.space(7)
                    verticalPadding: Style.space(3)
                    bordered: true
                    active: root.service && root.service.frameRate === modelData
                    onClicked: if (root.service) root.service.setFrameRate(modelData)
                  }
                }
              }
            }
          }

          // ---------- Footer ----------
          PanelSeparator { foreground: root.fg }

          Item {
            width: parent.width
            implicitHeight: startButton.implicitHeight

            Button {
              id: startButton
              anchors.left: parent.left
              iconText: "\u{F040A}"
              text: "Start now"
              bordered: true
              foreground: root.fg
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              onClicked: {
                if (!root.service) return
                root.close()
                root.service.launchNow()
              }
            }

            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              PanelActionButton {
                id: menuButton
                iconText: "\u{F035C}"
                foreground: root.state.menuInstalled ? root.fg : root.dim
                fontFamily: root.fontFamily
                tooltipText: root.state.menuInstalled ? "Remove from the Omarchy menu" : "Add to the Omarchy menu"
                onClicked: if (root.service) root.service.setMenu(!root.state.menuInstalled)
              }

              PanelActionButton {
                iconText: "\u{F018D}"
                foreground: root.state.cliInstalled ? root.fg : root.dim
                fontFamily: root.fontFamily
                tooltipText: root.state.cliInstalled ? "Remove the screensaver-manager command" : "Install the screensaver-manager command"
                onClicked: if (root.service) root.service.setCliInstalled(!root.state.cliInstalled)
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.service && root.service.lastError !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.service ? root.service.lastError : ""
            color: Color.urgent
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  // An installed screensaver: select on click, preview on hover.
  component SaverRow: CursorSurface {
    id: saverRow
    required property var saver
    readonly property string key: Model.saverKey(saver.id)
    readonly property bool isSelected: saver.id === root.selected

    hasCursor: root.cursorActive && root.cursorKey === key
    current: isSelected
    foreground: root.fg
    fill: root.hoverFill
    currentFill: root.selectedFill
    implicitHeight: saverInner.implicitHeight + Style.spacing.lg

    Row {
      id: saverInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: Model.saverGlyph(saverRow.saver)
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        width: parent.width - Style.space(22) - trailing.width - parent.spacing * 2
        anchors.verticalCenter: parent.verticalCenter

        Text {
          textFormat: Text.PlainText
          text: saverRow.saver.name
          width: parent.width
          elide: Text.ElideRight
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: saverRow.isSelected
        }

        Text {
          textFormat: Text.PlainText
          text: saverRow.saver.description || ""
          visible: text !== ""
          width: parent.width
          elide: Text.ElideRight
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Item {
        id: trailing
        width: Style.space(22)
        height: parent.height

        Text {
          anchors.centerIn: parent
          textFormat: Text.PlainText
          visible: saverRow.isSelected && !(saverRow.saver.kind === "custom" && rowHover.hovered)
          text: "\u{F012C}"
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        PanelActionButton {
          anchors.centerIn: parent
          visible: saverRow.saver.kind === "custom" && rowHover.hovered
          iconText: "\u{F0156}"
          fontSize: Style.font.bodySmall
          foreground: root.dim
          fontFamily: root.fontFamily
          tooltipText: "Remove"
          z: 2
          onClicked: if (root.service) root.service.removeCustom(saverRow.saver.id)
        }
      }
    }

    HoverHandler { id: rowHover }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) root.hover(saverRow.key)
      onClicked: root.activate(saverRow.key)
      z: -1
    }
  }

  // A known terminal screensaver, installed or not. The download and delete
  // buttons each open a terminal with the package manager command, where the
  // user confirms (or cancels) it themselves; nothing is installed or removed
  // from here directly.
  component CatalogRow: CursorSurface {
    id: catalogRow
    required property var saver
    readonly property string key: Model.catalogKey(saver.id)
    readonly property bool isInstalled: saver.installed === true
    readonly property bool canRemove: isInstalled && !!saver.uninstall

    hasCursor: root.cursorActive && root.cursorKey === key
    foreground: root.fg
    fill: root.hoverFill
    implicitHeight: catalogInner.implicitHeight + Style.spacing.lg

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      onContainsMouseChanged: if (containsMouse) root.hover(catalogRow.key)
    }

    Row {
      id: catalogInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(2)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: Model.saverGlyph(catalogRow.saver)
        color: catalogRow.isInstalled ? root.fg : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        width: parent.width - Style.space(22) - catalogActions.width - parent.spacing * 2
        anchors.verticalCenter: parent.verticalCenter

        Text {
          textFormat: Text.PlainText
          text: catalogRow.saver.name + "  ·  " + catalogRow.saver.description
          width: parent.width
          elide: Text.ElideRight
          color: root.fg
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          textFormat: Text.PlainText
          text: catalogRow.isInstalled
            ? "Installed" + (catalogRow.saver.owner ? " · " + catalogRow.saver.owner : " · not from a package")
            : catalogRow.saver.install + (catalogRow.saver.repo === "aur" ? "  (AUR)" : "")
          width: parent.width
          elide: Text.ElideRight
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Row {
        id: catalogActions
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        PanelActionButton {
          iconText: "\u{F01DA}"
          fontSize: Style.font.body
          foreground: root.fg
          fontFamily: root.fontFamily
          enabled: !catalogRow.isInstalled
          opacity: enabled ? 1.0 : 0.3
          tooltipText: "Install " + catalogRow.saver.name
          onHovered: function(h) { if (h) root.hover(catalogRow.key) }
          onClicked: if (root.service) root.service.install(catalogRow.saver)
        }

        PanelActionButton {
          iconText: "\u{F0A7A}"
          fontSize: Style.font.body
          foreground: root.fg
          fontFamily: root.fontFamily
          enabled: catalogRow.canRemove
          opacity: enabled ? 1.0 : 0.3
          tooltipText: catalogRow.isInstalled && !catalogRow.canRemove
            ? "Not installed from a package, remove it by hand"
            : "Remove " + catalogRow.saver.name
          onHovered: function(h) { if (h) root.hover(catalogRow.key) }
          onClicked: if (root.service) root.service.uninstall(catalogRow.saver)
        }
      }
    }
  }
}
