// Tsukiyo 99 月夜, moonlit night
//
// The time of day, told in the wallpaper's own processes. Day is the sky piece
// (12-bit color, noise-dithered, on the art's pixel grid), evening the house
// piece (four colors in '/' hatching), night the moon piece (1-bit Bayer).
// As the light goes the colors run out, and each change dissolves across the
// screen through the dither.
//
// Two clocks, picked with followSun. Off (this design): every lock runs the
// whole day, evening at about five minutes, night by twenty-two (or at the
// same pace to the length in shared/night-minutes), and typing brings the
// color back. On (Tsukiyo 99 Real Sky, Tsukiyo-99-Real-Sky.qml,
// generated from this file by tsukiyo-99/build.sh): the real sun decides, worked out with
// no network for the place below.
//
// At night 月 is the moon: its glow goes through the Bayer matrix and breaks
// into rings, and every key sends another ring out. Now and then a streak of
// light crosses the dark along the '/'. A wrong password is a VHS tracking
// error rolling down the screen. The unlock brings the color back along
// Omarchy's slant and settles on the wallpaper.
//
// Plays its own unlock: the explorer holds the screen for a design it counts
// as a clip (it looks for the word ClipDesign in the file) until the design
// calls unlockFinished(), or 15 seconds at most. No video is involved.
//
// If a keyboard lighting service listens on
// $XDG_RUNTIME_DIR/keychron-glow.sock, it is told what happened (a key, a
// wrong password, the unlock), never which key. See the README.
//
// Stroke order for 月 from KanjiVG, (c) Ulrich Apel, CC BY-SA 3.0.
// The sky is tsukiyo-99/sky.frag. After editing it, or this file, run
// tsukiyo-99/build.sh: it compiles the shader and regenerates
// Tsukiyo-99-Real-Sky.qml.
import QtQuick
import QtQuick.Effects
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

  // false: the whole day on every lock. true: the real sky.
  property bool followSun: false

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
  // One pixel of the art: the wallpaper is 800 pixels across
  readonly property real cellPx: Math.max(1, Math.round(width * dpr / 800))
  readonly property real kanjiTop: Math.round(height / 2 + unit * 0.1 - unit)
  readonly property real clockTop: kanjiTop + unit + Math.round(unit * 0.12)
  readonly property real marksTop: clockTop + clockText.height + Math.round(unit * 0.08)
  readonly property real hintsTop: marksTop + marksRow.height + Math.round(unit * 0.08)

  // ------------------------------------------------------------------ time
  property real t: 0
  FrameAnimation {
    running: lock.animating
    onTriggered: {
      lock.t += Math.min(frameTime, 0.1)
      lock.wall = Date.now() / 1000
    }
  }

  readonly property real breathPeriod: 12
  // On the wall clock, like the desktop's corner and the keyboard: every
  // screen breathes together, however long each copy has been running
  property real wall: Date.now() / 1000
  readonly property real breath: 0.5 - 0.5 * Math.cos(2 * Math.PI * wall / breathPeriod)
  function breathPhase() { return ((Date.now() / 1000) % breathPeriod) / breathPeriod }

  // Away: evening after about five minutes, night at twenty-two (scaled to
  // nightMinutes)
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
  readonly property real awayDusk: Math.max(0, Math.min(1, (awayMinutes * 22 / nightMinutes - 1.5) / 20.5))

  // The real sky: from 6 degrees of sun down to 12 below the horizon
  property real sunDusk: 0

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
  function readSky() {
    var when = new Date()
    awayMinutes = (when.getTime() - lockedAt) / 60000
    var s = Math.max(0, Math.min(1, (6 - sunElevation(when)) / 18))
    sunDusk = s * s * (3 - 2 * s)
  }
  Timer {
    interval: 10000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: lock.readSky()
  }

  // Typing brings the day back (only on the every-lock clock: the real sky
  // does not care)
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
  readonly property real duskShown: followSun ? sunDusk : awayDusk * (1 - returned)
  readonly property bool isNight: duskShown > 0.62

  // ------------------------------------------------------------- key rings
  // The last four keys, each a ring of light leaving 月 over two seconds
  property var ringStarts: [-100, -100, -100, -100]
  property int ringNext: 0
  function ring() {
    var r = ringStarts.slice()
    r[ringNext] = t
    ringStarts = r
    ringNext = (ringNext + 1) % 4
  }
  function ringAge(i) { return Math.max(0, Math.min(1, (t - ringStarts[i]) / 2.0)) }

  // ----------------------------------------------------------- the streak
  // Now and then at night, a streak of light across the dark along the '/'
  property var streakFrom: Qt.vector2d(0.2, 0.5)
  property real streakAt: -100
  Timer {
    id: streakTimer
    interval: 40000
    running: lock.isNight && lock.animating && !lock.small
    repeat: true
    onTriggered: {
      interval = 35000 + Math.round(Math.random() * 45000)
      lock.streakFrom = Qt.vector2d(0.05 + Math.random() * 0.5, 0.25 + Math.random() * 0.35)
      lock.streakAt = lock.t
    }
  }
  readonly property real streakAge: Math.max(0, Math.min(1, (t - streakAt) / 1.4))

  // ------------------------------------------ tracking error and unlock
  property real tracking: 0
  readonly property real shade: tracking > 0 && tracking < 1 ? Math.exp(-Math.pow((tracking - 0.5) / 0.2, 2)) : 0
  property real part: 0

  NumberAnimation {
    id: trackingRoll
    target: lock
    property: "tracking"
    from: 0.001
    to: 1
    duration: 1500
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

  // What gets drawn into the pixel grid: 月, the clock and the marks
  Item {
    id: inkLayer
    anchors.fill: parent

    Canvas {
      id: kanji
      x: Math.round((lock.width - lock.unit) / 2)
      y: lock.kanjiTop
      width: lock.unit
      height: lock.unit
      renderStrategy: Canvas.Cooperative
      property real clock: lock.writeClock
      onClockChanged: requestPaint()
      onWidthChanged: requestPaint()
      // Red channel: the shader tells 月 from the rest by color
      property color ink: "#ff0000"

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var k = width / 109
        var base = 5.6 * k
        ctx.lineCap = "round"
        ctx.lineJoin = "round"
        ctx.strokeStyle = String(ink)
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

    // A small square of light for each key, and where the next one goes
    Item {
      id: marksRow
      readonly property real step: Math.round(lock.unit * 0.075)
      readonly property real dot: Math.max(4, Math.round(lock.unit * 0.034))
      readonly property int slots: Math.min(24, Math.max(12, lock.marks + 2))
      readonly property int shown: Math.min(lock.marks, slots - 1)
      // Green channel
      readonly property color ink: "#00ff00"
      anchors.horizontalCenter: parent.horizontalCenter
      y: lock.marksTop
      width: slots * step
      height: step

      Repeater {
        model: marksRow.slots
        Rectangle {
          required property int index
          readonly property bool filled: index < marksRow.shown
          x: (marksRow.width - marksRow.shown * marksRow.step) / 2 + index * marksRow.step + (marksRow.step - width) / 2
          y: (marksRow.height - height) / 2
          width: marksRow.dot
          height: marksRow.dot
          color: marksRow.ink
          visible: filled && !lock.passwordVisible
          opacity: lock.erasing ? 0 : 1
          scale: filled ? 1 : 0.2
          Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutBack } }
          Behavior on opacity { NumberAnimation { duration: 280 } }
          Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
      }

      Rectangle {
        visible: lock.inputEnabled && !lock.authenticatingPassword && !lock.errorState && !lock.erasing && !lock.passwordVisible
        x: (marksRow.width - marksRow.shown * marksRow.step) / 2 + marksRow.shown * marksRow.step + (marksRow.step - width) / 2 - (marksRow.shown === 0 ? marksRow.step / 2 : 0)
        y: (marksRow.height - height) / 2
        width: Math.max(2, Math.round(marksRow.dot * 0.35))
        height: Math.round(marksRow.step * 0.6)
        color: "#00ff00"
        opacity: 0.35 + 0.5 * lock.breath
        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
      }

      // Shown with the eye
      Text {
        anchors.centerIn: parent
        visible: lock.passwordVisible && lock.passwordText.length > 0
        text: lock.passwordText
        textFormat: Text.PlainText
        color: "#00ff00"
        font.family: "Klee One"
        font.pixelSize: Math.round(marksRow.step * 0.75)
        font.letterSpacing: Math.round(marksRow.step * 0.12)
      }
    }
  }
  // Behind the words that stay crisp on the glass, black strips drawn in
  // blue inside the ink layer: at night the shader keeps these dark, so the
  // words sit on clean labels in the 1-bit picture
  Item {
    parent: inkLayer
    anchors.fill: parent
    z: -1   // under the marks, which sit on one of these strips
    readonly property real pad: Math.round(lock.unit * 0.03)
    Rectangle { x: furigana.x - parent.pad; y: furigana.y; width: furigana.width + parent.pad * 2; height: furigana.height; color: "#0000ff"; visible: furigana.opacity > 0 }
    Rectangle { x: dateColumns.x + dateRight.x - parent.pad; y: dateColumns.y + dateRight.y - parent.pad; width: dateRight.width + parent.pad * 2; height: dateRight.height + parent.pad * 2; color: "#0000ff"; visible: dateColumns.opacity > 0 }
    Rectangle { x: dateColumns.x + dateLeft.x - parent.pad; y: dateColumns.y + dateLeft.y - parent.pad; width: dateLeft.width + parent.pad * 2; height: dateLeft.height + parent.pad * 2; color: "#0000ff"; visible: dateColumns.opacity > 0 }
    Rectangle { x: hints.x + jpHintText.x - parent.pad; y: hints.y + jpHintText.y; width: jpHintText.width + parent.pad * 2; height: jpHintText.height; color: "#0000ff" }
    Rectangle { x: hints.x + enHintText.x - parent.pad; y: hints.y + enHintText.y; width: enHintText.width + parent.pad * 2; height: enHintText.height; color: "#0000ff" }
    Rectangle { x: eye.x; y: eye.y; width: eye.width; height: eye.height; color: "#0000ff" }
    Rectangle { x: clockText.x - parent.pad; y: clockText.y; width: clockText.width + parent.pad * 2; height: clockText.height; color: "#0000ff" }
    Rectangle { x: marksRow.x - parent.pad; y: marksRow.y; width: marksRow.width + parent.pad * 2; height: marksRow.height; color: "#0000ff" }
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
    fragmentShader: Qt.resolvedUrl("tsukiyo-99/sky-b0ec2d4f.frag.qsb")

    property var wall: wallTexture
    property var ink: inkTexture
    property real time: lock.t
    property real dusk: lock.duskShown
    property real glow: 0.2 + 0.25 * lock.breath + Math.min(0.3, typing.cadence * 0.05)
    property real tracking: lock.tracking
    property real part: lock.part
    property real aspect: lock.screenAspect
    property real softness: Math.max(0.3, Math.log(width * lock.dpr / 1400) / Math.LN2)
    property real cell: lock.cellPx
    property real nightCell: lock.cellPx * 2
    property vector2d res: Qt.vector2d(width * lock.dpr, height * lock.dpr)
    property vector2d moonAt: Qt.vector2d(0.5, (lock.kanjiTop + lock.unit / 2) / Math.max(1, lock.height))
    property real moonSize: lock.unit / 2 / Math.max(1, lock.height)
    property vector4d rings: Qt.vector4d(lock.ringAge(0), lock.ringAge(1), lock.ringAge(2), lock.ringAge(3))
    property vector4d streak: Qt.vector4d(lock.streakFrom.x, lock.streakFrom.y, lock.streakAge, lock.streakAge < 1 ? 1 : 0)
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

  // ------------------------------------------------------------- 月 strokes
  // KanjiVG's four strokes in textbook order, in its 109 unit box
  readonly property var strokes: [
    { type: "㇓", length: 80.2, points: [34.2,16.2,35,17.2,35.5,18.3,35.7,19.5,35.8,20.7,35.8,21.9,35.8,23.1,35.8,24.4,35.8,25.6,35.8,26.8,35.9,28,35.9,29.2,35.9,30.4,35.9,31.6,35.9,32.9,36,34.1,36,35.3,36,36.5,36,37.7,36,38.9,36,40.1,36.1,41.4,36.1,42.6,36.1,43.8,36.1,45,36.1,46.2,36.1,47.4,36.1,48.6,36.1,49.9,36,51.1,36,52.3,36,53.5,36,54.7,35.9,55.9,35.9,57.1,35.8,58.4,35.8,59.6,35.7,60.8,35.6,62,35.5,63.2,35.4,64.4,35.3,65.6,35.1,66.8,35,68,34.8,69.2,34.7,70.5,34.5,71.7,34.3,72.8,34,74,33.8,75.2,33.5,76.4,33.2,77.6,32.9,78.8,32.5,79.9,32.1,81.1,31.7,82.2,31.3,83.3,30.8,84.5,30.3,85.5,29.7,86.6,29.1,87.7,28.5,88.7,27.8,89.7,27.1,90.7,26.4,91.7,25.6,92.6,24.8,93.5] },
    { type: "㇆a", length: 128.0, points: [36.2,19,37.4,18.8,38.6,18.6,39.8,18.5,41,18.3,42.2,18.1,43.4,17.9,44.6,17.7,45.8,17.6,47,17.4,48.2,17.2,49.4,17,50.6,16.8,51.8,16.6,53,16.5,54.2,16.3,55.4,16.1,56.5,15.9,57.8,15.8,58.9,15.6,60.1,15.4,61.3,15.2,62.5,15,63.7,14.8,64.9,14.7,66.1,14.5,67.3,14.3,68.5,14.1,69.7,14,70.9,13.9,72.1,14,73.2,14.4,74.1,15.2,74.7,16.3,74.9,17.5,75,18.7,75,19.9,75,21.1,75,22.3,75,23.5,75,24.7,74.9,25.9,74.9,27.1,74.9,28.4,74.9,29.6,74.9,30.8,74.9,32,74.9,33.2,74.9,34.4,74.8,35.6,74.8,36.8,74.8,38,74.8,39.2,74.8,40.4,74.8,41.6,74.8,42.9,74.8,44.1,74.8,45.3,74.8,46.5,74.7,47.7,74.7,48.9,74.7,50.1,74.7,51.3,74.7,52.5,74.7,53.7,74.7,54.9,74.7,56.1,74.7,57.4,74.7,58.6,74.7,59.8,74.6,61,74.6,62.2,74.6,63.4,74.6,64.6,74.6,65.8,74.6,67,74.6,68.2,74.6,69.4,74.6,70.6,74.6,71.8,74.5,73,74.5,74.3,74.5,75.5,74.5,76.7,74.5,77.9,74.5,79.1,74.5,80.3,74.5,81.5,74.5,82.7,74.5,83.9,74.5,85.1,74.5,86.3,74.5,87.5,74.5,88.8,74.5,90,74.4,91.2,74.2,92.4,73.9,93.5,73.3,94.6,72.2,95.1,71.1,94.9,70.1,94.2,69.1,93.4,68.3,92.6,67.4,91.7,66.6,90.8,65.8,90] },
    { type: "㇐a", length: 36.5, points: [37.2,38,38.5,37.8,39.7,37.6,40.9,37.5,42.1,37.3,43.3,37.1,44.5,37,45.7,36.8,46.9,36.6,48.1,36.5,49.3,36.3,50.5,36.2,51.7,36,52.9,35.8,54.1,35.7,55.4,35.5,56.6,35.4,57.8,35.2,59,35.1,60.2,34.9,61.4,34.8,62.6,34.6,63.8,34.5,65,34.4,66.2,34.2,67.4,34.1,68.7,34,69.9,33.8,71.1,33.7,72.3,33.6,73.5,33.5] },
    { type: "㇐a", length: 36.5, points: [37,58.2,38.2,58.1,39.4,57.9,40.6,57.8,41.8,57.6,43,57.5,44.2,57.3,45.4,57.2,46.6,57,47.9,56.9,49.1,56.7,50.3,56.6,51.5,56.4,52.7,56.3,53.9,56.1,55.1,56,56.3,55.9,57.5,55.7,58.7,55.6,59.9,55.5,61.1,55.3,62.4,55.2,63.6,55.1,64.8,54.9,66,54.8,67.2,54.7,68.4,54.6,69.6,54.5,70.8,54.4,72,54.3,73.2,54.2] }
  ]

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

  function strokeProgress(i, clock) {
    var s = schedule[i]
    var u = Math.max(0, Math.min(1, (clock - s.start) / s.dur))
    if (strokes[i].type === "㇓") return Math.pow(u, 1.35)
    return u < 0.5 ? 2 * u * u : 1 - 2 * (1 - u) * (1 - u)
  }

  // A sweep that thins out, a hook that flicks off, a press to start the rest
  function strokeWidth(type, u) {
    if (type === "㇓") return Math.max(0.18, 1.08 - 0.9 * Math.pow(u, 1.6))
    if (type === "㇆a") return u > 0.9 ? Math.max(0.2, 1 - (u - 0.9) * 8) : 1.04 - 0.1 * Math.min(1, u * 8)
    return 1.12 - 0.14 * Math.min(1, u * 5) + (u > 0.94 ? (u - 0.94) * 2 : 0)
  }

  // ------------------------------------------------------ words, on the glass
  Item {
    id: chrome
    anchors.fill: parent
    opacity: 1 - 0.3 * lock.shade
    // A soft navy shadow so the words read on a bright cloud by day; at
    // night they sit on black labels anyway
    layer.enabled: true
    layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Qt.rgba(0.02, 0.04, 0.14, 0.6); shadowBlur: 0.6; shadowVerticalOffset: 1 }

    Text {
      id: furigana
      anchors.horizontalCenter: parent.horizontalCenter
      y: lock.kanjiTop - height - Math.round(lock.unit * 0.02)
      text: "つき"
      color: lock.cInk
      opacity: lock.written ? 0.75 : 0
      Behavior on opacity { NumberAnimation { duration: 1200; easing.type: Easing.OutCubic } }
      font.family: "Klee One"
      font.pixelSize: Math.round(lock.unit * 0.075)
      font.letterSpacing: Math.round(lock.unit * 0.035)
    }

    Text {
      id: clockText
      anchors.horizontalCenter: parent.horizontalCenter
      y: lock.clockTop
      text: lock.clock("HH:mm")
      color: lock.cInk
      font.family: "Klee One"
      font.weight: Font.DemiBold
      font.pixelSize: Math.round(lock.unit * 0.22)
      font.letterSpacing: Math.round(lock.unit * 0.02)
    }

    // The date down the side: 九月二十九日, 火曜日の夜
    Row {
      id: dateColumns
      // Just outside the rim of the eclipse at night, next to 月 by day
      x: Math.round(lock.width / 2 + (lock.isNight ? lock.unit * 0.54 * 1.2 + lock.unit * 0.12 : lock.unit / 2 + lock.unit * 0.06))
      y: lock.kanjiTop + Math.round(lock.unit * 0.08)
      spacing: Math.round(lock.unit * 0.035)
      layoutDirection: Qt.RightToLeft
      opacity: lock.written ? 0.9 : 0
      Behavior on opacity { NumberAnimation { duration: 1600; easing.type: Easing.OutCubic } }

      Tategaki { id: dateRight; text: lock.jpDate; size: Math.round(lock.unit * 0.085); color: lock.cInk }
      Tategaki { id: dateLeft; text: lock.jpDay; size: Math.round(lock.unit * 0.085); color: lock.cInk; opacity: 0.75; topPadding: Math.round(lock.unit * 0.09) }
    }

    EyeButton {
      id: eye
      lock: lock
      x: Math.round((lock.width + marksRow.width) / 2 + lock.unit * 0.03)
      y: lock.marksTop + (marksRow.height - height) / 2
      size: Math.round(lock.unit * 0.07)
    }

    Column {
      id: hints
      anchors.horizontalCenter: parent.horizontalCenter
      y: lock.hintsTop
      spacing: Math.round(lock.unit * 0.015)
      opacity: lock.snapshotMode ? 0 : 1

      Text {
        id: jpHintText
        anchors.horizontalCenter: parent.horizontalCenter
        text: lock.jpHint
        color: lock.errorState ? Color.lock.textError : lock.cInk
        opacity: 0.9
        font.family: "Klee One"
        font.pixelSize: Math.round(lock.unit * 0.06)
        font.letterSpacing: Math.round(lock.unit * 0.01)
      }
      Text {
        id: enHintText
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

  // With the moon out: "the moon is beautiful, isn't it"
  readonly property string jpHint: authenticatingPassword ? "確認中…"
    : (errorState ? "もう一度どうぞ"
    : (fido2Active ? "キーに触れてください"
    : (isNight ? "月が綺麗ですね" : "おかえりなさい")))

  readonly property string badges: (capsLock && showCapsBadge ? "CAPS  ·  " : "")
    + ((foreignLayout || layoutSwitchable) && showLayoutBadge && keyboardLayout.length > 0 ? keyboardLayout + "  ·  " : "")
  readonly property string enHint: badges + (authenticatingPassword ? tr("Checking…")
    : (errorState ? failureMessage
    : (fido2Active ? (fido2Status.length > 0 ? fido2Status : tr("Waiting for your key…"))
    : (fingerprintConfigured ? fingerprintHint(tr("Type your password or touch the sensor")) : tr("Type your password")))))

  // ------------------------------------------------------------ the marks
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
      lock.ring()
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
      trackingRoll.restart()
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
        chrome.opacity = 1
      }
    }
  }

  // The right password: the picture dissolves along the slant into the
  // wallpaper, pixel by pixel
  SequentialAnimation {
    id: unlocking
    ScriptAction { script: lock.tell("unlock") }
    ParallelAnimation {
      NumberAnimation { target: lock; property: "part"; from: 0; to: 1; duration: 1500; easing.type: Easing.InOutSine }
      NumberAnimation { target: chrome; property: "opacity"; to: 0; duration: 450; easing.type: Easing.OutCubic }
    }
    PauseAnimation { duration: 150 }
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
}
