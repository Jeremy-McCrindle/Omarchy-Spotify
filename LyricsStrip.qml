import QtQuick
import qs.Commons
import qs.Ui

import "Api.js" as Api

// Two fixed rows: the line being sung and the one after it. Stepping with
// the wheel or the keyboard enters browse mode, which lets go and follows
// playback again after a quiet interval or on the next track.
Item {
  id: root

  property var service: null
  property color foreground: Color.foreground
  property color muted: Color.muted
  property string fontFamily: Style.font.family
  property bool hasCursor: false
  property int browseIndex: -1

  readonly property bool browsing: browseIndex >= 0
  readonly property var texts: Api.lyricTexts(service ? service.lyrics : null)
  readonly property bool ready: !!service && service.lyricsState === "ready"
    && texts.length > 0
  readonly property int followIndex: service ? service.activeLyricIndex : -1
  readonly property int shownIndex: browsing ? browseIndex : followIndex
  readonly property string currentText: ready
    ? Api.lyricTextAt(texts, shownIndex)
    : Api.lyricsStatusText(service ? service.lyricsState : "idle",
      service ? service.lyricsMessage : "")
  readonly property string nextText: ready
    ? Api.lyricTextAt(texts, Api.nextLyricIndex(texts, shownIndex)) : ""
  readonly property real lineHeight: Style.space(18)
  readonly property real nextLineHeight: Style.space(16)

  signal hovered(bool on)

  implicitHeight: lineHeight + nextLineHeight + Style.space(4)
  height: implicitHeight

  function stepLine(delta) {
    if (!ready) return
    var from = shownIndex < 0 ? 0 : shownIndex
    var step = delta < 0 ? -1 : 1
    browseIndex = Math.max(0, Math.min(texts.length - 1, from + step))
    resumeTimer.restart()
  }

  function resumeFollowing() {
    resumeTimer.stop()
    browseIndex = -1
  }

  // A shorter set of lyrics can strand browseIndex past the end.
  onTextsChanged: if (browsing && browseIndex >= texts.length) resumeFollowing()

  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onLyricsSongKeyChanged() { root.resumeFollowing() }
  }

  Timer {
    id: resumeTimer
    interval: Api.LYRICS_BROWSE_RESUME_MS
    repeat: false
    onTriggered: root.resumeFollowing()
  }

  CursorSurface {
    anchors.fill: parent
    hasCursor: root.hasCursor
    foreground: root.foreground

    HoverHandler {
      onHoveredChanged: root.hovered(hovered)
    }

    WheelHandler {
      acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
      onWheel: function(event) {
        var delta = event.angleDelta.y || event.pixelDelta.y
        if (!delta || !root.ready) {
          event.accepted = false
          return
        }
        root.stepLine(delta > 0 ? -1 : 1)
        event.accepted = true
      }
    }

    Column {
      anchors.fill: parent
      anchors.leftMargin: Style.space(3)
      anchors.rightMargin: Style.space(3)
      anchors.topMargin: Style.space(2)
      spacing: 0

      Text {
        objectName: "lyrics-current-line"
        width: parent.width
        height: root.lineHeight
        text: root.currentText
        color: root.ready ? root.foreground : root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: root.ready
        elide: Text.ElideRight
        maximumLineCount: 1
        verticalAlignment: Text.AlignVCenter
      }

      Text {
        objectName: "lyrics-next-line"
        width: parent.width
        height: root.nextLineHeight
        text: root.nextText
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        maximumLineCount: 1
        verticalAlignment: Text.AlignVCenter
      }
    }
  }
}
