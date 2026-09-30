.pragma library
// Memory shared by every screen of one lock, for the Hikari and Tsukiyo designs.
//
// A monitor that disconnects while it sleeps (many DisplayPort monitors do)
// comes back as a new lock surface with a fresh copy of the design. Without
// this it would start the day over. A design joins with begin() once the lock
// service says the session really is locked (previews and the explorer's
// cards never join), keeps the memory alive while it runs, and clears it when
// the unlock plays.
//
// With one monitor there can be a stretch with no copy running at all. When a
// copy then appears it is still the same lock, unless the last thing that
// happened was a password check (the lock ended in an unlock the design did
// not see, with reduce motion for one) or it has been gone for half a day.

var started = 0     // when this lock began (ms since the epoch)
var seen = 0        // the last moment any screen of it was alive
var returned = 0    // how far typing has brought the day back, 0..1
var checked = 0     // when a password was last checked

var LONG = 12 * 3600 * 1000
var AFTER_CHECK = 15000   // a check this close to the last sign of life ended the lock

function sameLock(now) {
    if (started === 0) return false
    if (now - seen > LONG) return false
    if (checked > 0 && checked >= seen - AFTER_CHECK) return false
    return true
}

function begin(now) {
    if (!sameLock(now)) {
        started = now
        returned = 0
        checked = 0
    }
    seen = now
    return started
}

function alive(now) {
    seen = now
}

function checking(now) {
    checked = now
}

function end() {
    started = 0
    seen = 0
    returned = 0
    checked = 0
}
