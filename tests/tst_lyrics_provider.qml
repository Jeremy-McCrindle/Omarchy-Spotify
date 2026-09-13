pragma ComponentBehavior: Bound

import QtQuick
import QtTest

import ".." as Plugin

TestCase {
  id: testCase
  name: "LyricsProvider"

  property var requests: []
  property var loadedEvents: []
  property var failedEvents: []
  property bool failOpen: false

  readonly property var song: ({ id: "spotify:track:1", title: "Song",
    artist: "Artist", album: "Album", duration: 200 })
  readonly property var otherSong: ({ id: "spotify:track:2", title: "Other",
    artist: "Artist", album: "Album", duration: 180 })

  Component {
    id: providerComponent

    Plugin.LyricsProvider {
      xhrFactory: function() { return testCase.newRequest() }
      onLoaded: function(key, result) { testCase.loadedEvents.push({ key: key, result: result }) }
      onFailed: function(key, message) { testCase.failedEvents.push({ key: key, message: message }) }
    }
  }

  function newRequest() {
    var xhr = {
      readyState: XMLHttpRequest.UNSENT,
      status: 0,
      responseText: "",
      url: "",
      headers: ({}),
      aborted: false,
      onreadystatechange: null,
      open: function(method, url) {
        if (testCase.failOpen) throw new Error("open failed")
        this.url = url
        this.readyState = XMLHttpRequest.OPENED
      },
      setRequestHeader: function(name, value) { this.headers[name] = value },
      send: function() {},
      abort: function() { this.aborted = true }
    }
    requests.push(xhr)
    return xhr
  }

  function complete(xhr, status, body) {
    xhr.status = status
    xhr.responseText = body === undefined ? "" : body
    xhr.readyState = XMLHttpRequest.DONE
    xhr.onreadystatechange()
  }

  function makeProvider() {
    var provider = providerComponent.createObject(testCase)
    verify(provider)
    return provider
  }

  function init() {
    requests = []
    loadedEvents = []
    failedEvents = []
    failOpen = false
  }

  function test_exactHitLoadsSyncedLyrics() {
    var provider = makeProvider()
    var key = provider.fetch(song)
    compare(requests.length, 1)
    verify(requests[0].url.indexOf("https://lrclib.net/api/get?") === 0)
    compare(requests[0].headers["Lrclib-Client"], provider.clientName)
    complete(requests[0], 200, JSON.stringify({ syncedLyrics: "[00:01.00] Hi",
      plainLyrics: "Hi" }))
    compare(loadedEvents.length, 1)
    compare(loadedEvents[0].key, key)
    compare(loadedEvents[0].result.state, "ready")
    compare(loadedEvents[0].result.synced.length, 1)
    provider.destroy()
  }

  function test_exact404FallsBackToSearch() {
    var provider = makeProvider()
    provider.fetch(song)
    complete(requests[0], 404, "{}")
    compare(requests.length, 2)
    verify(requests[1].url.indexOf("https://lrclib.net/api/search?") === 0)
    complete(requests[1], 200, JSON.stringify([
      { duration: 250, plainLyrics: "far" },
      { duration: 201, plainLyrics: "near" }
    ]))
    compare(loadedEvents.length, 1)
    compare(loadedEvents[0].result.state, "ready")
    compare(loadedEvents[0].result.plain, ["near"])
    provider.destroy()
  }

  function test_emptySearchIsNotFound() {
    var provider = makeProvider()
    provider.fetch(song)
    complete(requests[0], 404, "{}")
    complete(requests[1], 200, "[]")
    compare(loadedEvents.length, 1)
    compare(loadedEvents[0].result.state, "not-found")
    compare(failedEvents.length, 0)
    provider.destroy()
  }

  function test_networkErrorFails() {
    var provider = makeProvider()
    var key = provider.fetch(song)
    complete(requests[0], 0, "")
    compare(loadedEvents.length, 0)
    compare(failedEvents.length, 1)
    compare(failedEvents[0].key, key)
    compare(failedEvents[0].message, "Lyrics are unavailable offline.")
    provider.destroy()
  }

  function test_serverErrorFailsWithStatus() {
    var provider = makeProvider()
    provider.fetch(song)
    complete(requests[0], 500, "")
    compare(failedEvents.length, 1)
    compare(failedEvents[0].message, "Lyrics service returned 500.")
    provider.destroy()
  }

  function test_openFailureFails() {
    var provider = makeProvider()
    failOpen = true
    provider.fetch(song)
    compare(failedEvents.length, 1)
    compare(failedEvents[0].message, "Lyrics could not be requested.")
    provider.destroy()
  }

  function test_timeoutAbortsAndFails() {
    var provider = makeProvider()
    var key = provider.fetch(song)
    provider.expireActiveRequest()
    verify(requests[0].aborted)
    compare(failedEvents.length, 1)
    compare(failedEvents[0].key, key)
    compare(failedEvents[0].message, "Lyrics request timed out.")
    // A late response for the aborted request is ignored.
    complete(requests[0], 200, JSON.stringify({ plainLyrics: "late" }))
    compare(loadedEvents.length, 0)
    provider.destroy()
  }

  function test_secondFetchDropsStaleResponse() {
    var provider = makeProvider()
    provider.fetch(song)
    var second = provider.fetch(otherSong)
    verify(requests[0].aborted)
    compare(requests.length, 2)
    complete(requests[0], 200, JSON.stringify({ plainLyrics: "stale" }))
    compare(loadedEvents.length, 0)
    complete(requests[1], 200, JSON.stringify({ plainLyrics: "fresh" }))
    compare(loadedEvents.length, 1)
    compare(loadedEvents[0].key, second)
    compare(loadedEvents[0].result.plain, ["fresh"])
    provider.destroy()
  }

  function test_cachedKeyAnswersWithoutARequest() {
    var provider = makeProvider()
    provider.fetch(song)
    complete(requests[0], 200, JSON.stringify({ plainLyrics: "Hi" }))
    compare(loadedEvents.length, 1)
    provider.fetch(song)
    compare(requests.length, 1)
    wait(0)
    compare(loadedEvents.length, 2)
    compare(loadedEvents[1].result.plain, ["Hi"])
    provider.destroy()
  }

  function test_cacheEvictsOldestBeyondLimit() {
    var provider = makeProvider()
    var limit = provider.cacheLimit
    for (var i = 0; i <= limit; i++) {
      provider.fetch({ id: "t" + i, title: "S" + i, artist: "A", album: "", duration: 100 })
      complete(requests[requests.length - 1], 200, JSON.stringify({ plainLyrics: "L" + i }))
    }
    compare(provider.cacheOrder.length, limit)
    compare(provider.cached("t0|S0|A||100"), null)
    verify(provider.cached("t1|S1|A||100") !== null)
    provider.destroy()
  }

  function test_cancelStopsTheActiveRequest() {
    var provider = makeProvider()
    provider.fetch(song)
    provider.cancel()
    verify(requests[0].aborted)
    complete(requests[0], 200, JSON.stringify({ plainLyrics: "x" }))
    compare(loadedEvents.length, 0)
    compare(failedEvents.length, 0)
    provider.destroy()
  }
}
