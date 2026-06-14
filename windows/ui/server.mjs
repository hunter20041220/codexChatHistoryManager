import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import { dirname, extname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import os from "node:os";

const uiDir = dirname(fileURLToPath(import.meta.url));
const toolDir = resolve(uiDir, "..");
const isWindows = process.platform === "win32";
const scriptPath = isWindows
  ? join(toolDir, "Codex-History-Manager.ps1")
  : join(toolDir, "Codex-History-Manager.sh");
const usagiManifestPath = join(uiDir, "private-assets", "line-usagi", "manifest.json");
const bundledUsagiManifestPath = join(uiDir, "assets", "line-usagi", "manifest.json");
const importUsagiScript = join(uiDir, "import-line-usagi.mjs");

const mimeTypes = {
  ".html": "text/html; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".ico": "image/x-icon",
};

function sendJson(res, status, body) {
  res.writeHead(status, {
    "content-type": "application/json; charset=utf-8",
    "cache-control": "no-store",
  });
  res.end(JSON.stringify(body, null, 2));
}

function readRequestJson(req) {
  return new Promise((resolveRequest, reject) => {
    let body = "";
    req.setEncoding("utf8");
    req.on("data", (chunk) => {
      body += chunk;
      if (body.length > 2_000_000) {
        reject(new Error("Request body is too large."));
        req.destroy();
      }
    });
    req.on("end", () => {
      if (!body.trim()) {
        resolveRequest({});
        return;
      }
      try {
        resolveRequest(JSON.parse(body));
      } catch (error) {
        reject(error);
      }
    });
    req.on("error", reject);
  });
}

function extractJson(stdout) {
  const text = String(stdout || "").trim();
  if (!text) return null;
  const markers = ["{\n  \"ok\"", "{\"ok\""];
  for (const marker of markers) {
    const index = text.lastIndexOf(marker);
    if (index >= 0) {
      try {
        return JSON.parse(text.slice(index));
      } catch {
        // Continue to fallback.
      }
    }
  }
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

function runManager(action, { argument = "", restoreLogin = false, secret = "" } = {}) {
  return new Promise((resolveRun) => {
    const args = isWindows
      ? [
          "-NoProfile",
          "-ExecutionPolicy",
          "Bypass",
          "-File",
          scriptPath,
          "-Action",
          action,
          "-Argument",
          argument || "",
        ]
      : [scriptPath, "--action", action, "--argument", argument || ""];

    if (restoreLogin) {
      if (isWindows) args.push("-RestoreLogin");
      else args.push("--restore-login");
    }

    const command = isWindows ? "powershell.exe" : "bash";
    const child = spawn(command, args, {
      cwd: toolDir,
      windowsHide: true,
      stdio: ["pipe", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.on("error", (error) => {
      resolveRun({
        ok: false,
        action,
        error: error.message,
        stdout,
        stderr,
      });
    });
    child.on("close", (code) => {
      const parsed = extractJson(stdout);
      if (parsed) {
        parsed.exitCode = code;
        parsed.stdout = stdout;
        parsed.stderr = stderr;
        resolveRun(parsed);
        return;
      }
      resolveRun({
        ok: code === 0,
        action,
        exitCode: code,
        error: code === 0 ? "" : stderr.trim() || stdout.trim() || `Action failed with exit code ${code}.`,
        stdout,
        stderr,
      });
    });

    if (secret) child.stdin.end(`${secret}\n`);
    else child.stdin.end();
  });
}

async function readUsagiManifest() {
  for (const [kind, manifestPath] of [
    ["private", usagiManifestPath],
    ["bundled", bundledUsagiManifestPath],
  ]) {
    try {
      const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
      return {
        ok: true,
        kind,
        sourcePage: manifest.sourcePage,
        pageTitle: manifest.pageTitle,
        importedAt: manifest.importedAt || manifest.bundledAt || "",
        assets: Array.isArray(manifest.assets) ? manifest.assets : [],
        roleAssets: Array.isArray(manifest.roleAssets) ? manifest.roleAssets : [],
      };
    } catch {
      // Try the next manifest source.
    }
  }
  return {
    ok: true,
    kind: "none",
    sourcePage: "https://store.line.me/stickershop/product/21802595/ja",
    pageTitle: "ちいかわ(うさぎ多)",
    importedAt: "",
    assets: [],
    roleAssets: [],
  };
}

function runUsagiImporter() {
  return new Promise((resolveRun) => {
    const nodeExe = process.execPath;
    const child = spawn(nodeExe, [importUsagiScript], {
      cwd: uiDir,
      windowsHide: true,
      stdio: ["ignore", "pipe", "pipe"],
    });

    let stdout = "";
    let stderr = "";
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      stdout += chunk;
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk;
    });
    child.on("error", (error) => {
      resolveRun({ ok: false, error: error.message, stdout, stderr });
    });
    child.on("close", async (code) => {
      const parsed = extractJson(stdout);
      if (code === 0 && parsed?.ok) {
        const manifest = await readUsagiManifest();
        resolveRun({ ...parsed, manifest, stdout, stderr, exitCode: code });
        return;
      }
      resolveRun({
        ok: false,
        error: parsed?.error || stderr.trim() || stdout.trim() || `Importer failed with exit code ${code}.`,
        stdout,
        stderr,
        exitCode: code,
      });
    });
  });
}

function findBrowserCommand(url) {
  if (process.env.CHMM_NO_BROWSER === "1") return null;
  if (isWindows) {
    const edgeCandidates = [
      join(process.env.ProgramFiles || "C:\\Program Files", "Microsoft\\Edge\\Application\\msedge.exe"),
      join(process.env["ProgramFiles(x86)"] || "C:\\Program Files (x86)", "Microsoft\\Edge\\Application\\msedge.exe"),
      join(process.env.LOCALAPPDATA || "", "Microsoft\\Edge\\Application\\msedge.exe"),
    ].filter(Boolean);
    for (const candidate of edgeCandidates) {
      if (existsSync(candidate)) {
        return { command: candidate, args: [`--app=${url}`] };
      }
    }
    return { command: "cmd.exe", args: ["/c", "start", "", url] };
  }
  if (process.platform === "darwin") {
    return { command: "open", args: ["-na", "Microsoft Edge", "--args", `--app=${url}`] };
  }
  return { command: "xdg-open", args: [url] };
}

function openBrowser(url) {
  const command = findBrowserCommand(url);
  if (!command) return;
  const child = spawn(command.command, command.args, {
    detached: true,
    stdio: "ignore",
    windowsHide: true,
  });
  child.unref();
}

const server = createServer(async (req, res) => {
  try {
    const url = new URL(req.url || "/", "http://127.0.0.1");
    if (req.method === "GET" && url.pathname === "/api/status") {
      sendJson(res, 200, await runManager("ui-status"));
      return;
    }
    if (req.method === "GET" && url.pathname === "/api/private-assets") {
      sendJson(res, 200, await readUsagiManifest());
      return;
    }
    if (req.method === "POST" && url.pathname === "/api/import-line-usagi") {
      sendJson(res, 200, await runUsagiImporter());
      return;
    }
    if (req.method === "POST" && url.pathname === "/api/action") {
      const body = await readRequestJson(req);
      if (!body.action || !String(body.action).startsWith("ui-")) {
        sendJson(res, 400, { ok: false, error: "Invalid action." });
        return;
      }
      sendJson(res, 200, await runManager(String(body.action), {
        argument: String(body.argument || ""),
        restoreLogin: Boolean(body.restoreLogin),
        secret: String(body.secret || ""),
      }));
      return;
    }
    if (req.method === "POST" && url.pathname === "/api/quit") {
      sendJson(res, 200, { ok: true });
      setTimeout(() => process.exit(0), 120);
      return;
    }

    let filePath = url.pathname === "/" ? join(uiDir, "index.html") : join(uiDir, decodeURIComponent(url.pathname));
    filePath = resolve(filePath);
    if (!filePath.startsWith(uiDir)) {
      res.writeHead(403);
      res.end("Forbidden");
      return;
    }
    const content = await readFile(filePath);
    res.writeHead(200, {
      "content-type": mimeTypes[extname(filePath)] || "application/octet-stream",
      "cache-control": "no-store",
    });
    res.end(content);
  } catch (error) {
    sendJson(res, 500, { ok: false, error: error.message });
  }
});

server.listen(0, "127.0.0.1", () => {
  const address = server.address();
  const url = `http://127.0.0.1:${address.port}/`;
  console.log(`Codex-Chat-History-Manager: ${url}`);
  openBrowser(url);
});

process.on("SIGTERM", () => process.exit(0));
process.on("SIGINT", () => process.exit(0));
