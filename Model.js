function filterIPv4(ips) {
  var result = []
  if (!ips || typeof ips.length !== "number") return result
  for (var i = 0; i < ips.length; i++) {
    var ip = String(ips[i] || "")
    if (/^100\./.test(ip)) result.push(ip)
  }
  return result
}

function filterIPv6(ips) {
  var result = []
  if (!ips || typeof ips.length !== "number") return result
  for (var i = 0; i < ips.length; i++) {
    var ip = String(ips[i] || "")
    if (/^fd7a:115c:a1e0:/i.test(ip)) result.push(ip)
  }
  return result
}

function cleanDnsName(name) {
  var value = String(name || "")
  return value.charAt(value.length - 1) === "." ? value.slice(0, -1) : value
}

function shortDnsName(name) {
  var clean = cleanDnsName(name)
  if (clean === "") return ""
  return clean.split(".")[0] || clean
}

function displayHostName(hostName, dnsName) {
  var host = String(hostName || "")
  if (host !== "" && host.toLowerCase() !== "localhost") return host
  return shortDnsName(dnsName) || host || "Unknown"
}

function isMullvadHost(name) {
  var value = String(name || "").toLowerCase()
  var suffix = ".mullvad.ts.net"
  return value.length > suffix.length && value.indexOf(suffix) === value.length - suffix.length
}

function isMullvadPeer(peer) {
  var hostName = String((peer && peer.HostName) || "")
  var dnsName = cleanDnsName((peer && peer.DNSName) || "")
  return isMullvadHost(dnsName) || isMullvadHost(hostName)
}

function osIcon(os) {
  var value = String(os || "").toLowerCase()
  if (value === "linux") return "󰌽"
  if (value === "macos" || value === "ios") return "󰀵"
  if (value === "windows") return "󰍲"
  if (value === "android") return "󰀲"
  if (value === "mullvad") return "󰖂"
  return "󰟀"
}

function accountLabel(account) {
  if (!account) return "Unknown account"
  if (account.nickname) return String(account.nickname)
  if (account.tailnet) return String(account.tailnet)
  if (account.account) return String(account.account)
  return String(account.id || "Unknown account")
}

function loginPlan(needsLogin, authUrl) {
  var url = String(authUrl || "").trim()
  if (needsLogin === true && /^https?:\/\//.test(url)) {
    return { authUrl: url, command: [] }
  }
  return { authUrl: "", command: ["tailscale", "up"] }
}

// Taildrop is a tailnet feature the admin can turn off, so the button for it
// only makes sense when this profile actually carries the capability.
function hasFileSharing(self) {
  var capability = "https://tailscale.com/cap/file-sharing"
  var capMap = (self && self.CapMap) || null
  if (capMap && capMap[capability] !== undefined) return true
  var capabilities = (self && self.Capabilities) || []
  for (var i = 0; i < capabilities.length; i++) {
    if (String(capabilities[i]) === capability) return true
  }
  return false
}

// Tailscale grades every peer itself — offline, wrong owner, an OS without
// Taildrop, no peer API — so take its word when the status carries one, and
// fall back to same-owner for daemons too old to say.
function isTaildropTarget(peer, selfUserId) {
  var target = peer && peer.TaildropTarget
  if (typeof target === "number" && target !== 0) return target === 1
  var owner = String((peer && peer.UserID) || "")
  return owner !== "" && owner === String(selfUserId || "")
}

function peerFromStatus(id, peer) {
  return {
    id: id,
    HostName: displayHostName(peer.HostName, peer.DNSName),
    UserID: String(peer.UserID || ""),
    TaildropTarget: typeof peer.TaildropTarget === "number" ? peer.TaildropTarget : 0,
    DNSName: cleanDnsName(peer.DNSName),
    DisplayName: displayHostName(peer.HostName, peer.DNSName),
    TailscaleIPs: filterIPv4(peer.TailscaleIPs || []),
    TailscaleIPv6: filterIPv6(peer.TailscaleIPs || []),
    Online: peer.Online === true,
    OS: String(peer.OS || ""),
    Tags: peer.Tags || [],
    ExitNodeOption: peer.ExitNodeOption === true,
    ExitNode: peer.ExitNode === true,
    Mullvad: isMullvadPeer(peer)
  }
}

function sliceTableColumn(line, start, end) {
  var text = String(line || "")
  if (start < 0 || start >= text.length) return ""
  if (end < 0) return text.substring(start).trim()
  return text.substring(start, Math.min(end, text.length)).trim()
}

function parseExitNodeList(raw) {
  var lines = String(raw || "").split(/\r?\n/)
  var header = ""
  var headerIndex = -1
  for (var i = 0; i < lines.length; i++) {
    if (/^\s*IP\s+HOSTNAME\s+COUNTRY\s+CITY\s+STATUS\s*$/.test(lines[i])) {
      header = lines[i]
      headerIndex = i
      break
    }
  }
  if (headerIndex === -1) return []

  var ipStart = header.indexOf("IP")
  var hostStart = header.indexOf("HOSTNAME")
  var countryStart = header.indexOf("COUNTRY")
  var cityStart = header.indexOf("CITY")
  var statusStart = header.indexOf("STATUS")
  var byHost = {}

  for (var j = headerIndex + 1; j < lines.length; j++) {
    var line = lines[j]
    if (/^\s*$/.test(line) || /^\s*#/.test(line)) continue

    var ip = sliceTableColumn(line, ipStart, hostStart)
    var host = sliceTableColumn(line, hostStart, countryStart)
    var country = sliceTableColumn(line, countryStart, cityStart)
    var city = sliceTableColumn(line, cityStart, statusStart)
    var status = sliceTableColumn(line, statusStart, -1)
    if (!isMullvadHost(host)) continue

    byHost[host] = {
      id: "mullvad:" + host,
      HostName: host,
      DNSName: host,
      DisplayName: (city && city !== "Any" ? city + ", " : "") + country,
      TailscaleIPs: ip ? [ip] : [],
      TailscaleIPv6: [],
      Online: true,
      OS: "mullvad",
      Tags: [],
      ExitNodeOption: true,
      ExitNode: status !== "" && status !== "-",
      Mullvad: true,
      Country: country,
      City: city,
      Status: status
    }
  }

  var result = []
  for (var hostName in byHost) result.push(byHost[hostName])
  result.sort(function(a, b) {
    var countryCompare = String(a.Country).localeCompare(String(b.Country))
    if (countryCompare !== 0) return countryCompare
    return String(a.DisplayName).localeCompare(String(b.DisplayName))
  })
  return result
}

function mullvadRegionOptions(nodes) {
  var byRegion = {}
  var values = Array.isArray(nodes) ? nodes : []
  for (var i = 0; i < values.length; i++) {
    var node = values[i] || {}
    if (node.Mullvad !== true) continue
    var country = String(node.Country || "").trim()
    var city = String(node.City || "").trim()
    if (country === "") continue
    if (city === "" || city === "Any") continue

    var key = country + "\n" + city
    if (byRegion[key]) continue

    var option = {}
    for (var propertyName in node) option[propertyName] = node[propertyName]
    option.id = "mullvad-region:" + key
    option.DisplayName = city + ", " + country
    option.Country = country
    option.City = city
    option.MullvadRegion = true
    byRegion[key] = option
  }

  var result = []
  for (var name in byRegion) result.push(byRegion[name])
  result.sort(function(a, b) {
    var countryCompare = String(a.Country).localeCompare(String(b.Country))
    if (countryCompare !== 0) return countryCompare
    return String(a.City).localeCompare(String(b.City))
  })
  return result
}

function mullvadCountryOptions(nodes) {
  return mullvadRegionOptions(nodes)
}

function parseStatus(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { ok: true, unavailable: true, message: "Disconnected" }

  try {
    var data = JSON.parse(text)
    var backendState = String(data.BackendState || "Unknown")
    var self = data.Self || {}
    var selfIps = filterIPv4(self.TailscaleIPs || data.TailscaleIPs || [])
    var peers = []
    var exitNodes = []
    var rawPeers = data.Peer || {}

    for (var id in rawPeers) {
      var peer = rawPeers[id] || {}
      var normalized = peerFromStatus(id, peer)
      if (normalized.Mullvad) continue
      // Offline machines stay in the list so the panel shows the whole tailnet,
      // but they are never offered as exit nodes.
      peers.push(normalized)
      if (normalized.Online && normalized.ExitNodeOption) exitNodes.push(normalized)
    }

    // Online first, then by host name, so reachable machines stay at the top.
    peers.sort(function(a, b) {
      if (a.Online !== b.Online) return a.Online ? -1 : 1
      return String(a.HostName).localeCompare(String(b.HostName))
    })
    exitNodes.sort(function(a, b) {
      return String(a.HostName).localeCompare(String(b.HostName))
    })

    return {
      ok: true,
      unavailable: false,
      backendState: backendState,
      running: backendState === "Running",
      needsLogin: backendState === "NeedsLogin",
      authUrl: String(data.AuthURL || ""),
      selfName: displayHostName(self.HostName, self.DNSName),
      selfDnsName: cleanDnsName(self.DNSName),
      selfIp: selfIps.length > 0 ? selfIps[0] : "",
      selfUserId: String(self.UserID || ""),
      selfOs: String(self.OS || ""),
      fileSharing: hasFileSharing(self),
      peers: peers,
      exitNodes: exitNodes
    }
  } catch (e) {
    return { ok: false, unavailable: true, message: "Status error", error: "Failed to parse tailscale status" }
  }
}

function parseAccounts(raw) {
  var text = String(raw || "").trim()
  if (text === "") return { accounts: [], selectedAccountId: "", selectedAccountLabel: "" }

  try {
    var parsed = JSON.parse(text)
    var next = []
    var selected = null
    if (parsed && typeof parsed.length === "number") {
      for (var i = 0; i < parsed.length; i++) {
        var rawAccount = parsed[i] || {}
        var account = {
          id: String(rawAccount.id || rawAccount.ID || ""),
          nickname: String(rawAccount.nickname || rawAccount.Nickname || rawAccount.name || rawAccount.Name || ""),
          tailnet: String(rawAccount.tailnet || rawAccount.Tailnet || ""),
          account: String(rawAccount.account || rawAccount.Account || rawAccount.loginName || rawAccount.LoginName || rawAccount.user || rawAccount.User || ""),
          selected: rawAccount.selected === true || rawAccount.Selected === true
        }
        next.push(account)
        if (account.selected === true) selected = account
      }
    }
    return {
      accounts: next,
      selectedAccountId: selected ? String(selected.id || "") : "",
      selectedAccountLabel: selected ? accountLabel(selected) : ""
    }
  } catch (e) {
    return { accounts: [], selectedAccountId: "", selectedAccountLabel: "" }
  }
}

// `tailscale debug --file get` prints the inbox as JSON, or `null` when it is
// empty. Anything unparseable comes back as null rather than [], so the panel
// can tell "nothing waiting" from "could not look".
function parseWaitingFiles(raw) {
  var text = String(raw || "").trim()
  if (text === "") return null
  try {
    var parsed = JSON.parse(text)
    if (parsed === null) return []
    if (!Array.isArray(parsed)) return null
    var files = []
    for (var i = 0; i < parsed.length; i++) {
      var entry = parsed[i] || {}
      var name = String(entry.Name || "")
      if (name === "") continue
      files.push({ name: name, size: typeof entry.Size === "number" ? entry.Size : 0 })
    }
    return files
  } catch (e) {
    return null
  }
}

function formatBytes(bytes) {
  var value = typeof bytes === "number" && bytes > 0 ? bytes : 0
  var units = ["B", "KB", "MB", "GB", "TB"]
  var unit = 0
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024
    unit++
  }
  var digits = unit === 0 || value >= 10 ? 0 : 1
  return value.toFixed(digits) + " " + units[unit]
}

function waitingFilesSummary(files) {
  var list = Array.isArray(files) ? files : []
  if (list.length === 0) return "No files waiting"
  var total = 0
  for (var i = 0; i < list.length; i++) total += list[i].size || 0
  var what = list.length === 1 ? list[0].name : list.length + " files"
  return what + " · " + formatBytes(total)
}

// From `systemctl show -p LoadState -p ActiveState -p UnitFileState`. A unit
// counts as on while it is either enabled or running: one that was started by
// hand still empties the inbox, and one that crashed comes back next login.
function parseUnitState(raw) {
  var props = {}
  var lines = String(raw || "").split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    var eq = lines[i].indexOf("=")
    if (eq > 0) props[lines[i].substring(0, eq).trim()] = lines[i].substring(eq + 1).trim()
  }
  var fileState = String(props.UnitFileState || "")
  var activeState = String(props.ActiveState || "")
  return {
    loaded: props.LoadState === "loaded",
    enabled: fileState === "enabled" || fileState === "enabled-runtime",
    active: activeState === "active" || activeState === "activating" || activeState === "reloading" || activeState === "refreshing"
  }
}

// `tailscale file get --verbose` reports each file as
// "wrote <name> as <path> (<n> bytes)". Either part can contain " as ", so
// anchor on the directory the files were saved into.
function parseSavedFiles(raw, dir) {
  var prefix = " as " + String(dir || "").replace(/\/+$/, "") + "/"
  var lines = String(raw || "").split(/\r?\n/)
  var paths = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (line.indexOf("wrote ") !== 0) continue
    var at = line.indexOf(prefix)
    if (at === -1) continue
    var path = line.substring(at + 4).replace(/ \(\d+ bytes\)\s*$/, "")
    if (path !== "") paths.push(path)
  }
  return paths
}

function tildePath(path, home) {
  var value = String(path || "")
  var base = String(home || "").replace(/\/+$/, "")
  if (base === "") return value
  if (value === base) return "~"
  return value.indexOf(base + "/") === 0 ? "~" + value.substring(base.length) : value
}

function savedFilesNotice(paths, dir, home) {
  var list = Array.isArray(paths) ? paths : []
  var where = "to " + tildePath(dir, home)
  if (list.length === 0) return { headline: "No Taildrop files waiting", body: "Nothing was saved", open: "" }
  if (list.length === 1) {
    var name = String(list[0]).substring(String(list[0]).lastIndexOf("/") + 1)
    return { headline: "Saved " + name, body: where, open: String(list[0]) }
  }
  return { headline: "Saved " + list.length + " files", body: where, open: String(dir || "") }
}

if (typeof module !== "undefined") {
  module.exports = {
    filterIPv4: filterIPv4,
    filterIPv6: filterIPv6,
    cleanDnsName: cleanDnsName,
    shortDnsName: shortDnsName,
    displayHostName: displayHostName,
    osIcon: osIcon,
    accountLabel: accountLabel,
    loginPlan: loginPlan,
    hasFileSharing: hasFileSharing,
    isTaildropTarget: isTaildropTarget,
    isMullvadPeer: isMullvadPeer,
    peerFromStatus: peerFromStatus,
    parseExitNodeList: parseExitNodeList,
    mullvadRegionOptions: mullvadRegionOptions,
    mullvadCountryOptions: mullvadCountryOptions,
    parseStatus: parseStatus,
    parseAccounts: parseAccounts,
    parseWaitingFiles: parseWaitingFiles,
    formatBytes: formatBytes,
    waitingFilesSummary: waitingFilesSummary,
    parseUnitState: parseUnitState,
    parseSavedFiles: parseSavedFiles,
    tildePath: tildePath,
    savedFilesNotice: savedFilesNotice
  }
}
