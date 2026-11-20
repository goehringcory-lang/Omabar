// Omabar notifications: a bell, crossed out while Do Not Disturb is on.
// Click: replay recent notifications. Right-click: toggle Do Not Disturb.
//
// It reads Do Not Disturb straight from Omarchy's notification service, so the
// bell changes the moment it is toggled, from here or anywhere else, and
// nothing is polled.
import QtQuick
import qs.Commons
import qs.Ui

Item {
  id: root

  property var bar
  property string moduleName
  property var settings: ({})

  readonly property var service: bar && bar.shell && typeof bar.shell.firstPartyServiceFor === "function"
    ? bar.shell.firstPartyServiceFor("omarchy.notifications") : null
  readonly property bool dnd: !!service && service.doNotDisturb === true

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.dnd ? "\u{F009B}" : "\u{F009A}"
    tooltipText: root.dnd
      ? "Do not disturb is on\nRight-click to turn it off"
      : "Notifications\nClick: show recent · Right-click: do not disturb"
    onPressed: function(pressedButton) {
      if (pressedButton !== Qt.RightButton) {
        if (root.bar) root.bar.run("omarchy-shell -q notifications showHistory")
      } else if (root.service && typeof root.service.setDoNotDisturb === "function") {
        root.service.setDoNotDisturb(!root.service.doNotDisturb)
      } else if (root.bar) {
        root.bar.run("omarchy-shell -q notifications toggleDnd")
      }
    }
  }
}
