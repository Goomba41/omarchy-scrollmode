import QtQuick

// Selects the drawn icon for the active pointer kind. The trackball is the
// default while mouse is fully drawn; trackpad/unknown will get their own
// components here later.
Item {
  id: root

  property real size: 16
  property color color: "#d95f5f"
  property string kind: "unknown"
  property bool opened: false
  property bool shadow: false

  implicitWidth: size
  implicitHeight: size

  Loader {
    id: loader
    anchors.fill: parent
    sourceComponent: root.kind === "mouse" ? mouseComponent : trackballComponent
  }

  Component {
    id: trackballComponent
    TrackballBall {
      anchors.fill: parent
      size: root.size
      ballColor: root.color
      spinning: root.opened
      shadow: root.shadow
    }
  }

  Component {
    id: mouseComponent
    MouseGlyph {
      anchors.fill: parent
      size: root.size
      color: root.color
      opened: root.opened
      shadow: root.shadow
    }
  }

  function kick() {
    if (loader.item && loader.item.kick) loader.item.kick()
  }
}
