import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "Model.js" as Model

Item {
  id: root

  property var settings: ({})
  // The panel's own IPC target, which a click on the arrival notification
  // calls back into to save the files.
  property string pluginIpcTarget: ""

  property bool installed: false
  property bool running: false
  property bool needsLogin: false

  // Optimistic off state so the UI reacts the instant you click, rather than
  // waiting for the next status refresh. _desired is -1 while we just follow
  // the real state, or 0/1 while a toggle is still catching up.
  property int _desired: -1
  readonly property bool active: _desired === -1 ? running : (_desired === 1)
  property bool refreshing: false
  property string backendState: "Unknown"
  property string statusText: "Checking…"
  property string selfName: ""
  property string selfDnsName: ""
  property string selfIp: ""
  property string selfUserId: ""
  property string selfOs: ""
  property bool fileSharing: false
  property string authUrl: ""
  property var peers: []
  property var exitNodes: []
  property var tailnetExitNodes: []
  property var mullvadExitNodes: []
  property var mullvadRegions: []
  property var accounts: []
  property string selectedAccountId: ""
  property string selectedAccountLabel: ""
  property string switchingAccountId: ""
  property string settingExitNodeId: ""
  property bool accountsAccessDenied: false
  property string actionStatus: ""
  property string lastError: ""
  property var waitingFiles: []
  property bool waitingFilesKnown: false
  property bool receiveServiceAvailable: false
  property bool autoReceive: false

  // Omarchy's own receiver, which drains the Taildrop inbox into ~/Downloads
  // the moment a file lands. The plugin only reports and flips it on request.
  readonly property string receiveService: "omarchy-tailscale-receive.service"
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 30, 5, 3600)
  readonly property bool busy: whichProcess.running || statusProcess.running || mullvadExitNodesProcess.running || accountsProcess.running || waitingFilesProcess.running || receiveStateProcess.running || actionProcess.running || loginProcess.running || switchProcess.running || operatorProcess.running || exitNodeProcess.running
  readonly property bool settingAutoReceive: receiveServiceProcess.running
  readonly property bool savingFiles: folderPickerProcess.running || fileGetProcess.running
  readonly property string waitingFilesSummary: Model.waitingFilesSummary(waitingFiles)
  // With Omarchy's receiver on, the inbox drains on its own and the receiver
  // announces every file itself, so there is nothing to watch for.
  readonly property bool watchInbox: installed && fileSharing && !autoReceive
  readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")
  readonly property string homeDir: Quickshell.env("HOME") || ""

  property string _statusOutput: ""
  property string _statusError: ""
  property string _accountsOutput: ""
  property string _accountsError: ""
  property string _mullvadExitNodesOutput: ""
  property string _mullvadExitNodesError: ""
  property string _actionOutput: ""
  property string _actionError: ""
  property string _loginOutput: ""
  property string _loginError: ""
  property bool _loginInProgress: false
  property bool _loginUrlOpened: false
  property string _preLoginAuthUrl: ""
  property double _lastAccountsRefreshMs: 0
  property string _switchOutput: ""
  property string _switchError: ""
  property string _exitNodeOutput: ""
  property string _exitNodeError: ""
  property string _operatorOutput: ""
  property string _operatorError: ""
  property string _waitingFilesOutput: ""
  property string _waitingFilesError: ""
  property string _receiveStateOutput: ""
  property string _receiveStateError: ""
  property string _receiveServiceOutput: ""
  property string _receiveServiceError: ""
  property string _folderPickerOutput: ""
  property string _folderPickerError: ""
  property string _fileGetOutput: ""
  property string _fileGetError: ""
  property string _saveDir: ""
  property var _seenWaitingFiles: ({})

  onWatchInboxChanged: syncInboxWatcher()

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function filterIPv4(ips) {
    return Model.filterIPv4(ips)
  }

  function cleanDnsName(name) {
    return Model.cleanDnsName(name)
  }

  function shortDnsName(name) {
    return Model.shortDnsName(name)
  }

  function displayHostName(hostName, dnsName) {
    return Model.displayHostName(hostName, dnsName)
  }

  function osIcon(os) {
    return Model.osIcon(os)
  }

  function accountLabel(account) {
    return Model.accountLabel(account)
  }

  function copyToClipboard(value, label) {
    var text = String(value || "")
    if (text === "") return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(text) + " | wl-copy"])
  }

  function copyPeerIp(peer) {
    if (!peer) return
    var ips = filterIPv4(peer.TailscaleIPs || [])
    copyToClipboard(ips.length > 0 ? ips[0] : "", displayHostName(peer.HostName, peer.DNSName) + " IP")
  }

  function copyPeerName(peer) {
    if (!peer) return
    copyToClipboard(displayHostName(peer.HostName, peer.DNSName), displayHostName(peer.HostName, peer.DNSName) + " name")
  }

  function copyPeerDnsName(peer) {
    if (!peer) return
    copyToClipboard(cleanDnsName(peer.DNSName), displayHostName(peer.HostName, peer.DNSName) + " DNS name")
  }

  function peerAddress(peer) {
    if (!peer) return ""
    if (peer.DNSName) return cleanDnsName(peer.DNSName)
    if (peer.HostName) return String(peer.HostName)
    var ips = filterIPv4(peer.TailscaleIPs || [])
    return ips.length > 0 ? ips[0] : ""
  }

  function canSendFiles(peer) {
    if (!fileSharing || !running || !peer) return false
    return Model.isTaildropTarget(peer, selfUserId)
  }

  function sendFile(peer) {
    if (!canSendFiles(peer)) return
    var target = peerAddress(peer)
    if (target === "") return
    Quickshell.execDetached(["omarchy-tailscale-send", target])
  }

  function notify(headline, body, urgency, onClick) {
    var args = ["omarchy-notification-send", "-g", "󰒊"]
    if (urgency) args.push("-u", urgency)
    args.push(headline)
    if (body) args.push(body)
    // --exec takes the rest of the line as the click command, so it goes last.
    if (onClick && onClick.length > 0) args = args.concat(["--exec"], onClick)
    Quickshell.execDetached(args)
  }

  function announceWaitingFiles(files) {
    var diff = Model.diffWaitingFiles(files, _seenWaitingFiles)
    _seenWaitingFiles = diff.seen
    if (diff.fresh.length === 0 || autoReceive) return
    var notice = Model.waitingFilesNotice(diff.fresh)
    notify(notice.headline, notice.body, "normal", pluginIpcTarget !== "" ? ["omarchy-shell", "-q", pluginIpcTarget, "saveFiles"] : [])
  }

  function syncInboxWatcher() {
    if (watchInbox && !inboxWatchProcess.running) {
      // Peer updates are most of what the bus carries and none of them matter
      // here, so leave them out rather than parse past them.
      inboxWatchProcess.command = ["tailscale", "debug", "watch-ipn", "--peer-changes=false", "--peer-patches=false"]
      inboxWatchProcess.running = true
    } else if (!watchInbox && inboxWatchProcess.running) {
      inboxWatchProcess.running = false
    }
  }

  function setAutoReceive(on) {
    if (!receiveServiceAvailable || receiveServiceProcess.running) return
    _receiveServiceOutput = ""
    _receiveServiceError = ""
    receiveServiceProcess.command = ["systemctl", "--user", on ? "enable" : "disable", "--now", receiveService]
    receiveServiceProcess.running = true
  }

  function toggleAutoReceive() {
    setAutoReceive(!autoReceive)
  }

  // Asks for a folder first; fileGetProcess takes over once one is picked.
  function saveWaitingFiles() {
    if (!installed || savingFiles) return
    _folderPickerOutput = ""
    _folderPickerError = ""
    folderPickerProcess.command = ["omarchy-file-select", "--directory", "--title", "Save Taildrop files"]
    folderPickerProcess.running = true
  }

  function getWaitingFiles(dir) {
    _saveDir = dir
    _fileGetOutput = ""
    _fileGetError = ""
    // rename rather than the default skip, which would leave a same-named file
    // stuck in the inbox and report the whole run as failed.
    fileGetProcess.command = ["tailscale", "file", "get", "--verbose", "--conflict=rename", dir]
    fileGetProcess.running = true
  }

  function refresh(forceAccounts) {
    if (installed) {
      refreshStatusAndAccounts(forceAccounts === true)
      return
    }
    if (!whichProcess.running) {
      refreshing = true
      whichProcess.command = ["which", "tailscale"]
      whichProcess.running = true
    }
  }

  function refreshStatusAndAccounts(forceAccounts) {
    if (!installed) return
    var launched = false
    if (!statusProcess.running) {
      _statusOutput = ""
      _statusError = ""
      refreshing = true
      statusProcess.command = ["tailscale", "status", "--json"]
      statusProcess.running = true
      launched = true
    }
    if (!mullvadExitNodesProcess.running) {
      _mullvadExitNodesOutput = ""
      _mullvadExitNodesError = ""
      mullvadExitNodesProcess.command = ["tailscale", "exit-node", "list"]
      mullvadExitNodesProcess.running = true
      launched = true
    }
    var now = Date.now()
    var shouldRefreshAccounts = forceAccounts === true || accounts.length === 0 || now - _lastAccountsRefreshMs > 60000
    if (shouldRefreshAccounts && !accountsProcess.running) {
      _accountsOutput = ""
      _accountsError = ""
      _lastAccountsRefreshMs = now
      accountsProcess.command = ["tailscale", "switch", "--list", "--json"]
      accountsProcess.running = true
      launched = true
    }
    if (refreshWaitingFiles()) launched = true
    if (!receiveStateProcess.running) {
      _receiveStateOutput = ""
      _receiveStateError = ""
      receiveStateProcess.command = ["systemctl", "--user", "show", "-p", "LoadState", "-p", "ActiveState", "-p", "UnitFileState", receiveService]
      receiveStateProcess.running = true
      launched = true
    }
    // Arm on the launch that needs watching and leave it alone after that.
    // Restarting it every refresh pushes the deadline out ahead of a hung
    // process forever once the refresh interval is shorter than the timeout,
    // and refreshIntervalSec goes down to five seconds.
    if (launched && !pollWatchdog.running) pollWatchdog.start()
  }

  // Also run on its own when the bus says files arrived, so it arms the
  // watchdog itself instead of relying on refreshStatusAndAccounts to.
  function refreshWaitingFiles() {
    if (!installed || waitingFilesProcess.running) return false
    _waitingFilesOutput = ""
    _waitingFilesError = ""
    // `tailscale file` has no way to list the inbox without emptying it; the
    // debug command is the only read-only view the CLI offers.
    waitingFilesProcess.command = ["tailscale", "debug", "--file", "get"]
    waitingFilesProcess.running = true
    if (!pollWatchdog.running) pollWatchdog.start()
    return true
  }

  function elideStatus(text) {
    var value = String(text || "").replace(/\s+/g, " ").trim()
    return value.length > 140 ? value.substring(0, 137) + "…" : value
  }

  function resetUnavailable(message) {
    running = false
    needsLogin = false
    _desired = -1
    backendState = "Unavailable"
    statusText = message
    selfName = ""
    selfDnsName = ""
    selfIp = ""
    selfUserId = ""
    selfOs = ""
    fileSharing = false
    authUrl = ""
    peers = []
    exitNodes = []
    tailnetExitNodes = []
    mullvadExitNodes = []
    mullvadRegions = []
    accounts = []
    selectedAccountId = ""
    selectedAccountLabel = ""
    switchingAccountId = ""
    settingExitNodeId = ""
    accountsAccessDenied = false
  }

  function parseStatus(raw) {
    var parsed = Model.parseStatus(raw)
    if (!parsed.ok) {
      resetUnavailable(parsed.message || "Status error")
      lastError = parsed.error || "Failed to parse tailscale status"
      console.warn("tailscale", lastError)
      return
    }
    if (parsed.unavailable) {
      resetUnavailable(parsed.message || "Disconnected")
      return
    }

    backendState = parsed.backendState
    running = parsed.running
    // Reality caught up to the pending toggle — stop overriding.
    if (_desired !== -1 && running === (_desired === 1)) _desired = -1
    needsLogin = parsed.needsLogin
    authUrl = parsed.authUrl
    if (needsLogin && _loginInProgress && !_loginUrlOpened && authUrl !== "" && authUrl !== _preLoginAuthUrl) openAuthUrlFrom(authUrl, false)
    selfName = parsed.selfName
    selfDnsName = parsed.selfDnsName
    selfIp = parsed.selfIp
    selfUserId = parsed.selfUserId
    selfOs = parsed.selfOs
    fileSharing = parsed.fileSharing
    peers = parsed.running ? parsed.peers : []
    tailnetExitNodes = parsed.running ? parsed.exitNodes : []
    exitNodes = parsed.running ? tailnetExitNodes.concat(mullvadRegions) : []

    if (needsLogin) statusText = "Needs login"
    else if (running) {
      statusText = "Connected"
      _loginInProgress = false
      _loginUrlOpened = false
      _preLoginAuthUrl = ""
      loginTimeoutTimer.stop()
    } else if (backendState === "Stopped") {
      statusText = "Disconnected"
    } else {
      statusText = backendState
    }
    lastError = ""
  }

  function parseAccounts(raw) {
    var parsed = Model.parseAccounts(raw)
    accounts = parsed.accounts
    selectedAccountId = parsed.selectedAccountId
    selectedAccountLabel = parsed.selectedAccountLabel
    accountsAccessDenied = false
  }

  function parseMullvadExitNodes(raw) {
    mullvadExitNodes = Model.parseExitNodeList(raw)
    mullvadRegions = Model.mullvadRegionOptions(mullvadExitNodes)
    exitNodes = running ? tailnetExitNodes.concat(mullvadRegions) : []
  }

  function toggleTailscale() {
    if (!installed) return
    if (active) down()
    else loginOrUp()
  }

  function down() {
    // No progress status here — the greyed icon and hero line already convey
    // the optimistic off; only surface a message if the command fails.
    _desired = 0
    runAction(["tailscale", "down"])
  }

  function loginOrUp() {
    if (!installed || loginProcess.running) return
    _desired = -1
    var plan = Model.loginPlan(needsLogin, authUrl)
    if (plan.authUrl !== "") {
      _loginUrlOpened = false
      openAuthUrlFrom(plan.authUrl, true)
      return
    }
    _loginOutput = ""
    _loginError = ""
    if (needsLogin) actionStatus = "Starting Tailscale login…"
    else _desired = 1
    _loginInProgress = needsLogin
    _loginUrlOpened = false
    _preLoginAuthUrl = authUrl
    loginProcess.command = plan.command
    loginProcess.running = true
    if (needsLogin) loginTimeoutTimer.restart()
  }

  function switchAccount(id) {
    var accountId = String(id || "")
    if (!installed || accountId === "" || accountId === selectedAccountId || switchProcess.running) return
    _switchOutput = ""
    _switchError = ""
    switchingAccountId = accountId
    switchProcess.command = ["tailscale", "switch", accountId]
    switchProcess.running = true
  }

  function exitNodeTarget(peer) {
    if (!peer) return ""
    if (peer.Mullvad === true) {
      var mullvadIps = filterIPv4(peer.TailscaleIPs || [])
      if (mullvadIps.length > 0) return mullvadIps[0]
    }
    return peerAddress(peer)
  }

  function setExitNode(peer) {
    if (!installed || !running || !peer || exitNodeProcess.running) return
    var active = peer.ExitNode === true
    var target = active ? "" : exitNodeTarget(peer)
    if (!active && target === "") return
    _exitNodeOutput = ""
    _exitNodeError = ""
    settingExitNodeId = String(peer.id || "")
    exitNodeProcess.command = ["tailscale", "set", "--exit-node=" + target]
    exitNodeProcess.running = true
  }

  function authorizeTailscaleOperator() {
    if (!installed || operatorProcess.running || userName === "") return
    _operatorOutput = ""
    _operatorError = ""
    actionStatus = "Authorizing Tailscale operator..."
    operatorProcess.command = ["pkexec", "tailscale", "set", "--operator=" + userName]
    operatorProcess.running = true
  }

  function runAction(command, label) {
    if (actionProcess.running) return
    _actionOutput = ""
    _actionError = ""
    actionStatus = label || ""
    actionProcess.command = command
    actionProcess.running = true
  }

  function openAuthUrlFrom(text, allowFallback) {
    if (_loginUrlOpened) return true
    var match = String(text || "").match(/https?:\/\/\S+/)
    var url = match && match[0] ? match[0] : (allowFallback === true ? authUrl : "")
    if (url !== "") {
      // Turning on ended up needing browser auth — stop pretending we're up.
      _desired = -1
      _loginUrlOpened = true
      _loginInProgress = false
      loginTimeoutTimer.stop()
      Quickshell.execDetached(["omarchy-launch-browser", url])
      return true
    }
    return false
  }

  function handleLoginOutput(data, isError) {
    var text = String(data || "")
    if (isError) _loginError += text + "\n"
    else _loginOutput += text + "\n"
    if (_loginInProgress && !_loginUrlOpened) openAuthUrlFrom(text, false)
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    // After a fresh boot the startup poll usually lands before tailscaled has
    // connected, which left the icon stale until the next periodic refresh.
    // Poll quickly until the service shows up, or give up after ~30 seconds.
    id: startupRamp
    property int ticks: 0
    interval: 2000
    repeat: true
    running: true
    onTriggered: {
      ticks += 1
      if (root.running || ticks >= 15) startupRamp.running = false
      else root.refresh()
    }
  }

  Timer {
    id: delayedRefresh
    interval: 600
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    // Every poll is skipped while its own process is still running, so one that
    // never exits — tailscale can hang on a network that is coming and going —
    // silently stops the panel refreshing at all, and it stays stopped. Reap
    // anything still running well inside the refresh interval so the next tick
    // starts clean.
    id: pollWatchdog
    interval: 15000
    repeat: false
    onTriggered: {
      if (statusProcess.running) statusProcess.running = false
      if (mullvadExitNodesProcess.running) mullvadExitNodesProcess.running = false
      if (accountsProcess.running) accountsProcess.running = false
      if (waitingFilesProcess.running) waitingFilesProcess.running = false
      if (receiveStateProcess.running) receiveStateProcess.running = false
    }
  }

  Timer {
    id: actionStatusTimer
    interval: 2200
    repeat: false
    onTriggered: root.actionStatus = ""
  }

  Timer {
    id: loginTimeoutTimer
    interval: 10000
    repeat: false
    onTriggered: {
      if (!root._loginInProgress || root._loginUrlOpened) return
      if (!root.openAuthUrlFrom(root.authUrl, true)) {
        root._loginInProgress = false
        root.actionStatus = "Tailscale login link not available yet"
      }
    }
  }

  Process {
    id: whichProcess
    running: false
    command: []
    onExited: function(exitCode) {
      root.installed = exitCode === 0
      if (root.installed) root.refreshStatusAndAccounts()
      else {
        root.refreshing = false
        root.resetUnavailable("Not installed")
      }
    }
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true; onStreamFinished: root._statusOutput = text }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true; onStreamFinished: root._statusError = text }
    onExited: function(exitCode) {
      root.refreshing = false
      var stdout = String(statusStdout.text || root._statusOutput || "")
      var stderr = String(statusStderr.text || root._statusError || "")
      if (exitCode === 0) root.parseStatus(stdout)
      else {
        root.resetUnavailable("Disconnected")
        root.lastError = stderr.trim()
      }
    }
  }

  Process {
    id: accountsProcess
    running: false
    command: []
    stdout: StdioCollector { id: accountsStdout; waitForEnd: true; onStreamFinished: root._accountsOutput = text }
    stderr: StdioCollector { id: accountsStderr; waitForEnd: true; onStreamFinished: root._accountsError = text }
    onExited: function(exitCode) {
      var stdout = String(accountsStdout.text || root._accountsOutput || "")
      var stderr = String(accountsStderr.text || root._accountsError || "")
      if (exitCode === 0) root.parseAccounts(stdout)
      else {
        root.parseAccounts("")
        if (/profiles access denied/i.test(stderr) || /profiles access denied/i.test(stdout)) {
          root.accountsAccessDenied = true
          root.lastError = "Authorize Tailscale operator to show connections"
        } else {
          root.lastError = elideStatus(stderr || stdout || "Could not list Tailscale connections")
        }
      }
    }
  }

  Process {
    id: mullvadExitNodesProcess
    running: false
    command: []
    stdout: StdioCollector { id: mullvadExitNodesStdout; waitForEnd: true; onStreamFinished: root._mullvadExitNodesOutput = text }
    stderr: StdioCollector { id: mullvadExitNodesStderr; waitForEnd: true; onStreamFinished: root._mullvadExitNodesError = text }
    onExited: function(exitCode) {
      var stdout = String(mullvadExitNodesStdout.text || root._mullvadExitNodesOutput || "")
      if (exitCode === 0) root.parseMullvadExitNodes(stdout)
      else root.parseMullvadExitNodes("")
    }
  }

  Process {
    id: actionProcess
    running: false
    command: []
    stdout: StdioCollector { id: actionStdout; waitForEnd: true; onStreamFinished: root._actionOutput = text }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true; onStreamFinished: root._actionError = text }
    onExited: function(exitCode) {
      var stdout = String(actionStdout.text || root._actionOutput || "")
      var stderr = String(actionStderr.text || root._actionError || "")
      if (exitCode !== 0) {
        root._desired = -1
        root.lastError = elideStatus(stderr || stdout || "Tailscale command failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: loginProcess
    running: false
    command: []
    stdout: SplitParser { onRead: function(data) { root.handleLoginOutput(data, false) } }
    stderr: SplitParser { onRead: function(data) { root.handleLoginOutput(data, true) } }
    onExited: function(exitCode) {
      var combined = String(root._loginOutput || "") + "\n" + String(root._loginError || "")
      var opened = root.openAuthUrlFrom(combined, true)
      if (exitCode !== 0 && !opened) {
        root._desired = -1
        root._loginInProgress = false
        root.lastError = elideStatus(combined || "tailscale up failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else if (!opened) {
        root.lastError = ""
        root.actionStatus = ""
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: switchProcess
    running: false
    command: []
    stdout: StdioCollector { id: switchStdout; waitForEnd: true; onStreamFinished: root._switchOutput = text }
    stderr: StdioCollector { id: switchStderr; waitForEnd: true; onStreamFinished: root._switchError = text }
    onExited: function(exitCode) {
      var stdout = String(switchStdout.text || root._switchOutput || "")
      var stderr = String(switchStderr.text || root._switchError || "")
      if (exitCode !== 0) {
        root.lastError = elideStatus(stderr || stdout || "Account switch failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
        root._lastAccountsRefreshMs = 0
      }
      root.switchingAccountId = ""
      delayedRefresh.restart()
    }
  }

  Process {
    id: exitNodeProcess
    running: false
    command: []
    stdout: StdioCollector { id: exitNodeStdout; waitForEnd: true; onStreamFinished: root._exitNodeOutput = text }
    stderr: StdioCollector { id: exitNodeStderr; waitForEnd: true; onStreamFinished: root._exitNodeError = text }
    onExited: function(exitCode) {
      var stdout = String(exitNodeStdout.text || root._exitNodeOutput || "")
      var stderr = String(exitNodeStderr.text || root._exitNodeError || "")
      if (exitCode !== 0) {
        root.lastError = elideStatus(stderr || stdout || "Exit node selection failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      root.settingExitNodeId = ""
      delayedRefresh.restart()
    }
  }

  Process {
    id: operatorProcess
    running: false
    command: []
    stdout: StdioCollector { id: operatorStdout; waitForEnd: true; onStreamFinished: root._operatorOutput = text }
    stderr: StdioCollector { id: operatorStderr; waitForEnd: true; onStreamFinished: root._operatorError = text }
    onExited: function(exitCode) {
      var stdout = String(operatorStdout.text || root._operatorOutput || "")
      var stderr = String(operatorStderr.text || root._operatorError || "")
      if (exitCode !== 0) {
        root.lastError = elideStatus(stderr || stdout || "Tailscale authorization failed")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.accountsAccessDenied = false
        root.lastError = ""
        root.actionStatus = "Tailscale operator authorized"
        actionStatusTimer.restart()
        root._lastAccountsRefreshMs = 0
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: waitingFilesProcess
    running: false
    command: []
    stdout: StdioCollector { id: waitingFilesStdout; waitForEnd: true; onStreamFinished: root._waitingFilesOutput = text }
    stderr: StdioCollector { id: waitingFilesStderr; waitForEnd: true; onStreamFinished: root._waitingFilesError = text }
    onExited: function(exitCode) {
      var stdout = String(waitingFilesStdout.text || root._waitingFilesOutput || "")
      var files = exitCode === 0 ? Model.parseWaitingFiles(stdout) : null
      root.waitingFilesKnown = files !== null
      root.waitingFiles = files || []
      if (files !== null) root.announceWaitingFiles(files)
    }
  }

  // A long-running subscription to tailscaled's message bus, the same signal
  // `tailscale file get --wait` waits on, so an arrival is announced at once
  // instead of on the next poll. It is not a poll, so it stays out of `busy`
  // and the watchdog; polling still catches anything it misses.
  Process {
    id: inboxWatchProcess
    running: false
    command: []
    stdout: SplitParser {
      onRead: function(data) {
        if (String(data).indexOf("\"FilesWaiting\"") !== -1 && !inboxWatchDebounce.running) inboxWatchDebounce.start()
      }
    }
    onExited: if (root.watchInbox) inboxWatchRestart.restart()
  }

  Timer {
    // A transfer in progress repeats FilesWaiting with every progress update
    // while earlier files sit in the inbox; look at most once a second.
    id: inboxWatchDebounce
    interval: 1000
    repeat: false
    onTriggered: root.refreshWaitingFiles()
  }

  Timer {
    // The watch ends whenever tailscaled restarts.
    id: inboxWatchRestart
    interval: 10000
    repeat: false
    onTriggered: root.syncInboxWatcher()
  }

  Process {
    id: receiveStateProcess
    running: false
    command: []
    stdout: StdioCollector { id: receiveStateStdout; waitForEnd: true; onStreamFinished: root._receiveStateOutput = text }
    stderr: StdioCollector { id: receiveStateStderr; waitForEnd: true; onStreamFinished: root._receiveStateError = text }
    onExited: function(exitCode) {
      var stdout = String(receiveStateStdout.text || root._receiveStateOutput || "")
      var state = Model.parseUnitState(exitCode === 0 ? stdout : "")
      root.receiveServiceAvailable = state.loaded
      root.autoReceive = state.enabled || state.active
    }
  }

  Process {
    id: receiveServiceProcess
    running: false
    command: []
    stdout: StdioCollector { id: receiveServiceStdout; waitForEnd: true; onStreamFinished: root._receiveServiceOutput = text }
    stderr: StdioCollector { id: receiveServiceStderr; waitForEnd: true; onStreamFinished: root._receiveServiceError = text }
    onExited: function(exitCode) {
      var stdout = String(receiveServiceStdout.text || root._receiveServiceOutput || "")
      var stderr = String(receiveServiceStderr.text || root._receiveServiceError || "")
      if (exitCode !== 0) {
        root.lastError = elideStatus(stderr || stdout || "Could not change automatic receiving")
        root.actionStatus = root.lastError
        actionStatusTimer.restart()
      } else {
        root.lastError = ""
        root.actionStatus = ""
      }
      delayedRefresh.restart()
    }
  }

  Process {
    id: folderPickerProcess
    running: false
    command: []
    stdout: StdioCollector { id: folderPickerStdout; waitForEnd: true; onStreamFinished: root._folderPickerOutput = text }
    stderr: StdioCollector { id: folderPickerStderr; waitForEnd: true; onStreamFinished: root._folderPickerError = text }
    onExited: function(exitCode) {
      var stdout = String(folderPickerStdout.text || root._folderPickerOutput || "")
      var dir = stdout.split(/\r?\n/)[0].trim()
      // 1 is the chooser closing with nothing picked, which is a decision, not
      // a fault. Anything above it means the chooser never ran.
      if (exitCode === 0 && dir !== "") root.getWaitingFiles(dir)
      else if (exitCode > 1) root.notify("Could not save Taildrop files", "The folder chooser did not open", "critical", [])
    }
  }

  Process {
    id: fileGetProcess
    running: false
    command: []
    stdout: StdioCollector { id: fileGetStdout; waitForEnd: true; onStreamFinished: root._fileGetOutput = text }
    stderr: StdioCollector { id: fileGetStderr; waitForEnd: true; onStreamFinished: root._fileGetError = text }
    onExited: function(exitCode) {
      var stdout = String(fileGetStdout.text || root._fileGetOutput || "")
      var stderr = String(fileGetStderr.text || root._fileGetError || "")
      if (exitCode !== 0) {
        root.notify("Could not save Taildrop files", elideStatus(stderr || stdout || "tailscale file get failed"), "critical", [])
      } else {
        var notice = Model.savedFilesNotice(Model.parseSavedFiles(stdout, root._saveDir), root._saveDir, root.homeDir)
        root.notify(notice.headline, notice.body, "", notice.open !== "" ? ["xdg-open", notice.open] : [])
      }
      delayedRefresh.restart()
    }
  }
}
