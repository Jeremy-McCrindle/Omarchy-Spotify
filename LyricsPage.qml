import QtQuick
import qs.Commons
import qs.Ui

import "Api.js" as Api

// Every line, the active one in accent. Following keeps the active line in
// the upper third; any manual scroll or key pauses following until the
// resume interval passes or the track changes.
Item {
  id: root

  property var service: null
  property color foreground: Color.foreground
  property color muted: Color.muted
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property bool following: true
  property bool syncing: false

  readonly property var texts: Api.lyricTexts(service ? service.lyrics : null)
  readonly property bool ready: !!service && service.lyricsState === "ready"
    && texts.length > 0
  readonly property int activeIndex: service ? service.activeLyricIndex : -1
  readonly property bool synced: !!service && service.lyricsSynced
  readonly property string statusText: Api.lyricsStatusText(
    service ? service.lyricsState : "idle", service ? service.lyricsMessage : "")

  function pauseFollowing() {
    following = false
    resumeTimer.restart()
  }

  function resumeFollowing() {
    resumeTimer.stop()
    following = true
    syncToActive()
  }

  function syncToActive() {
    if (!following || activeIndex < 0 || activeIndex >= lyricsList.count) return
    syncing = true
    lyricsList.currentIndex = activeIndex
    syncing = false
  }

  function pageBy(direction) {
    pauseFollowing()
    var step = Math.max(0, lyricsList.height - Style.space(20))
    lyricsList.contentY = lyricsWheel.boundedContentY(
      lyricsList.contentY + (direction < 0 ? -step : step))
  }

  function jumpToEdge(toStart) {
    pauseFollowing()
    if (toStart) lyricsList.positionViewAtBeginning()
    else lyricsList.positionViewAtEnd()
  }

  onActiveIndexChanged: syncToActive()
  // A model swap resets currentIndex to 0, which would otherwise read as a
  // manual scroll and pause following every time lyrics arrive mid-track.
  onTextsChanged: {
    syncing = true
    Qt.callLater(function() {
      root.syncing = false
      root.syncToActive()
    })
  }

  Connections {
    target: root.service
    ignoreUnknownSignals: true
    function onLyricsSongKeyChanged() {
      root.resumeFollowing()
      lyricsList.positionViewAtBeginning()
    }
  }

  Timer {
    id: resumeTimer
    interval: Api.LYRICS_BROWSE_RESUME_MS
    repeat: false
    onTriggered: root.resumeFollowing()
  }

  Column {
    anchors.fill: parent
    spacing: Style.space(6)

    Text {
      width: parent.width
      visible: !root.ready
      text: root.statusText
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      wrapMode: Text.WordWrap
    }

    ListView {
      id: lyricsList
      objectName: "page-list"
      width: parent.width
      height: Math.max(Style.space(60),
        parent.height - footerCaption.height - parent.spacing)
      visible: root.ready
      clip: true
      model: root.texts
      spacing: Style.space(2)
      boundsBehavior: Flickable.StopAtBounds
      keyNavigationEnabled: false
      highlightRangeMode: ListView.ApplyRange
      preferredHighlightBegin: height / 3
      preferredHighlightEnd: height / 3 + Style.space(40)
      highlightMoveDuration: 250
      highlightFollowsCurrentItem: true
      highlight: Item {}

      onCurrentIndexChanged: {
        if (root.syncing) return
        if (root.following && currentIndex !== root.activeIndex) root.pauseFollowing()
      }

      delegate: Text {
        required property int index
        required property var modelData
        width: ListView.view.width
        text: String(modelData || "")
        height: text === "" ? Style.space(10) : implicitHeight
        color: index === root.activeIndex ? root.accent
          : (index === ListView.view.currentIndex && !root.following
            ? root.foreground : root.muted)
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: index === root.activeIndex
        wrapMode: Text.WordWrap
      }

      FastScrollHandler {
        id: lyricsWheel
        parent: lyricsList
        flickable: lyricsList
        onScrolled: root.pauseFollowing()
      }
    }

    Text {
      id: footerCaption
      width: parent.width
      text: "Lyrics from LRCLIB"
        + (root.ready && !root.synced ? " · Estimated position" : "")
        + (root.ready && !root.following ? " · Following paused" : "")
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
}
