// A clickable patch of an Omabar widget.
//
// The bar lays a MouseArea over every widget (for dragging widgets around),
// so a widget's own TapHandler or MouseArea never sees a click. Instead the
// bar hit-tests the click targets widgets register with it and calls
// triggerPress(button) on the one under the pointer, as Omarchy's own
// WidgetButton does. While a button is held on it, the bar sets heldButtons.
import QtQuick

Item {
  id: target

  property var bar: null
  // Which buttons this target answers; others fall through to the bar.
  property int acceptedButtons: Qt.LeftButton
  property int heldButtons: Qt.NoButton
  readonly property bool held: (heldButtons & acceptedButtons) !== 0
  // The bar skips a target whose pressable is false.
  property bool pressable: enabled && visible

  signal pressed(int button)

  function triggerPress(button) {
    if (bar && typeof bar.hideTooltip === "function") bar.hideTooltip(target)
    if (button & acceptedButtons) pressed(button)
  }

  property var registeredBar: null
  function register() {
    if (registeredBar && typeof registeredBar.unregisterClickTarget === "function") registeredBar.unregisterClickTarget(target)
    registeredBar = bar
    if (registeredBar && typeof registeredBar.registerClickTarget === "function") registeredBar.registerClickTarget(target)
  }
  onBarChanged: register()
  Component.onCompleted: register()
  Component.onDestruction: if (registeredBar && typeof registeredBar.unregisterClickTarget === "function") registeredBar.unregisterClickTarget(target)
}
