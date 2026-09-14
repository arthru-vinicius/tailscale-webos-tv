const BASE = "/var/lib/webosbrew/tailscale-tv";
const APPID = "com.github.arthru-vinicius.tailscale-tv";
const HB_SERVICE = "luna://org.webosbrew.hbchannel.service";

const TEXT = {
  serviceUnavailable:
    "ERROR: webOS.service.request is not available.\n\n" +
    "Check that this file exists:\n" +
    "lib/webOSTVjs-1.2.4/webOSTV.js",
  serviceUnavailableStatus: "Error: webOS service unavailable",
  hbTimeout: "TIMEOUT: no response from Homebrew service.",
  jsException: "JS EXCEPTION",
  lunaError: "luna-call ERROR",

  checkInstalled:
    "Tailscale TV ready.\n\n" +
    "Components already installed.\n\n" +
    "1. Enter your auth key below and press \"Save auth key\" (get one at " +
    "console.tailscale.com/admin/settings/keys)\n" +
    "2. Press \"Start\"\n" +
    "3. Press \"Status\" to confirm the tunnel is up",

  checkMissing:
    "Tailscale TV ready.\n\n" +
    "Components are not installed yet.\n\n" +
    "Press \"Install / update\" before starting Tailscale.",

  checkingInitial: "Tailscale TV ready.\n\nChecking whether components are already installed..."
};

function setStatus(text) {
  const el = document.getElementById("statusLine");
  if (el) el.textContent = text || "";
}

function print(text) {
  const el = document.getElementById("out");
  if (el) {
    el.textContent = text || "";
    el.scrollTop = 0;
  }
}

function scrollOutput(direction) {
  const el = document.getElementById("out");
  if (!el) return;
  el.scrollTop += direction * 300;
}

function scrollOutputToEnd() {
  const el = document.getElementById("out");
  if (!el) return;
  el.scrollTop = el.scrollHeight;
}

function decodeBase64Maybe(value) {
  if (!value) return "";
  try {
    return atob(value);
  } catch (e) {
    return "";
  }
}

function formatResponse(res) {
  let out = "";

  if (res.stdoutString) {
    out += res.stdoutString;
  } else if (res.stdoutBytes) {
    out += decodeBase64Maybe(res.stdoutBytes);
  }

  if (res.stderrString) {
    out += "\nSTDERR:\n" + res.stderrString;
  } else if (res.stderrBytes) {
    const stderr = decodeBase64Maybe(res.stderrBytes);
    if (stderr) out += "\nSTDERR:\n" + stderr;
  }

  if (!out) {
    out = JSON.stringify(res, null, 2);
  }

  return out;
}

function serviceAvailable() {
  return (
    typeof webOS !== "undefined" &&
    webOS.service &&
    typeof webOS.service.request === "function"
  );
}

// POSIX single-quote escaping, so values typed by the user (e.g. the auth
// key) reach the shell script as an exact, literal argument.
function shQuote(value) {
  return "'" + String(value).replace(/'/g, "'\\''") + "'";
}

function execCommand(command, callback, timeoutMs) {
  timeoutMs = timeoutMs || 20000;

  if (!serviceAvailable()) {
    const msg = TEXT.serviceUnavailable;
    print(msg);
    setStatus(TEXT.serviceUnavailableStatus);
    if (callback) callback(false, msg);
    return;
  }

  let finished = false;

  const timer = setTimeout(function() {
    if (!finished) {
      finished = true;
      const msg = TEXT.hbTimeout;
      print(msg);
      setStatus("Timeout");
      if (callback) callback(false, msg);
    }
  }, timeoutMs);

  try {
    webOS.service.request(HB_SERVICE, {
      method: "exec",
      parameters: {
        command: command
      },
      onSuccess: function(res) {
        if (finished) return;
        finished = true;
        clearTimeout(timer);
        const out = formatResponse(res);
        if (callback) callback(true, out, res);
      },
      onFailure: function(err) {
        if (finished) return;
        finished = true;
        clearTimeout(timer);
        const out = TEXT.lunaError + ":\n" + JSON.stringify(err, null, 2);
        if (callback) callback(false, out, err);
      }
    });
  } catch (e) {
    finished = true;
    clearTimeout(timer);
    const out = TEXT.jsException + ":\n" + e.message + "\n\n" + (e.stack || "");
    if (callback) callback(false, out, e);
  }
}

function run(command, label, timeoutMs) {
  setStatus("Running...");
  print("Running:\n" + (label || command) + "\n\nWaiting for response...");

  const wrappedCommand =
    "( " + command + " ); " +
    "RC=$?; " +
    "echo; echo COMMAND_RC=$RC; " +
    "exit 0";

  execCommand(wrappedCommand, function(ok, out) {
    print(out);

    const commandOk = ok && out.indexOf("COMMAND_RC=0") !== -1;
    setStatus(commandOk ? "Completed" : "Error");
  }, timeoutMs || 20000);
}

function componentsCheckCommand() {
  return (
    "if [ -L " + BASE + "/scripts ] && " +
    "   [ -d " + BASE + "/bin ] && " +
    "   [ -x " + BASE + "/scripts/start.sh ] && " +
    "   [ -x " + BASE + "/scripts/stop.sh ] && " +
    "   [ -x " + BASE + "/scripts/status.sh ] && " +
    "   [ -x " + BASE + "/bin/tailscale ] && " +
    "   [ -x " + BASE + "/bin/tailscaled ]; then " +
    "  echo 'COMPONENTS_STATUS=installed'; " +
    "  echo 'Tailscale components installed'; " +
    "else " +
    "  echo 'COMPONENTS_STATUS=missing'; " +
    "  echo 'Tailscale components not installed'; " +
    "  echo 'Press Install / update before starting Tailscale.'; " +
    "fi"
  );
}

function checkComponents(callback) {
  execCommand(componentsCheckCommand(), function(ok, out) {
    const installed = out.indexOf("COMPONENTS_STATUS=installed") !== -1;
    if (callback) callback(installed, out);
  }, 10000);
}

function installComponents() {
  const cmd =
    "APPID='" + APPID + "'; " +
    "echo 'Installing/updating Tailscale components...'; " +
    "echo; echo '== whoami / id =='; " +
    "id 2>&1 || true; " +
    "echo; echo '== app locations =='; " +
    "INSTALL=''; " +
    "for d in " +
      "/media/developer/apps/usr/palm/applications/$APPID " +
      "/media/cryptofs/apps/usr/palm/applications/$APPID " +
      "/media/internal/apps/usr/palm/applications/$APPID; do " +
      "echo \"checking: $d\"; " +
      "if [ -f \"$d/payload/tailscale/install.sh\" ]; then " +
        "INSTALL=\"$d/payload/tailscale/install.sh\"; " +
        "break; " +
      "fi; " +
    "done; " +
    "if [ -z \"$INSTALL\" ]; then " +
      "echo; echo '== fallback search =='; " +
      "INSTALL=$(find /media -type f -path \"*/$APPID/payload/tailscale/install.sh\" 2>/dev/null | head -1); " +
    "fi; " +
    "if [ -z \"$INSTALL\" ]; then " +
      "echo 'ERROR: cannot find payload/tailscale/install.sh'; " +
      "echo; echo '== matching files =='; " +
      "find /media -path \"*$APPID*\" 2>/dev/null | head -120; " +
      "echo; echo 'INSTALL_RC=1'; " +
      "exit 0; " +
    "fi; " +
    "echo; echo \"found installer: $INSTALL\"; " +
    "echo; echo '== running installer =='; " +
    "sh \"$INSTALL\"; " +
    "RC=$?; " +
    "echo; echo \"INSTALL_RC=$RC\"; " +
    "exit 0";

  setStatus("Installing/updating components...");
  print("Running:\nInstall / update\n\nWaiting for response...");

  execCommand(cmd, function(ok, out) {
    print(out);

    const installOk = ok && out.indexOf("INSTALL_RC=0") !== -1;

    if (installOk) {
      setStatus("Components installed/updated");
      refreshAutostart();
    } else {
      setStatus("Error");
    }
  }, 60000);
}

function startTailscale() {
  run(BASE + "/scripts/start.sh", "Start", 40000);
}

function stopTailscale() {
  run(BASE + "/scripts/stop.sh", "Stop", 30000);
}

function statusTailscale() {
  run(BASE + "/scripts/status.sh", "Status", 30000);
}

function showLog() {
  run(
    "echo '== tailscaled.log =='; " +
    "tail -120 " + BASE + "/run/tailscaled.log 2>/dev/null || true; " +
    "echo; echo '== autostart.log =='; " +
    "tail -80 " + BASE + "/run/autostart.log 2>/dev/null || true",
    "Log",
    30000
  );
}

function saveAuthKey() {
  const input = document.getElementById("authKeyInput");
  const key = input ? input.value.trim() : "";

  if (!key) {
    setStatus("Enter an auth key first");
    return;
  }

  run(
    BASE + "/scripts/set-authkey.sh " + shQuote(key),
    "Save auth key",
    15000
  );

  if (input) input.value = "";
}

function refreshAutostart() {
  const cmd =
    "if [ -x " + BASE + "/scripts/autostart.sh ]; then " +
    BASE + "/scripts/autostart.sh status; " +
    "else echo 'Autostart: unavailable'; fi";

  execCommand(cmd, function(ok, out) {
    const toggle = document.getElementById("autostartToggle");
    if (!toggle) return;

    const unavailable = out.indexOf("unavailable") !== -1;
    toggle.checked = out.indexOf("enabled") !== -1;
    toggle.disabled = unavailable;
  }, 10000);
}

function toggleAutostart() {
  const toggle = document.getElementById("autostartToggle");
  const enable = toggle && toggle.checked;
  const cmd = BASE + "/scripts/autostart.sh " + (enable ? "enable" : "disable");

  run(cmd, enable ? "Enable start on boot" : "Disable start on boot", 15000);

  setTimeout(refreshAutostart, 1200);
}

function cleanupAll() {
  run(BASE + "/scripts/uninstall.sh", "Uninstall", 30000);
}

window.onerror = function(message, source, lineno, colno, error) {
  print(
    "JS ERROR:\n" +
    message + "\n" +
    "line: " + lineno + ":" + colno + "\n" +
    (error && error.stack ? error.stack : "")
  );
  setStatus("JS error");
};

window.onload = function() {
  print(TEXT.checkingInitial);
  setStatus("Checking components");

  checkComponents(function(installed, out) {
    if (installed) {
      refreshAutostart();
      setStatus("Ready");
      print(TEXT.checkInstalled);
    } else {
      setStatus("Install required");
      print(TEXT.checkMissing);

      const toggle = document.getElementById("autostartToggle");
      if (toggle) {
        toggle.checked = false;
        toggle.disabled = true;
      }
    }
  });

  setTimeout(function() {
    const btn = document.querySelector("button");
    if (btn) btn.focus();
  }, 300);
};

function remoteKeyCode(event) {
  if (event && typeof event.keyCode === "number" && event.keyCode) {
    return event.keyCode;
  }

  if (event && typeof event.which === "number") {
    return event.which;
  }

  if (event && event.key) {
    const keys = {
      ArrowLeft: 37,
      ArrowUp: 38,
      ArrowRight: 39,
      ArrowDown: 40,
      Enter: 13,
      Escape: 27,
      GoBack: 461
    };
    return keys[event.key] || 0;
  }

  return 0;
}

function remoteFocusableElements() {
  const elements = document.querySelectorAll("button, input");
  const focusable = [];

  for (let i = 0; i < elements.length; i++) {
    const element = elements[i];
    if (element.disabled) continue;
    if (element.offsetWidth === 0 || element.offsetHeight === 0) continue;
    focusable.push(element);
  }

  return focusable;
}

function moveRemoteFocus(direction) {
  const elements = remoteFocusableElements();
  if (!elements.length) return false;

  let current = document.activeElement;
  if (elements.indexOf(current) === -1) {
    elements[0].focus();
    return true;
  }

  const currentRect = current.getBoundingClientRect();
  const currentX = currentRect.left + currentRect.width / 2;
  const currentY = currentRect.top + currentRect.height / 2;
  let best = null;
  let bestScore = Infinity;

  for (let i = 0; i < elements.length; i++) {
    const candidate = elements[i];
    if (candidate === current) continue;

    const rect = candidate.getBoundingClientRect();
    const candidateX = rect.left + rect.width / 2;
    const candidateY = rect.top + rect.height / 2;
    const dx = candidateX - currentX;
    const dy = candidateY - currentY;
    const primary = direction === "left" || direction === "right" ? dx : dy;
    const cross = direction === "left" || direction === "right" ? dy : dx;

    if (
      (direction === "left" && primary >= -2) ||
      (direction === "right" && primary <= 2) ||
      (direction === "up" && primary >= -2) ||
      (direction === "down" && primary <= 2)
    ) {
      continue;
    }

    const score = Math.abs(primary) + Math.abs(cross) * 2;
    if (score < bestScore) {
      best = candidate;
      bestScore = score;
    }
  }

  if (!best) return false;
  best.focus();
  if (typeof best.scrollIntoView === "function") {
    try {
      best.scrollIntoView({ block: "nearest", inline: "nearest" });
    } catch (e) {
      best.scrollIntoView(false);
    }
  }
  return true;
}

function handleRemoteKey(event) {
  const code = remoteKeyCode(event);
  const active = document.activeElement;
  const isTypingInInput = active && active.tagName === "INPUT" && active.type === "text";

  if (code === 461 || code === 27) {
    if (code === 461 && typeof webOS !== "undefined" && webOS.platformBack) {
      event.preventDefault();
      webOS.platformBack();
    }
    return;
  }

  if (code === 13) {
    if (active && active.tagName === "BUTTON") {
      event.preventDefault();
      active.click();
    }
    return;
  }

  // Let left/right move the text cursor while editing the auth key field.
  if (isTypingInInput && (code === 37 || code === 39)) return;

  const directions = {
    37: "left",
    38: "up",
    39: "right",
    40: "down"
  };
  const direction = directions[code];
  if (!direction) return;

  if (moveRemoteFocus(direction)) {
    event.preventDefault();
    event.stopPropagation();
  }
}

document.addEventListener("keydown", handleRemoteKey, false);
