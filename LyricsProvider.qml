import QtQuick

import "Api.js" as Api

// One lrclib lookup at a time: exact match, then search on 404. Responses
// are matched to the request that issued them by serial, so a superseded or
// aborted request can never publish a result for the song now playing.
Item {
  id: root

  property var xhrFactory: function() { return new XMLHttpRequest() }
  property string clientName: "omarchy-spotify"
  property int timeoutMs: Api.LYRICS_REQUEST_TIMEOUT_MS
  property int cacheLimit: Api.LYRICS_CACHE_LIMIT
  property var cache: ({})
  property var cacheOrder: []
  property int serial: 0
  property var activeXhr: null
  property string activeKey: ""
  property var activeSong: null

  signal loaded(string key, var result)
  signal failed(string key, string message)

  visible: false
  width: 0
  height: 0

  function cached(key) {
    return cache[String(key || "")] || null
  }

  function fetch(song) {
    var key = Api.lyricsCacheKey(song)
    if (!key) return ""
    var hit = cached(key)
    abortActive()
    clearActive()
    if (hit) {
      remember(key, hit)
      Qt.callLater(function() { root.loaded(key, hit) })
      return key
    }
    activeKey = key
    activeSong = song
    startStep("exact", Api.lrclibGetUrl(song))
    return key
  }

  function cancel() {
    abortActive()
    clearActive()
  }

  function abortActive() {
    serial += 1
    timeoutTimer.stop()
    var xhr = activeXhr
    activeXhr = null
    if (!xhr || typeof xhr.abort !== "function") return
    try {
      xhr.abort()
    } catch (error) {
      console.warn("Lyrics request abort failed: " + Api.redact(error))
    }
  }

  function clearActive() {
    serial += 1
    activeKey = ""
    activeSong = null
  }

  function startStep(step, url) {
    var mySerial = serial
    var xhr = null
    try {
      xhr = xhrFactory()
      activeXhr = xhr
      xhr.onreadystatechange = function() {
        if (xhr.readyState !== XMLHttpRequest.DONE) return
        if (mySerial !== root.serial) return
        root.activeXhr = null
        timeoutTimer.stop()
        root.handleResponse(step, Number(xhr.status) || 0,
          Api.parseJson(xhr.responseText, null))
      }
      xhr.open("GET", url)
      xhr.setRequestHeader("Lrclib-Client", clientName)
      xhr.send()
      timeoutTimer.restart()
    } catch (error) {
      activeXhr = null
      finishFailed(Api.lyricsErrorText("request"))
    }
  }

  function handleResponse(step, status, payload) {
    if (status === 404 && step === "exact") {
      startStep("search", Api.lrclibSearchUrl(activeSong))
      return
    }
    if (status === 404) {
      finishLoaded(Api.lyricsFromLrclib(null))
      return
    }
    if (status < 200 || status >= 300) {
      finishFailed(status === 0 ? Api.lyricsErrorText("offline")
        : Api.lyricsErrorText("server", status))
      return
    }
    var row = step === "search" ? Api.pickLrclibCandidate(payload, activeSong) : payload
    finishLoaded(Api.lyricsFromLrclib(row))
  }

  function expireActiveRequest() {
    var key = activeKey
    if (!key) return
    abortActive()
    clearActive()
    failed(key, Api.lyricsErrorText("timeout"))
  }

  function finishLoaded(result) {
    var key = activeKey
    remember(key, result)
    clearActive()
    loaded(key, result)
  }

  function finishFailed(message) {
    var key = activeKey
    clearActive()
    failed(key, message)
  }

  function remember(key, result) {
    var nextCache = Api.shallowCopy(cache)
    nextCache[key] = result
    var nextOrder = cacheOrder.filter(function(k) { return k !== key })
    nextOrder.push(key)
    while (nextOrder.length > cacheLimit) delete nextCache[nextOrder.shift()]
    cache = nextCache
    cacheOrder = nextOrder
  }

  Timer {
    id: timeoutTimer
    interval: root.timeoutMs
    repeat: false
    onTriggered: root.expireActiveRequest()
  }
}
