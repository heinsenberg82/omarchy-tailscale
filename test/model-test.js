// Unit tests for Model.js — the pure parsing layer.
//
// Model.js is deliberately free of QML imports and carries a `module.exports`
// guard, so the parsing that drives the panel can be exercised in plain node
// without a running shell. Fixtures are synthetic; no real tailnet data.
//
//   node test/model-test.js

const fs = require("fs")
const path = require("path")
const M = require("../Model.js")

const FIXTURES = path.join(__dirname, "fixtures")
const statusRaw = fs.readFileSync(path.join(FIXTURES, "status.json"), "utf8")
const accountsRaw = fs.readFileSync(path.join(FIXTURES, "accounts.json"), "utf8")

let passed = 0
const failures = []

function check(name, actual, expected) {
  const a = JSON.stringify(actual)
  const e = JSON.stringify(expected)
  if (a === e) {
    passed++
  } else {
    failures.push(`${name}\n    expected: ${e}\n    actual:   ${a}`)
  }
}

function ok(name, value) {
  check(name, value === true, true)
}

// --- string helpers ---------------------------------------------------------

check("cleanDnsName strips the trailing dot", M.cleanDnsName("host.example.ts.net."), "host.example.ts.net")
check("cleanDnsName leaves a clean name alone", M.cleanDnsName("host.example.ts.net"), "host.example.ts.net")
check("cleanDnsName on empty", M.cleanDnsName(undefined), "")
check("shortDnsName takes the first label", M.shortDnsName("host.example.ts.net."), "host")
check("displayHostName prefers the host name", M.displayHostName("beacon", "beacon.example.ts.net."), "beacon")
check("displayHostName falls back past localhost", M.displayHostName("localhost", "edge-node.example.ts.net."), "edge-node")
check("displayHostName with nothing usable", M.displayHostName("", ""), "Unknown")

// --- IP filtering -----------------------------------------------------------

check("filterIPv4 keeps only the 100.x CGNAT range",
  M.filterIPv4(["100.64.0.3", "10.0.0.7", "192.168.1.50"]), ["100.64.0.3"])
check("filterIPv6 keeps only the Tailscale ULA prefix",
  M.filterIPv6(["fd7a:115c:a1e0::3", "fe80::1", "2001:db8::1"]), ["fd7a:115c:a1e0::3"])
check("filterIPv4 tolerates a missing list", M.filterIPv4(undefined), [])

// --- OS icons ---------------------------------------------------------------

check("osIcon linux", M.osIcon("linux"), "\u{f033d}")
check("osIcon macOS is case-insensitive", M.osIcon("macOS"), M.osIcon("macos"))
check("osIcon falls back for something unknown", M.osIcon("plan9"), M.osIcon(""))

// --- capabilities -----------------------------------------------------------

ok("hasFileSharing reads CapMap",
  M.hasFileSharing({ CapMap: { "https://tailscale.com/cap/file-sharing": [] } }))
ok("hasFileSharing reads the legacy Capabilities list",
  M.hasFileSharing({ Capabilities: ["https://tailscale.com/cap/file-sharing"] }))
check("hasFileSharing is false when absent", M.hasFileSharing({}), false)

ok("isTaildropTarget trusts TaildropTarget == 1", M.isTaildropTarget({ TaildropTarget: 1 }, "999"))
check("isTaildropTarget rejects a non-1 grade", M.isTaildropTarget({ TaildropTarget: 2, UserID: "1001" }, "1001"), false)
ok("isTaildropTarget falls back to same owner", M.isTaildropTarget({ UserID: "1001" }, "1001"))
check("isTaildropTarget rejects another owner", M.isTaildropTarget({ UserID: "2002" }, "1001"), false)

// --- login ------------------------------------------------------------------

check("loginPlan hands back an auth URL when one is offered",
  M.loginPlan(true, "https://login.example.com/a/abc"),
  { authUrl: "https://login.example.com/a/abc", command: [] })
check("loginPlan falls back to `tailscale up`",
  M.loginPlan(false, ""), { authUrl: "", command: ["tailscale", "up"] })
check("loginPlan ignores a non-http URL",
  M.loginPlan(true, "file:///etc/passwd"), { authUrl: "", command: ["tailscale", "up"] })

// --- parseStatus: this device ----------------------------------------------

const s = M.parseStatus(statusRaw)

ok("parseStatus succeeds", s.ok)
check("parseStatus is not unavailable", s.unavailable, false)
ok("running when BackendState is Running", s.running)
check("needsLogin is false while running", s.needsLogin, false)
check("selfName", s.selfName, "workstation")
check("selfOs is carried through for the THIS DEVICE row", s.selfOs, "linux")
check("selfIp picks the CGNAT address, not the LAN one", s.selfIp, "100.64.0.1")
check("selfDnsName is cleaned", s.selfDnsName, "workstation.tailnet-demo.ts.net")
check("selfUserId", s.selfUserId, "1001")
ok("fileSharing detected from Self.CapMap", s.fileSharing)

// --- parseStatus: machines --------------------------------------------------

const names = s.peers.map(p => p.HostName)

check("online machines come first, then offline; alphabetical within each group",
  names, ["beacon", "edge-node", "laptop", "aardvark"])
check("the offline machine is listed rather than dropped",
  s.peers.filter(p => p.Online === false).map(p => p.HostName), ["aardvark"])
check("a Mullvad node is never a machine",
  names.filter(n => n.indexOf("mullvad") !== -1 || n.indexOf("se-mma") !== -1), [])
check("a peer calling itself localhost is named from its DNS name",
  names.indexOf("edge-node") !== -1, true)

const laptop = s.peers.find(p => p.HostName === "laptop")
check("peer IPv4 is filtered to the tailnet address", laptop.TailscaleIPs, ["100.64.0.3"])
check("peer IPv6 is split out", laptop.TailscaleIPv6, ["fd7a:115c:a1e0::3"])
check("peer OS is preserved for the icon", laptop.OS, "macOS")

// --- parseStatus: exit nodes ------------------------------------------------

const exitNames = s.exitNodes.map(p => p.HostName)
check("only online machines offering exit are exit nodes", exitNames, ["beacon"])
check("an offline machine is excluded even though it offers exit",
  exitNames.indexOf("aardvark"), -1)

// --- parseStatus: degraded input -------------------------------------------

check("empty status means unavailable, not an error", M.parseStatus("").unavailable, true)
check("empty status is still ok", M.parseStatus("").ok, true)
check("unparseable status reports failure", M.parseStatus("not json").ok, false)

const loggedOut = M.parseStatus(JSON.stringify({ BackendState: "NeedsLogin", AuthURL: "https://login.example.com/a/x", Self: {}, Peer: {} }))
ok("NeedsLogin is surfaced", loggedOut.needsLogin)
check("no machines when logged out", loggedOut.peers, [])

// --- parseAccounts ----------------------------------------------------------

const a = M.parseAccounts(accountsRaw)
check("both accounts are parsed", a.accounts.length, 2)
check("the selected account id", a.selectedAccountId, "aaaa")
check("the selected account label is what the ACCOUNT row shows",
  a.selectedAccountLabel, "tailnet-demo.ts.net")
check("no accounts from empty input", M.parseAccounts("").accounts, [])
check("no accounts from garbage input", M.parseAccounts("{{{").accounts, [])

check("accountLabel prefers a nickname",
  M.accountLabel({ nickname: "Work", tailnet: "t.ts.net", account: "a@example.com" }), "Work")
check("accountLabel falls back to the tailnet",
  M.accountLabel({ tailnet: "t.ts.net", account: "a@example.com" }), "t.ts.net")
check("accountLabel with nothing", M.accountLabel(null), "Unknown account")

// --- Taildrop inbox ---------------------------------------------------------

const waitingRaw = JSON.stringify([
  { Name: "notes.pdf", Size: 1536 },
  { Name: "photo.jpg", Size: 2 * 1024 * 1024 },
  { Name: "", Size: 10 }
])
check("parseWaitingFiles reads names and sizes, skipping nameless entries",
  M.parseWaitingFiles(waitingRaw),
  [{ name: "notes.pdf", size: 1536 }, { name: "photo.jpg", size: 2097152 }])
check("parseWaitingFiles reads `null` as an empty inbox", M.parseWaitingFiles("null\n"), [])
check("parseWaitingFiles cannot tell from empty output", M.parseWaitingFiles(""), null)
check("parseWaitingFiles cannot tell from garbage", M.parseWaitingFiles("{{{"), null)
check("parseWaitingFiles rejects a non-list", M.parseWaitingFiles("{\"Name\":\"x\"}"), null)

check("formatBytes keeps bytes whole", M.formatBytes(512), "512 B")
check("formatBytes gives small values one decimal", M.formatBytes(1536), "1.5 KB")
check("formatBytes drops the decimal from ten up", M.formatBytes(12 * 1024 * 1024), "12 MB")
check("formatBytes tolerates nonsense", M.formatBytes(undefined), "0 B")

check("waitingFilesSummary on an empty inbox", M.waitingFilesSummary([]), "No files waiting")
check("waitingFilesSummary names a single file",
  M.waitingFilesSummary([{ name: "notes.pdf", size: 1536 }]), "notes.pdf · 1.5 KB")
check("waitingFilesSummary counts several files and adds up their size",
  M.waitingFilesSummary(M.parseWaitingFiles(waitingRaw)), "2 files · 2.0 MB")

const firstPoll = M.diffWaitingFiles([{ name: "a.txt", size: 1 }, { name: "b.txt", size: 2 }], {})
check("diffWaitingFiles: everything is fresh the first time",
  firstPoll.fresh.map(f => f.name), ["a.txt", "b.txt"])
const secondPoll = M.diffWaitingFiles([{ name: "a.txt", size: 1 }, { name: "b.txt", size: 2 }, { name: "c.txt", size: 3 }], firstPoll.seen)
check("diffWaitingFiles: only the new arrival is fresh", secondPoll.fresh.map(f => f.name), ["c.txt"])
const afterSave = M.diffWaitingFiles([], secondPoll.seen)
check("diffWaitingFiles: an emptied inbox forgets what it saw", afterSave.seen, {})
check("diffWaitingFiles: a name that comes back after saving is fresh again",
  M.diffWaitingFiles([{ name: "a.txt", size: 1 }], afterSave.seen).fresh.length, 1)
check("diffWaitingFiles tolerates a missing list", M.diffWaitingFiles(undefined, undefined), { fresh: [], seen: {} })

check("waitingFilesNotice names a single file",
  M.waitingFilesNotice([{ name: "notes.pdf", size: 1 }]),
  { headline: "Received notes.pdf", body: "Waiting in the Taildrop inbox. Click to save it" })
check("waitingFilesNotice counts several files",
  M.waitingFilesNotice([{ name: "a", size: 1 }, { name: "b", size: 1 }]).headline, "Received 2 files")

check("parseUnitState: enabled and running",
  M.parseUnitState("LoadState=loaded\nActiveState=active\nUnitFileState=enabled\n"),
  { loaded: true, enabled: true, active: true })
check("parseUnitState: disabled and stopped",
  M.parseUnitState("LoadState=loaded\nActiveState=inactive\nUnitFileState=disabled\n"),
  { loaded: true, enabled: false, active: false })
check("parseUnitState: started by hand while disabled",
  M.parseUnitState("LoadState=loaded\nActiveState=active\nUnitFileState=disabled\n"),
  { loaded: true, enabled: false, active: true })
check("parseUnitState: unit not installed",
  M.parseUnitState("LoadState=not-found\nActiveState=inactive\nUnitFileState=\n"),
  { loaded: false, enabled: false, active: false })
check("parseUnitState: masked is not enabled",
  M.parseUnitState("LoadState=masked\nActiveState=inactive\nUnitFileState=masked\n"),
  { loaded: false, enabled: false, active: false })

const getOutput = [
  "wrote notes.pdf as /home/me/Saved as/notes.pdf (1536 bytes)",
  "wrote a as b.txt as /home/me/Saved as/a as b (1).txt (3 bytes)",
  "moved 2/2 files",
  ""
].join("\n")
check("parseSavedFiles anchors on the target directory, even through \" as \"",
  M.parseSavedFiles(getOutput, "/home/me/Saved as"),
  ["/home/me/Saved as/notes.pdf", "/home/me/Saved as/a as b (1).txt"])
check("parseSavedFiles ignores a trailing slash on the directory",
  M.parseSavedFiles(getOutput, "/home/me/Saved as/").length, 2)
check("parseSavedFiles on an empty inbox", M.parseSavedFiles("moved 0/0 files\n", "/tmp"), [])

check("tildePath shortens paths under home", M.tildePath("/home/me/Downloads", "/home/me"), "~/Downloads")
check("tildePath on home itself", M.tildePath("/home/me", "/home/me/"), "~")
check("tildePath leaves a lookalike prefix alone", M.tildePath("/home/meadow/x", "/home/me"), "/home/meadow/x")
check("tildePath leaves paths outside home alone", M.tildePath("/srv/drop", "/home/me"), "/srv/drop")

check("savedFilesNotice for one file opens the file",
  M.savedFilesNotice(["/home/me/Downloads/notes.pdf"], "/home/me/Downloads", "/home/me"),
  { headline: "Saved notes.pdf", body: "to ~/Downloads", open: "/home/me/Downloads/notes.pdf" })
check("savedFilesNotice for several files opens the folder",
  M.savedFilesNotice(["/srv/a", "/srv/b"], "/srv", "/home/me"),
  { headline: "Saved 2 files", body: "to /srv", open: "/srv" })
check("savedFilesNotice when nothing was waiting",
  M.savedFilesNotice([], "/srv", "/home/me").headline, "No Taildrop files waiting")

// --- report -----------------------------------------------------------------

if (failures.length > 0) {
  console.error(`\n${failures.length} of ${passed + failures.length} assertions failed:\n`)
  failures.forEach(f => console.error(`  ✗ ${f}\n`))
  process.exit(1)
}

console.log(`Model.js: ${passed} assertions passed.`)
