// Hikari 99 Real Sky 光. Generated from Hikari-99.qml by hikari-99/build.sh: edit that file, then run build.sh.
//
// Hikari, true to the original, drawn the way the wallpaper itself was made:
// the art's pixel grid, 12-bit color and a noise dither in place of film
// grain. The clouds drift and the light behind them breathes, on the wall
// clock, with the desktop's. Stay away and the sky turns to evening, then night, and single
// pixels of starlight come out between the clouds. Come back and 光 is written
// again, stroke by stroke. Each key pushes light through the clouds and draws
// a pencil 〇 on the line of light. A wrong password is a cloud's shadow
// passing over. The right one parts the clouds along Omarchy's slant, and the
// picture settles on your wallpaper cell by cell. 光, its glow, the marks and
// every light are part of the picture and go through the same process; the
// clock and the small words stay crisp on top.
//
// Plays its own unlock: the explorer holds the screen for a design it counts
// as a clip (it looks for the word ClipDesign in the file) until the design
// calls unlockFinished(), or 15 seconds at most. No video is involved.
//
// If a keyboard lighting service listens on
// $XDG_RUNTIME_DIR/keychron-glow.sock, it is told what happened (a key, a
// wrong password, the unlock), never which key. See the README.
//
// Two clocks, picked with followSun. Off (this design): every lock runs from
// day to night in twenty-two minutes (or as long as shared/night-minutes
// says), and typing brings the day back. On
// (Hikari 99 Real Sky, Hikari-99-Real-Sky.qml): the real sun decides, worked
// out with no network for the place below.
//
// Stroke order for 光 from KanjiVG, (c) Ulrich Apel, CC BY-SA 3.0.
// The sky is hikari-99/sky.frag. After editing it, or this file, run
// hikari-99/build.sh: it compiles the shader and regenerates
// Hikari-99-Real-Sky.qml from this file.
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "shared/lock-state.js" as LockState
import qs.Commons
import "../plugins/io.github.sirjul1337.lock-explorer/designs"

DesignBase {
  id: lock
  inputItem: input
  flashOnFail: false
  shakeOnFail: false

  // false: day to night on every lock. true: the real sky.
  property bool followSun: true

  // Where the sun is worked out for. By default the reference city of the
  // system's timezone (from zone1970.tab): close enough for sunrise and
  // sunset, and nothing personal in this file. A line "latitude longitude" in
  // degrees in shared/location, next to this file, overrides it. Until one
  // of them answers: the timezone's offset, 15 degrees an hour.
  property real latitude: 45
  property real longitude: -(new Date().getTimezoneOffset()) / 4
  property bool located: false
  function setLocation(answer) {
    var t = String(answer || "").trim()
    var m = /^([+-])(\d{2})(\d{2})(\d{2})?([+-])(\d{3})(\d{2})(\d{2})?$/.exec(t)
    if (m) {
      latitude = (m[1] === "-" ? -1 : 1) * (Number(m[2]) + Number(m[3]) / 60 + (m[4] ? Number(m[4]) / 3600 : 0))
      longitude = (m[5] === "-" ? -1 : 1) * (Number(m[6]) + Number(m[7]) / 60 + (m[8] ? Number(m[8]) / 3600 : 0))
      located = true
      return
    }
    var p = t.split(/[\s,]+/)
    if (p.length >= 2 && isFinite(Number(p[0])) && isFinite(Number(p[1]))) {
      latitude = Number(p[0])
      longitude = Number(p[1])
      located = true
    }
  }
  Process {
    running: true
    command: ["sh", "-c", "f=\"$0/shared/location\"\nif [ -r \"$f\" ]; then head -n 1 \"$f\"; exit 0; fi\ntz=$(timedatectl show -p Timezone --value 2>/dev/null)\n[ -n \"$tz\" ] || tz=$(readlink /etc/localtime | sed 's|.*zoneinfo/||')\n[ -n \"$tz\" ] && awk -v tz=\"$tz\" '$3 == tz { print $2; exit }' /usr/share/zoneinfo/zone1970.tab /usr/share/zoneinfo/zone.tab",
              decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, ""))]
    stdout: StdioCollector { onStreamFinished: lock.setLocation(text) }
  }
  onLocatedChanged: readSky()

  // ---------------------------------------------------------------- colors
  property var palette: ({})
  function tone(name, fallback) { return palette[name] !== undefined ? palette[name] : fallback }
  readonly property color cNight: tone("darker_background", Qt.darker(Color.background, 1.4))
  readonly property color cAccent: tone("accent", Color.accent)
  readonly property color cLilac: tone("bright_magenta", Qt.lighter(Color.accent, 1.6))
  readonly property color cLight: tone("bright_foreground", Color.foreground)
  readonly property color cInk: tone("light_foreground", Color.lock.text)

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var out = {}
      var re = /^\s*([a-z_]+)\s*=\s*"(#[0-9a-fA-F]{6})"/gm
      var s = text()
      var m
      while ((m = re.exec(s)) !== null) out[m[1]] = m[2]
      lock.palette = out
    }
  }

  // ------------------------------------------------------------- geometry
  readonly property real dpr: Math.max(1, Screen.devicePixelRatio)
  readonly property real unit: Math.round(Math.min(height * 0.27, width * 0.2))
  // One pixel of the art (the wallpaper is 800 pixels across), in screen
  // pixels and in the layout's own units
  readonly property real cellPx: Math.max(1, Math.round(width * dpr / 800))
  readonly property real artPixel: cellPx / dpr
  readonly property real kanjiTop: Math.round(height / 2 + unit * 0.1 - unit)
  readonly property real clockTop: kanjiTop + unit + Math.round(unit * 0.12)
  readonly property real marksTop: clockTop + clockText.height + Math.round(unit * 0.07)
  readonly property real hintsTop: marksTop + paper.height + Math.round(unit * 0.07)

  // ------------------------------------------------------------------ time
  property real t: 0
  FrameAnimation {
    running: lock.animating
    onTriggered: {
      lock.t += Math.min(frameTime, 0.1)
      lock.wall = Date.now() / 1000
    }
  }

  // One slow breath, shared with the keyboard
  readonly property real breathPeriod: 12
  // On the wall clock, like the desktop's corner and the keyboard: every
  // screen breathes together, however long each copy has been running
  property real wall: Date.now() / 1000
  readonly property real breath: 0.5 - 0.5 * Math.cos(2 * Math.PI * wall / breathPeriod)
  function breathPhase() { return ((Date.now() / 1000) % breathPeriod) / breathPeriod }

  // How long you have been away: evening after about five minutes, the first
  // stars at about thirteen, night at twenty-two (scaled to nightMinutes).
  property real lockedAt: Date.now()

  // One lock, several screens. A monitor that disconnects while it sleeps
  // comes back as a new lock surface with a new copy of this design;
  // lock-state.js tells it when the lock really began and how far typing has
  // brought the day back, so it picks up where the other screen is. Only a
  // real lock takes part: previews and the explorer's cards keep their own.
  // The same question every 5 s is the heartbeat: a copy stops sharing the
  // moment the session is no longer locked, so a copy left running (the
  // explorer keeps its preview) can never carry one lock into the next.
  property bool sharing: false
  Process {
    id: lockCheck
    running: !lock.snapshotMode
    command: ["/usr/share/omarchy/bin/omarchy-shell", "lock", "isLocked"]
    stdout: StdioCollector {
      onStreamFinished: {
        var locked = String(text).trim() === "true" && !lock.snapshotMode
        if (!locked) {
          lock.sharing = false
          return
        }
        var now = Date.now()
        if (lock.sharing) {
          LockState.alive(now)
          return
        }
        lock.lockedAt = LockState.begin(now)
        lock.awayMinutes = (now - lock.lockedAt) / 60000
        lock.returned = LockState.returned
        lock.sharing = true
      }
    }
  }
  Timer {
    interval: 5000
    running: lock.sharing
    repeat: true
    onTriggered: if (!lockCheck.running) lockCheck.running = true
  }
  onReturnedChanged: if (sharing) LockState.returned = returned
  // A password going in: if every copy is gone right after it, the lock ended
  // (lock-state.js). Guarded: a shell still running an older copy of the
  // shared file has no checking().
  onAuthenticatingPasswordChanged: if (authenticatingPassword && sharing && LockState.checking) LockState.checking(Date.now())
  property real awayMinutes: 0
  // How long a lock takes to reach night: 22 minutes, or the number of
  // minutes in shared/night-minutes, next to this file. Evening and the
  // stars come at the same share of it.
  property real nightMinutes: 22
  FileView {
    path: decodeURIComponent(String(Qt.resolvedUrl("shared/night-minutes")).replace(/^file:\/\//, ""))
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var m = /^\s*(\d+(\.\d+)?)/.exec(text())
      lock.nightMinutes = m ? Math.max(2, Math.min(1440, Number(m[1]))) : 22
    }
    onLoadFailed: lock.nightMinutes = 22
  }
  readonly property real dusk: Math.max(0, Math.min(1, (awayMinutes * 22 / nightMinutes - 1.5) / 20.5))

  // The real sky: from 6 degrees of sun down to 12 below the horizon
  property real sunDusk: 0
  function readSky() {
    var when = new Date()
    awayMinutes = (when.getTime() - lockedAt) / 60000
    var s = Math.max(0, Math.min(1, (6 - sunElevation(when)) / 18))
    sunDusk = s * s * (3 - 2 * s)
  }
  function sunElevation(when) {
    var rad = Math.PI / 180
    var n = when.getTime() / 86400000 + 2440587.5 - 2451545.0
    var L = (280.460 + 0.9856474 * n) % 360
    var g = ((357.528 + 0.9856003 * n) % 360) * rad
    var lambda = (L + 1.915 * Math.sin(g) + 0.020 * Math.sin(2 * g)) * rad
    var eps = (23.439 - 0.0000004 * n) * rad
    var dec = Math.asin(Math.sin(eps) * Math.sin(lambda))
    var ra = Math.atan2(Math.cos(eps) * Math.sin(lambda), Math.cos(lambda))
    var gmst = (18.697374558 + 24.06570982441908 * n) % 24
    var ha = (gmst * 15 + longitude) * rad - ra
    return Math.asin(Math.sin(latitude * rad) * Math.sin(dec) + Math.cos(latitude * rad) * Math.cos(dec) * Math.cos(ha)) / rad
  }

  Timer {
    interval: 10000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: lock.readSky()
  }

  // Coming back brings the day back: waking the screen, then every key (on
  // the every-lock clock; the real sky does not care)
  property real returned: 0
  property real lastActive: Date.now()
  Behavior on returned { NumberAnimation { duration: 1400; easing.type: Easing.OutCubic } }
  function bringBack(amount) {
    returned = Math.min(1, returned + amount)
    lastActive = Date.now()
  }
  Timer {
    interval: 2000
    running: lock.returned > 0 && lock.animating
    repeat: true
    onTriggered: if (Date.now() - lock.lastActive > 30000) lock.returned = Math.max(0, lock.returned - 0.04)
  }
  readonly property real duskShown: followSun ? sunDusk : dusk * (1 - returned)

  // ------------------------------------------------------------ key lights
  property var pulses: [[0, 0, -10, 0], [0, 0, -10, 0], [0, 0, -10, 0], [0, 0, -10, 0]]
  property int pulseNext: 0
  function pulse(strength) {
    var p = pulses.slice()
    p[pulseNext] = [0.12 + Math.random() * 0.76, 0.06 + Math.random() * 0.5, t, strength]
    pulses = p
    pulseNext = (pulseNext + 1) % 4
  }
  function pulseVec(i) {
    var p = pulses[i]
    var age = (t - p[2]) / 1.5
    var alive = age >= 0 && age < 1
    return Qt.vector4d(p[0], p[1], alive ? age : 1, alive ? p[3] : 0)
  }

  // ------------------------------------------------ fail shadow and unlock
  property real shadow: 0
  readonly property real shade: shadow > 0 && shadow < 1 ? Math.exp(-Math.pow((shadow - 0.5) / 0.16, 2)) : 0
  property real part: 0
  property real settle: 0
  property real bloom: 0

  NumberAnimation {
    id: shadowPass
    target: lock
    property: "shadow"
    from: 0.001
    to: 1
    duration: 1800
    easing.type: Easing.InOutSine
  }

  // ------------------------------------------------------------------- sky
  Rectangle { anchors.fill: parent; color: lock.cNight }

  readonly property string wallUrl: loadBackground && backgroundPath.length > 0 ? fileUrl(backgroundPath) : ""
  Image {
    id: wallImage
    anchors.fill: parent
    source: lock.wallUrl
    fillMode: Image.PreserveAspectCrop
    sourceSize.width: Math.round(lock.width * lock.dpr)
    asynchronous: true
    cache: true
    smooth: true
  }
  ShaderEffectSource {
    id: wallTexture
    anchors.fill: parent
    sourceItem: wallImage
    hideSource: true
    mipmap: true
    smooth: true
    visible: false
  }

  // What gets drawn into the picture: 光 (red) and the pencil marks (green)
  Item {
    id: inkLayer
    anchors.fill: parent

    Canvas {
      id: kanji
      x: Math.round((lock.width - lock.unit) / 2)
      y: lock.kanjiTop
      width: lock.unit
      height: lock.unit
      scale: 1 + lock.bloom * 0.06
      renderStrategy: Canvas.Cooperative
      property real clock: lock.writeClock
      onClockChanged: requestPaint()
      onWidthChanged: requestPaint()

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var k = width / 109
        var base = 5.4 * k
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        ctx.strokeStyle = "#ff0000"
        for (var i = 0; i < lock.strokes.length; i++) {
          var progress = lock.strokeProgress(i, clock)
          if (progress <= 0) break
          var st = lock.strokes[i]
          var pts = st.points
          var n = pts.length / 2
          var reach = progress * (n - 1)
          for (var j = 0; j < Math.ceil(reach); j++) {
            var f = Math.min(1, reach - j)
            var x0 = pts[2 * j] * k
            var y0 = pts[2 * j + 1] * k
            var x1 = x0 + (pts[2 * j + 2] * k - x0) * f
            var y1 = y0 + (pts[2 * j + 3] * k - y0) * f
            ctx.lineWidth = base * lock.strokeWidth(st.type, (j + f) / (n - 1))
            ctx.beginPath()
            ctx.moveTo(x0, y0)
            ctx.lineTo(x1, y1)
            ctx.stroke()
          }
        }
      }
    }

    Paper {
      id: paper
      lock: lock
      x: Math.round((lock.width - width) / 2)
      y: lock.marksTop
    }
  }
  ShaderEffectSource {
    id: inkTexture
    anchors.fill: parent
    sourceItem: inkLayer
    hideSource: true
    mipmap: true
    smooth: true
    visible: false
  }

  readonly property real screenAspect: width / Math.max(1, height)

  ShaderEffect {
    id: sky
    anchors.fill: parent
    visible: wallImage.status === Image.Ready
    fragmentShader: Qt.resolvedUrl("hikari-99/sky-e4e0e804.frag.qsb")

    property var wall: wallTexture
    property var ink: inkTexture
    property real time: lock.t
    property real dusk: lock.duskShown
    property real glow: 0.18 + 0.2 * lock.breath + Math.min(0.25, typing.cadence * 0.04) + lock.bloom * 0.4
    property real shadow: lock.shadow
    property real part: lock.part
    property real settle: lock.settle
    property real bloom: lock.bloom
    property real errorOn: lock.errorState ? 1 : 0
    property real aspect: lock.screenAspect
    property real softness: Math.max(0.3, Math.log(width * lock.dpr / 1400) / Math.LN2)
    property real cell: lock.cellPx
    property vector2d res: Qt.vector2d(width * lock.dpr, height * lock.dpr)
    property vector4d pulseA: lock.pulseVec(0)
    property vector4d pulseB: lock.pulseVec(1)
    property vector4d pulseC: lock.pulseVec(2)
    property vector4d pulseD: lock.pulseVec(3)
    property color night: lock.cNight
    property color accent: lock.cAccent
    property color lilac: lock.cLilac
    property color light: lock.cLight
    property color error: Color.lock.textError
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    onClicked: { lock.wakeRequested(); lock.forcePasswordFocus() }
    onPositionChanged: lock.wakeRequested()
  }

  LockInput {
    id: input
    lock: lock
    width: 1
    height: 1
    opacity: 0
    anchors.centerIn: parent
  }

  // ------------------------------------------------------------- 光 strokes
  // KanjiVG's six strokes in textbook order, in its 109 unit box
  readonly property var strokes: [
    { type: "㇑a", length: 32.4, points: [51.7,15.4,52.5,16.3,53,17.4,53.4,18.6,53.6,19.9,53.6,21.1,53.6,22.4,53.6,23.6,53.6,24.9,53.7,26.1,53.7,27.3,53.7,28.6,53.7,29.8,53.7,31.1,53.7,32.3,53.7,33.6,53.7,34.8,53.7,36,53.7,37.3,53.7,38.5,53.7,39.8,53.7,41,53.7,42.3,53.6,43.5,53.6,44.8,53.6,46,53.6,47.3] },
    { type: "㇔", length: 19.0, points: [26.5,26.2,27.5,27,28.5,27.8,29.4,28.7,30.3,29.6,31.1,30.5,32,31.5,32.8,32.5,33.5,33.5,34.3,34.5,35,35.6,35.7,36.6,36.4,37.7,37,38.8,37.5,40,37.9,41.2] },
    { type: "㇒", length: 23.6, points: [77.5,20.5,77.5,21.7,77.3,23,77,24.2,76.5,25.3,76.1,26.5,75.5,27.6,75,28.7,74.4,29.8,73.8,30.9,73.2,32,72.5,33,71.8,34.1,71.1,35.1,70.3,36.1,69.6,37,68.8,38,67.9,38.9,67,39.8,66.1,40.6] },
    { type: "㇐", length: 75.2, points: [16.1,51.5,17.3,51.7,18.5,51.9,19.7,52,20.9,52,22.2,52,23.4,51.9,24.6,51.8,25.8,51.6,27,51.5,28.2,51.4,29.4,51.2,30.6,51.1,31.8,51,33,50.8,34.2,50.7,35.4,50.6,36.6,50.4,37.9,50.3,39,50.2,40.3,50,41.5,49.9,42.7,49.8,43.9,49.6,45.1,49.5,46.3,49.4,47.5,49.2,48.7,49.1,49.9,49,51.1,48.8,52.3,48.7,53.5,48.6,54.7,48.5,55.9,48.3,57.1,48.2,58.4,48.1,59.6,48,60.8,47.8,62,47.7,63.2,47.6,64.4,47.5,65.6,47.4,66.8,47.3,68,47.1,69.2,47,70.4,46.9,71.7,46.8,72.9,46.7,74.1,46.6,75.3,46.5,76.5,46.5,77.7,46.4,78.9,46.3,80.1,46.2,81.3,46.1,82.5,46.1,83.8,46,85,46,86.2,46,87.4,46.1,88.6,46.2,89.8,46.4,91,46.6] },
    { type: "㇒", length: 46.5, points: [45.5,53.5,45.7,54.7,45.6,55.9,45.4,57.1,45,58.3,44.7,59.5,44.3,60.6,44,61.8,43.6,63,43.2,64.1,42.8,65.3,42.3,66.4,41.9,67.5,41.4,68.7,40.9,69.8,40.4,70.9,39.8,72,39.2,73.1,38.6,74.1,38,75.2,37.4,76.2,36.7,77.3,36,78.3,35.3,79.3,34.6,80.2,33.8,81.2,33,82.1,32.2,83,31.4,83.9,30.5,84.8,29.6,85.7,28.8,86.5,27.8,87.3,26.9,88.1,25.9,88.9,25,89.6,24,90.3,23,91.1,22,91.8] },
    { type: "㇟", length: 75.4, points: [58.7,51.4,59.3,52.5,59.7,53.6,59.9,54.8,60,56,60,57.2,60,58.4,60,59.7,60,60.9,60,62.1,60,63.3,60,64.5,60,65.7,60,67,60,68.2,60,69.4,60,70.6,60,71.8,60,73,60,74.3,60,75.5,60,76.7,60,77.9,60,79.1,60,80.3,60.1,81.6,60.2,82.8,60.3,84,60.5,85.2,60.8,86.3,61.3,87.5,62,88.5,62.9,89.3,63.9,90,65,90.4,66.2,90.8,67.4,91,68.6,91.2,69.8,91.3,71,91.4,72.2,91.4,73.5,91.5,74.7,91.5,75.9,91.5,77.1,91.5,78.3,91.5,79.5,91.5,80.8,91.5,82,91.5,83.2,91.4,84.4,91.3,85.6,91.2,86.8,91,88,90.8,89.2,90.5,90.3,90.1,91.4,89.5,92.3,88.7,92.9,87.7,93.3,86.5,93.5,85.3,93.6,84.1,93.6,82.9] }
  ]

  // When each stroke starts and how long the hand takes over it (ms). The pen
  // lifts between strokes.
  readonly property var schedule: {
    var out = []
    var at = 0
    for (var i = 0; i < strokes.length; i++) {
      var dur = Math.round(220 + strokes[i].length * 8)
      out.push({ start: at, dur: dur })
      at += dur + 150
    }
    return out
  }
  readonly property real writeTotal: schedule[schedule.length - 1].start + schedule[schedule.length - 1].dur
  property real writeClock: 0
  readonly property bool written: writeClock >= writeTotal

  NumberAnimation {
    id: writing
    target: lock
    property: "writeClock"
    from: 0
    to: lock.writeTotal
    duration: lock.writeTotal
    onFinished: lock.stillRequested()
  }
  Timer { id: writeSoon; interval: 700; onTriggered: writing.restart() }

  // The explorer's cards and side preview are small and photographed early:
  // they get the kanji already written
  readonly property bool small: width > 0 && width < 900
  function rewrite() {
    writing.stop()
    writeSoon.stop()
    if (small || snapshotMode) {
      writeClock = writeTotal
      stillRequested()
      return
    }
    writeClock = 0
    writeSoon.restart()
  }
  onSmallChanged: if (small) rewrite()

  // Left-falling strokes speed up into their sweep, the rest ease in and out
  function strokeProgress(i, clock) {
    var s = schedule[i]
    var u = Math.max(0, Math.min(1, (clock - s.start) / s.dur))
    if (strokes[i].type === "㇒") return Math.pow(u, 1.45)
    return u < 0.5 ? 2 * u * u : 1 - 2 * (1 - u) * (1 - u)
  }

  // After the textbook hand: a press to start, a sweep that thins out, a dot
  // that presses in, a hook that flicks off
  function strokeWidth(type, u) {
    if (type === "㇒") return Math.max(0.18, 1.08 - 0.9 * Math.pow(u, 1.5))
    if (type === "㇔") return 0.55 + 0.6 * u
    if (type === "㇟") return u > 0.9 ? Math.max(0.2, 1 - (u - 0.9) * 8) : 1.02 - 0.1 * Math.min(1, u * 6)
    return 1.12 - 0.14 * Math.min(1, u * 5) + (u > 0.94 ? (u - 0.94) * 2 : 0)
  }

  // ------------------------------------------------------ words, on the glass
  Item {
    id: chrome
    anchors.fill: parent
    // A soft navy shadow so the words read on a bright cloud
    layer.enabled: true
    layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0.02, 0.04, 0.14, 0.55); shadowBlur: 0.6; shadowVerticalOffset: 1 }

    Item {
      anchors.fill: parent
      opacity: 1 - 0.3 * lock.shade

      // Reading above the kanji, the way a textbook prints it
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        y: lock.kanjiTop - height - Math.round(lock.unit * 0.02)
        text: "ひかり"
        color: lock.cInk
        opacity: lock.written ? 0.75 : 0
        Behavior on opacity { NumberAnimation { duration: 1200; easing.type: Easing.OutCubic } }
        font.family: "Klee One"
        font.pixelSize: Math.round(lock.unit * 0.075)
        font.letterSpacing: Math.round(lock.unit * 0.035)
      }

      // The date, written down the side: 九月二十九日, 火曜日の夜
      Row {
        x: Math.round((lock.width + lock.unit) / 2 + lock.unit * 0.06)
        y: lock.kanjiTop + Math.round(lock.unit * 0.08)
        spacing: Math.round(lock.unit * 0.035)
        layoutDirection: Qt.RightToLeft
        opacity: lock.written ? 0.9 : 0
        Behavior on opacity { NumberAnimation { duration: 1600; easing.type: Easing.OutCubic } }

        Tategaki { text: lock.jpDate; size: Math.round(lock.unit * 0.085); color: lock.cInk }
        Tategaki { text: lock.jpDay; size: Math.round(lock.unit * 0.085); color: lock.cInk; opacity: 0.75; topPadding: Math.round(lock.unit * 0.09) }
      }

      Text {
        id: clockText
        anchors.horizontalCenter: parent.horizontalCenter
        y: lock.clockTop
        text: lock.clock("HH:mm")
        color: lock.cInk
        font.family: "Klee One"
        font.weight: Font.DemiBold
        font.pixelSize: Math.round(lock.unit * 0.2)
        font.letterSpacing: Math.round(lock.unit * 0.02)
      }

      EyeButton {
        lock: lock
        x: Math.round((lock.width + paper.width) / 2 + lock.unit * 0.04)
        y: lock.marksTop + (paper.height - height) / 2
        size: Math.round(lock.unit * 0.07)
      }

      Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: lock.hintsTop
        spacing: Math.round(lock.unit * 0.015)
        opacity: lock.snapshotMode ? 0 : 1

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: lock.jpHint
          color: lock.errorState ? Color.lock.textError : lock.cInk
          opacity: 0.9
          font.family: "Klee One"
          font.pixelSize: Math.round(lock.unit * 0.06)
          font.letterSpacing: Math.round(lock.unit * 0.01)
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: lock.enHint
          textFormat: Text.PlainText
          color: lock.errorState ? Color.lock.textError : lock.cInk
          opacity: 0.8
          font.family: "Murecho"
          font.pixelSize: Math.max(Style.font.bodySmall, Math.round(lock.unit * 0.034))
          font.letterSpacing: 1
        }
      }
    }
  }

  // --------------------------------------------------------------- words
  function kanjiNumber(n) {
    var d = ["〇", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
    if (n < 10) return d[n]
    var tens = Math.floor(n / 10)
    var ones = n % 10
    return (tens > 1 ? d[tens] : "") + "十" + (ones > 0 ? d[ones] : "")
  }
  readonly property string jpDate: kanjiNumber(now.getMonth() + 1) + "月" + kanjiNumber(now.getDate()) + "日"
  readonly property string jpDay: {
    var day = ["日", "月", "火", "水", "木", "金", "土"][now.getDay()] + "曜日"
    var h = now.getHours()
    var part = h >= 5 && h < 10 ? "朝" : (h >= 10 && h < 16 ? "昼" : (h >= 16 && h < 19 ? "夕方" : "夜"))
    return day + "の" + part
  }

  readonly property string jpHint: authenticatingPassword ? "確認中…"
    : (errorState ? "もう一度どうぞ"
    : (fido2Active ? "キーに触れてください"
    : "おかえりなさい"))

  readonly property string badges: (capsLock && showCapsBadge ? "CAPS  ·  " : "")
    + ((foreignLayout || layoutSwitchable) && showLayoutBadge && keyboardLayout.length > 0 ? keyboardLayout + "  ·  " : "")
  readonly property string enHint: badges + (authenticatingPassword ? tr("Checking…")
    : (errorState ? failureMessage
    : (fido2Active ? (fido2Status.length > 0 ? fido2Status : tr("Waiting for your key…"))
    : (fingerprintConfigured ? fingerprintHint(tr("Type your password or touch the sensor")) : tr("Type your password")))))

  // ------------------------------------------------------------ the marks
  // The field empties the moment Enter goes in; the marks stay while the
  // password is checked, and are rubbed out if it was wrong.
  property int lastLength: 0
  property int heldMarks: 0
  property bool erasing: false
  readonly property int marks: passwordText.length > 0 ? passwordText.length : heldMarks
  onPasswordTextChanged: if (passwordText.length > 0) lastLength = passwordText.length

  Timer {
    id: holdCheck
    interval: 400
    onTriggered: if (!lock.authenticatingPassword && !lock.errorState && lock.passwordText.length === 0) lock.eraseMarks()
  }
  Timer {
    id: eraseDone
    interval: 650
    onTriggered: { lock.heldMarks = 0; lock.erasing = false }
  }
  function eraseMarks() {
    if (heldMarks === 0) return
    erasing = true
    eraseDone.restart()
  }

  Typing {
    id: typing
    lock: lock
    onTyped: {
      lock.pulse(0.9 + Math.random() * 0.5)
      lock.bringBack(0.12)
      lock.tell("key")
    }
    onDeleted: lock.tell("back")
    onCleared: {
      lock.heldMarks = lock.lastLength
      holdCheck.restart()
    }
  }

  Connections {
    target: lock
    function onFailureMessageChanged() {
      if (lock.failureMessage.length === 0) return
      shadowPass.restart()
      lock.eraseMarks()
      lock.tell("fail")
    }
    function onScreenAwakeChanged() {
      if (lock.screenAwake) {
        lock.bringBack(0.3)
        lock.rewrite()
        lock.tell("wake")
      } else {
        lock.tell("sleep")
      }
    }
    function onUnlockPlaybackChanged() {
      if (lock.unlockPlayback) {
        if (lock.sharing) {
          LockState.end()
          lock.sharing = false
        }
        unlocking.restart()
      } else {
        unlocking.stop()
        lock.part = 0
        lock.settle = 0
        lock.bloom = 0
        chrome.opacity = 1
      }
    }
  }

  // The right password: the clouds part along the slant, the light floods
  // in and 光 goes with it, then the picture settles on the wallpaper
  SequentialAnimation {
    id: unlocking
    ScriptAction { script: lock.tell("unlock") }
    ParallelAnimation {
      NumberAnimation { target: lock; property: "part"; from: 0; to: 1; duration: 1150; easing.type: Easing.OutCubic }
      NumberAnimation { target: lock; property: "bloom"; from: 0; to: 1; duration: 450; easing.type: Easing.OutCubic }
      SequentialAnimation {
        PauseAnimation { duration: 250 }
        NumberAnimation { target: chrome; property: "opacity"; to: 0; duration: 600; easing.type: Easing.InCubic }
      }
    }
    NumberAnimation { target: lock; property: "settle"; from: 0; to: 1; duration: 850; easing.type: Easing.InOutSine }
    ScriptAction { script: lock.unlockFinished() }
  }

  // --------------------------------------------------------- the keyboard
  readonly property bool linkWanted: visible && !snapshotMode && width >= 900
  // Only when a lighting service is listening: everyone else gets no
  // connection attempts and no log noise
  property bool linkAvailable: false
  Socket {
    id: link
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000") + "/keychron-glow.sock"
    onConnectionStateChanged: if (connected) {
      lock.tell("lock " + lock.breathPhase().toFixed(3) + " " + lock.breathPeriod)
      lock.tell(lock.screenAwake ? "wake" : "sleep")
    }
    onError: lock.linkAvailable = false
  }
  Process {
    id: linkProbe
    command: ["test", "-S", link.path]
    onExited: function(exitCode) { lock.linkAvailable = exitCode === 0 }
  }
  function tell(message) {
    if (!link.connected) return
    link.write(message + "\n")
    link.flush()
  }
  Timer {
    interval: 4000
    running: lock.linkWanted
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (!lock.fullSizeOnScreen()) {
        if (link.connected) link.connected = false
        return
      }
      if (!link.connected) {
        if (lock.linkAvailable) link.connected = true
        else if (!linkProbe.running) linkProbe.running = true
      }
      else lock.tell("ping " + lock.breathPhase().toFixed(3) + " " + lock.duskShown.toFixed(3))
    }
  }
  onLinkWantedChanged: if (!linkWanted && link.connected) link.connected = false

  // Only a lock screen drawn full size on a visible screen talks to the
  // keyboard. The explorer's live panel draws designs at full size and
  // shrinks them; those stay quiet. (The keyboard also asks the lock service
  // whether the session is really locked.)
  function fullSizeOnScreen() {
    var w = Window.window
    if (!w || !w.visible) return false
    var a = mapToItem(null, 0, 0)
    var b = mapToItem(null, width, 0)
    return (b.x - a.x) >= w.width * 0.9
  }

  Component.onCompleted: rewrite()

  // ------------------------------------------------------------ components
  // Vertical writing, top to bottom
  component Tategaki: Column {
    id: column
    property string text: ""
    property real size: 20
    property color color: "white"
    spacing: Math.round(size * 0.06)
    Repeater {
      model: column.text.split("")
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: modelData
        color: column.color
        font.family: "Klee One"
        font.pixelSize: column.size
      }
    }
  }

  // The password line, drawn into the picture in green: a pencil 〇 for each
  // key on one line of light, both one pixel of the art thick
  component Paper: Item {
    id: sheet
    property var lock: null
    readonly property real cell: Math.round(lock.unit * 0.1)
    readonly property real stroke: Math.max(1.5, lock.artPixel * 1.15)
    readonly property int slots: Math.min(24, Math.max(12, lock.marks + 2))
    readonly property int shown: Math.min(lock.marks, slots - 1)
    readonly property int offset: lock.marks - shown
    readonly property real startX: (width - shown * cell) / 2
    width: slots * cell
    height: cell

    Behavior on width { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      y: Math.round(sheet.cell * 0.95)
      width: parent.width
      height: sheet.stroke
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: 0.25; color: Qt.rgba(0, 1, 0, 0.6) }
        GradientStop { position: 0.75; color: Qt.rgba(0, 1, 0, 0.6) }
        GradientStop { position: 1.0; color: "transparent" }
      }
    }

    // Where the next mark goes, breathing with the sky
    Rectangle {
      readonly property bool on: sheet.lock.inputEnabled && !sheet.lock.authenticatingPassword && !sheet.lock.errorState && !sheet.lock.erasing
      x: sheet.startX + sheet.shown * sheet.cell + sheet.cell / 2 - width / 2 - (sheet.shown === 0 ? sheet.cell / 2 : 0)
      y: sheet.cell / 2 - height / 2
      width: sheet.stroke
      height: Math.round(sheet.cell * 0.5)
      color: "#00ff00"
      visible: on
      opacity: 0.35 + 0.45 * sheet.lock.breath
      Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    }

    Repeater {
      model: sheet.slots
      Item {
        id: square
        required property int index
        x: sheet.startX + index * sheet.cell
        width: sheet.cell
        height: sheet.cell
        readonly property bool filled: index < sheet.shown
        // Same shape every time in the same place: a hand is consistent
        readonly property real seed: Math.abs(Math.sin((index + 1) * 12.9898) * 43758.5453) % 1
        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

        // The pencil 〇
        Shape {
          id: maru
          anchors.fill: parent
          visible: square.filled && !sheet.lock.passwordVisible
          preferredRendererType: Shape.CurveRenderer
          property real sweep: 0
          opacity: sheet.lock.erasing ? 0 : 1
          Behavior on opacity { NumberAnimation { duration: 280 } }

          ShapePath {
            strokeColor: "#00ff00"
            strokeWidth: sheet.stroke
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
              centerX: maru.width / 2 + (square.seed - 0.5) * sheet.cell * 0.06
              centerY: maru.height / 2 + (square.seed * 7 % 1 - 0.5) * sheet.cell * 0.06
              radiusX: sheet.cell * (0.25 + square.seed * 0.03)
              radiusY: sheet.cell * (0.23 + (square.seed * 3 % 1) * 0.04)
              startAngle: -110 + square.seed * 40
              sweepAngle: maru.sweep
            }
          }

          NumberAnimation {
            id: drawMaru
            target: maru
            property: "sweep"
            from: 0
            to: 335 + square.seed * 25
            duration: 170
            easing.type: Easing.OutQuad
          }
        }

        onFilledChanged: if (filled) drawMaru.restart()
        Component.onCompleted: if (filled) maru.sweep = 335 + seed * 25

        // Shown with the eye: the characters themselves, in the same hand
        Text {
          anchors.centerIn: parent
          visible: square.filled && sheet.lock.passwordVisible
          text: sheet.lock.passwordText.charAt(sheet.offset + square.index)
          textFormat: Text.PlainText
          color: "#00ff00"
          font.family: "Klee One"
          font.pixelSize: Math.round(sheet.cell * 0.6)
        }
      }
    }
  }
}
