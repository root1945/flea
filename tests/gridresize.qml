//@ pragma ShellId flea-gridresize-test

import QtQuick
import Quickshell
import "flea" as Flea

// gridresize: after a Grid shrink, tiles that were off-screen at the resize draw names and take a click.
// tests/gridresize.sh drives it. Sample output: "GRIDRESIZE PASS checks=12"
ShellRoot {
    id: root

    property var failures: []
    property int checks: 0
    property int rowCount: 200
    property int pastIndex: -1
    property int wideColumns: 0
    property int wideLast: 0
    property int polls: 0
    property int stage: 0

    function pad(i) {
        var n = String(i)
        while (n.length < 3) n = "0" + n
        return n
    }
    function buildRows() {
        var rows = []
        for (var i = 0; i < root.rowCount; i++)
            rows.push({ n: "item" + root.pad(i) + ".txt", d: false, i: "text-x-generic",
                p: 420, s: 13, m: 1758835200, t: false, k: 0, v: 0 })
        return rows
    }

    Component {
        id: backendStub
        QtObject {
            property int heldListing: 1
            property int windowCalls: 0
            function peek(path, size, hidden) {}
            function thumb(rows, cacheOnly) {}
            function thumbcancel(rows) {}
            function dirsize(rows) {}
            function dirsizecancel() {}
            function window(start, count) { windowCalls += 1 }
        }
    }

    Component {
        id: paneStub
        QtObject {
            property string path: "/probe"
            property var rows: []
            property var shown: null
            property int shownTotal: 200
            property int total: 200
            property int held: 0
            property int cursorIndex: 0
            property int renamingIndex: -1
            property string renameError: ""
            property bool renamePending: false
            property bool paneFocused: true
            property bool dualMode: false
            property var clipboard: ({ paths: [], moving: false })
            property var selected: ({})
            property var thumbState: ({ file: {}, order: [] })
            property var dirSizeState: ({ file: {}, order: [] })
            property string searchMode: ""
            property string searchQuery: ""
            property string filterQuery: ""
            property bool filterTyping: false
            property var selectionBand: null
            property var sidebar: null
            property int previewIndex: -1
            property bool storageKnown: true
            property string storageClass: ""
            property bool listInFlight: false
            property string listingState: "ready"
            property var statusBar: null
            property int firstSettleMs: 70
            property int settleMs: 120
            property int coalesceMs: 16
            property int refetchMargin: 25
            property int buffer: 150
            property int windowSize: 35
            property var backend: null
            property var swap: ({ searchWarm: false, answeredQuery: "" })
            function join(base, name) { return String(base) + "/" + String(name) }
            function rowFor(index) { var o = index - held; return (o >= 0 && o < rows.length) ? rows[o] : null }
            function isSelected(index) { return selected[index] === true }
            function commitRename(newName) {}
            function pressSlowClick() {}
            function slowClickWasSole(index) { return false }
            function armSlowClick(index, modifiers, dragging, wasSole) {}
            function cancelSlowClick() {}
        }
    }

    Component {
        id: menuStub
        QtObject {
            function close() {}
            function openBackground(point) {}
        }
    }

    property var stubBackend: backendStub.createObject(root)
    property var stubMenu: menuStub.createObject(root)
    property var stubPane: paneStub.createObject(root, { backend: root.stubBackend, rows: root.buildRows() })

    FloatingWindow {
        implicitWidth: 1100
        implicitHeight: 700
        color: Flea.Theme.color.background

        Flea.GridArea {
            id: grid
            x: 20
            y: 20
            width: 900
            height: 480
            pane: root.stubPane
            menu: root.stubMenu
        }
    }

    Timer {
        id: step
        property var next: null
        interval: 80
        repeat: false
        onTriggered: step.next()
    }
    Timer {
        id: watchdog
        interval: 15000
        repeat: false
        onTriggered: { root.fail("timed out at stage " + root.stage); root.report() }
    }

    Component.onCompleted: { watchdog.start(); step.next = root.waitWide; step.start() }

    function fail(text) { root.failures.push(text) }
    function check(name, ok, detail) {
        root.checks += 1
        if (!ok) root.fail(name + (detail ? " " + detail : ""))
    }

    function laidOut() {
        var out = []
        var kids = grid.contentItem.children
        for (var i = 0; i < kids.length; i++) {
            var t = kids[i]
            if (t.index !== undefined && t.prebuilt !== true && t.parent === grid.contentItem)
                out.push(t)
        }
        return out
    }

    function overlappingPooled() {
        var y0 = grid.contentY, y1 = grid.contentY + grid.height, n = 0
        var kids = grid.contentItem.children
        for (var i = 0; i < kids.length; i++) {
            var t = kids[i]
            if (t.index === undefined || t.prebuilt === true || t.pooled !== true) continue
            if (t.parent !== grid.contentItem) continue
            if (t.y + t.height > y0 && t.y < y1) n++
        }
        return n
    }

    function parentedPooled() {
        var n = 0, kids = grid.contentItem.children
        for (var i = 0; i < kids.length; i++) {
            var t = kids[i]
            if (t.index !== undefined && t.prebuilt !== true && t.pooled === true && t.parent === grid.contentItem)
                n++
        }
        return n
    }

    function inspectViewport(label) {
        var range = grid.visibleRange()
        var seen = 0
        for (var i = Math.max(0, range.first); i <= range.last; i++) {
            var t = grid.itemAtIndex(i)
            if (t === null || t.visible === false) continue
            seen += 1
            var want = root.stubPane.rows[i].n
            root.check(label + " tile " + i + " live", t.pooled !== true, "pooled=" + t.pooled)
            root.check(label + " tile " + i + " listing", t.listingIndex === i, "listingIndex=" + t.listingIndex)
            root.check(label + " tile " + i + " name", t.row && t.row.n === want, t.row ? t.row.n : "nothing")
            var cx = t.x + t.width / 2
            var cy = t.y + Math.min(24, t.height / 4)
            root.check(label + " tile " + i + " click", grid.tileAt(cx, cy) === i, "tileAt=" + grid.tileAt(cx, cy))
        }
        var overlap = root.overlappingPooled()
        root.check(label + " no pooled overlay", overlap === 0, "overlay=" + overlap)
        root.check(label + " saw tiles", seen > 0, "seen=" + seen + " range=" + range.first + ".." + range.last + " y=" + grid.contentY)
        return seen
    }

    function showIndex(index) {
        var row = Math.floor(index / Math.max(1, grid.columns))
        var y = grid.originY + row * grid.cellHeightPx
        var maxY = Math.max(grid.originY, grid.originY + grid.contentHeight + grid.topMargin + grid.bottomMargin - grid.height)
        grid.contentY = Math.min(y, maxY)
        grid.forceLayout()
    }

    function dumpTiles(label) {
        var kids = grid.contentItem.children, n = 0, pooled = 0, liveNamed = 0
        for (var i = 0; i < kids.length; i++) {
            var t = kids[i]
            if (t.index === undefined) continue
            n += 1
            if (t.pooled === true) pooled += 1
            if (t.pooled !== true && t.row && t.row.n) liveNamed += 1
        }
        console.log("GRIDRESIZE DUMP " + label + " n=" + n + " pooled=" + pooled + " named=" + liveNamed
            + " cols=" + grid.columns + " y=" + grid.contentY + " origin=" + grid.originY
            + " range=" + grid.visibleRange().first + ".." + grid.visibleRange().last
            + " at0=" + (grid.itemAtIndex(0) !== null) + " atPast=" + (grid.itemAtIndex(root.pastIndex) !== null))
    }

    function waitWide() {
        root.stage = 1
        if (grid.columns < 2 || grid.count === 0 || grid.itemAtIndex(0) === null) {
            root.polls += 1
            if (root.polls > 40) { root.fail("wide grid never laid out columns=" + grid.columns + " count=" + grid.count); root.report(); return }
            step.start()
            return
        }
        root.polls = 0
        root.wideColumns = grid.columns
        root.wideLast = grid.visibleRange().last
        root.pastIndex = Math.min(root.rowCount - 1, root.wideLast + grid.columns * 3 + 1)
        if (root.pastIndex <= root.wideLast) {
            root.fail("fixture has no off-screen row last=" + root.wideLast + " past=" + root.pastIndex)
            root.report()
            return
        }
        root.check("wide has columns", root.wideColumns >= 2, "columns=" + root.wideColumns)
        root.inspectViewport("wide")
        step.next = root.shrinkBoth
        step.start()
    }

    function shrinkBoth() {
        root.stage = 2
        grid.width = 400
        grid.height = 260
        step.next = root.waitShrink
        step.start()
    }

    function waitShrink() {
        root.stage = 3
        if (grid.columns === root.wideColumns) {
            root.polls += 1
            if (root.polls > 20) { root.fail("shrink kept columns " + grid.columns); root.report(); return }
            step.start()
            return
        }
        root.polls = 0
        root.check("shrink dropped columns", grid.columns < root.wideColumns, "now=" + grid.columns)
        root.check("shrunk parented pooled", root.parentedPooled() === 0, "pooled=" + root.parentedPooled())
        root.dumpTiles("shrunk")
        root.inspectViewport("shrunk-top")
        root.showIndex(root.pastIndex)
        step.next = root.waitScrolled
        step.start()
    }

    function waitScrolled() {
        root.stage = 4
        var t = grid.itemAtIndex(root.pastIndex)
        if (t === null) {
            root.polls += 1
            if (root.polls > 30) { root.fail("scroll never built tile " + root.pastIndex); root.report(); return }
            root.showIndex(root.pastIndex)
            step.start()
            return
        }
        root.polls = 0
        root.dumpTiles("scrolled")
        var want = root.stubPane.rows[root.pastIndex].n
        root.check("scrolled tile live", t.pooled !== true, "pooled=" + t.pooled)
        root.check("scrolled tile listing", t.listingIndex === root.pastIndex, "listingIndex=" + t.listingIndex)
        root.check("scrolled tile name", t.row && t.row.n === want, t.row ? t.row.n : "nothing")
        var cx = t.x + t.width / 2
        var cy = t.y + Math.min(24, t.height / 4)
        root.check("scrolled tile click", grid.tileAt(cx, cy) === root.pastIndex, "tileAt=" + grid.tileAt(cx, cy))
        root.inspectViewport("scrolled")
        root.heightOnly()
    }

    function heightOnly() {
        root.stage = 5
        grid.contentY = 0
        grid.forceLayout()
        grid.width = 900
        grid.height = 480
        step.next = root.waitWideAgain
        step.start()
    }

    function waitWideAgain() {
        root.stage = 6
        if (grid.columns < root.wideColumns || grid.itemAtIndex(0) === null) {
            root.polls += 1
            if (root.polls > 30) { root.dumpTiles("restore"); root.fail("wide restore never laid out"); root.report(); return }
            grid.contentY = 0
            grid.forceLayout()
            step.start()
            return
        }
        root.polls = 0
        var cols = grid.columns
        root.wideLast = grid.visibleRange().last
        root.pastIndex = Math.min(root.rowCount - 1, root.wideLast + cols * 3 + 1)
        grid.height = 240
        step.next = function () {
            root.check("height-only kept columns", grid.columns === cols, "now=" + grid.columns)
            root.check("height parented pooled", root.parentedPooled() === 0, "pooled=" + root.parentedPooled())
            root.showIndex(root.pastIndex)
            step.next = root.waitHeightScroll
            step.start()
        }
        step.start()
    }

    function waitHeightScroll() {
        root.stage = 7
        var t = grid.itemAtIndex(root.pastIndex)
        if (t === null) {
            root.polls += 1
            if (root.polls > 30) { root.fail("height-only scroll never built tile " + root.pastIndex); root.report(); return }
            root.showIndex(root.pastIndex)
            step.start()
            return
        }
        var want = root.stubPane.rows[root.pastIndex].n
        root.check("height tile live", t.pooled !== true, "pooled=" + t.pooled)
        root.check("height tile listing", t.listingIndex === root.pastIndex, "listingIndex=" + t.listingIndex)
        root.check("height tile name", t.row && t.row.n === want, t.row ? t.row.n : "nothing")
        var cx = t.x + t.width / 2
        var cy = t.y + Math.min(24, t.height / 4)
        root.check("height tile click", grid.tileAt(cx, cy) === root.pastIndex, "tileAt=" + grid.tileAt(cx, cy))
        root.inspectViewport("height")
        root.report()
    }

    function report() {
        watchdog.stop()
        step.stop()
        if (root.failures.length === 0)
            console.log("GRIDRESIZE PASS checks=" + root.checks)
        for (var f = 0; f < root.failures.length; f++)
            console.log("GRIDRESIZE FAIL " + root.failures[f])
        Quickshell.execDetached(["kill", String(Quickshell.processId)])
    }
}
