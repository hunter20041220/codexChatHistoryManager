import fs from "node:fs";
import path from "node:path";
import crypto from "node:crypto";
import os from "node:os";

const codexHome = process.env.CODEX_HOME || path.join(os.homedir(), ".codex");
const backupRoot = path.join(codexHome, "chat-history-backups");
const action = process.argv[2] || "status";
const argument = process.argv[3] || "";
const credentialPackages = [
  { name: "credentials.dpapi.json", protection: "windows-dpapi-current-user" },
  { name: "credentials.keychain.json", protection: "macos-keychain-current-user" },
];

const historyItems = [
  "sessions",
  "archived_sessions",
  "attachments",
  "session_index.jsonl",
  ".codex-global-state.json",
  "state_5.sqlite",
  "goals_1.sqlite",
];

function walkFiles(root) {
  if (!fs.existsSync(root)) return [];
  const stat = fs.statSync(root);
  if (stat.isFile()) return [root];
  const output = [];
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    const fullPath = path.join(root, entry.name);
    if (entry.isDirectory()) output.push(...walkFiles(fullPath));
    if (entry.isFile()) output.push(fullPath);
  }
  return output;
}

function hashFile(filePath) {
  const hash = crypto.createHash("sha256");
  hash.update(fs.readFileSync(filePath));
  return hash.digest("hex");
}

function copyTree(source, destination) {
  if (!fs.existsSync(source)) return;
  const stat = fs.statSync(source);
  if (stat.isDirectory()) {
    fs.mkdirSync(destination, { recursive: true });
    for (const entry of fs.readdirSync(source)) {
      copyTree(path.join(source, entry), path.join(destination, entry));
    }
    return;
  }
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.copyFileSync(source, destination);
}

function sessionMetadata() {
  const sessionRoot = path.join(codexHome, "sessions");
  const rows = [];
  for (const filePath of walkFiles(sessionRoot).filter((file) => file.endsWith(".jsonl"))) {
    try {
      const firstLine = fs.readFileSync(filePath, "utf8").split(/\r?\n/, 1)[0];
      const record = JSON.parse(firstLine);
      if (record.type !== "session_meta") continue;
      rows.push({
        id: record.payload?.id || "",
        provider: record.payload?.model_provider || "",
        threadSource: record.payload?.thread_source || "",
        filePath,
      });
    } catch (error) {
      rows.push({ filePath, error: error.message });
    }
  }
  return rows;
}

function readDesktopProvider() {
  const configPath = path.join(codexHome, "config.toml");
  if (!fs.existsSync(configPath)) return "";
  const lines = fs.readFileSync(configPath, "utf8").split(/\r?\n/);
  let section = "";
  for (const line of lines) {
    const sectionMatch = line.match(/^\s*\[([^\]]+)\]\s*$/);
    if (sectionMatch) {
      section = sectionMatch[1];
      continue;
    }
    if (section === "desktop") {
      const providerMatch = line.match(/^\s*model_provider\s*=\s*"([^"]+)"/);
      if (providerMatch) return providerMatch[1];
    }
  }
  return "";
}

function status() {
  const rows = sessionMetadata();
  const providers = {};
  const sources = {};
  for (const row of rows.filter((item) => !item.error)) {
    providers[row.provider || "(none)"] = (providers[row.provider || "(none)"] || 0) + 1;
    sources[row.threadSource || "(none)"] = (sources[row.threadSource || "(none)"] || 0) + 1;
  }
  const indexPath = path.join(codexHome, "session_index.jsonl");
  const indexLines = fs.existsSync(indexPath)
    ? fs.readFileSync(indexPath, "utf8").split(/\r?\n/).filter(Boolean).length
    : 0;
  return {
    codexHome,
    desktopProvider: readDesktopProvider(),
    openaiBaseUrl: readTopLevelSetting("openai_base_url"),
    totalSessionFiles: rows.length,
    validSessionFiles: rows.filter((item) => !item.error).length,
    invalidSessionFiles: rows.filter((item) => item.error).length,
    indexLines,
    providers,
    threadSources: sources,
  };
}

function readTopLevelSetting(settingName) {
  const configPath = path.join(codexHome, "config.toml");
  if (!fs.existsSync(configPath)) return "";
  const lines = fs.readFileSync(configPath, "utf8").split(/\r?\n/);
  let section = "";
  for (const line of lines) {
    const sectionMatch = line.match(/^\s*\[([^\]]+)\]\s*$/);
    if (sectionMatch) {
      section = sectionMatch[1];
      continue;
    }
    if (!section) {
      const match = line.match(new RegExp(`^\\s*${settingName}\\s*=\\s*"([^"]*)"`));
      if (match) return match[1];
    }
  }
  return "";
}

async function createBackup(label = "manual") {
  const { backup: sqliteBackup, DatabaseSync } = await import("node:sqlite");
  fs.mkdirSync(backupRoot, { recursive: true });
  const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
  const destination = path.join(backupRoot, `${timestamp}-${label}`);
  fs.mkdirSync(destination, { recursive: true });

  for (const item of historyItems) {
    const source = path.join(codexHome, item);
    const target = path.join(destination, item);
    if (!fs.existsSync(source)) continue;
    if (item.endsWith(".sqlite")) {
      const database = new DatabaseSync(source, { readOnly: true });
      try {
        await sqliteBackup(database, target);
      } finally {
        database.close();
      }
    } else {
      copyTree(source, target);
    }
  }

  const manifestFiles = walkFiles(destination)
    .filter((file) => path.basename(file) !== "manifest.json")
    .map((file) => ({
      path: path.relative(destination, file).replaceAll("\\", "/"),
      bytes: fs.statSync(file).size,
      sha256: hashFile(file),
    }));
  const manifest = {
    version: 1,
    createdAt: new Date().toISOString(),
    codexHome,
    credentialProtection: "none",
    status: status(),
    files: manifestFiles,
  };
  fs.writeFileSync(
    path.join(destination, "manifest.json"),
    JSON.stringify(manifest, null, 2),
    "utf8",
  );
  return { destination, files: manifestFiles.length };
}

function refreshManifest(backupName) {
  const destination = path.join(backupRoot, backupName);
  const manifestPath = path.join(destination, "manifest.json");
  const previous = fs.existsSync(manifestPath)
    ? JSON.parse(fs.readFileSync(manifestPath, "utf8"))
    : {};
  const manifestFiles = walkFiles(destination)
    .filter((file) => path.basename(file) !== "manifest.json")
    .map((file) => ({
      path: path.relative(destination, file).replaceAll("\\", "/"),
      bytes: fs.statSync(file).size,
      sha256: hashFile(file),
    }));
  const detectedCredentialPackages = credentialPackages.filter((credentialPackage) =>
    manifestFiles.some((item) => item.path === credentialPackage.name),
  );
  const manifest = {
    ...previous,
    version: 2,
    credentialProtection:
      detectedCredentialPackages.length === 1
        ? detectedCredentialPackages[0].protection
        : detectedCredentialPackages.length > 1
          ? "multiple"
          : "none",
    files: manifestFiles,
  };
  fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2), "utf8");
  return {
    backupName,
    files: manifestFiles.length,
    hasCredentials: detectedCredentialPackages.length > 0,
    credentialProtection: manifest.credentialProtection,
  };
}

function listBackups() {
  if (!fs.existsSync(backupRoot)) return [];
  return fs.readdirSync(backupRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => {
      const directory = path.join(backupRoot, entry.name);
      const manifestPath = path.join(directory, "manifest.json");
      let manifest = null;
      try {
        manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
      } catch {}
      return {
        name: entry.name,
        path: directory,
        createdAt: manifest?.createdAt || "",
        files: manifest?.files?.length || 0,
        credentialProtection: manifest?.credentialProtection || "none",
      };
    })
    .sort((left, right) => right.name.localeCompare(left.name));
}

function setOpenAiBaseUrl(baseUrl) {
  let normalized = baseUrl.trim();
  if (normalized && !/^https?:\/\//i.test(normalized)) {
    throw new Error("Base URL must start with http:// or https://");
  }
  normalized = normalized.replace(/\/+$/, "");
  const configPath = path.join(codexHome, "config.toml");
  const original = fs.readFileSync(configPath, "utf8");
  const lines = original.split(/\r?\n/);
  let section = "";
  let settingIndex = -1;
  let firstSectionIndex = lines.length;
  for (let index = 0; index < lines.length; index += 1) {
    const sectionMatch = lines[index].match(/^\s*\[([^\]]+)\]\s*$/);
    if (sectionMatch) {
      if (firstSectionIndex === lines.length) firstSectionIndex = index;
      section = sectionMatch[1];
      continue;
    }
    if (!section && /^\s*openai_base_url\s*=/.test(lines[index])) {
      settingIndex = index;
    }
  }
  if (settingIndex >= 0) {
    if (normalized) lines[settingIndex] = `openai_base_url = "${normalized.replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`;
    else lines.splice(settingIndex, 1);
  } else if (normalized) {
    lines.splice(firstSectionIndex, 0, `openai_base_url = "${normalized.replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`);
  }
  const backupPath = `${configPath}.history-manager-${Date.now()}.bak`;
  fs.copyFileSync(configPath, backupPath);
  fs.writeFileSync(configPath, lines.join("\r\n"), "utf8");
  const unified = setUnifiedDesktopProvider();
  return { baseUrl: normalized, backupPath, providerChanged: unified.changed };
}

function verifyBackup(backupName) {
  const directory = path.join(backupRoot, backupName);
  const manifest = JSON.parse(fs.readFileSync(path.join(directory, "manifest.json"), "utf8"));
  const failures = [];
  for (const item of manifest.files) {
    const filePath = path.join(directory, item.path);
    if (!fs.existsSync(filePath)) {
      failures.push(`${item.path}: missing`);
      continue;
    }
    if (fs.statSync(filePath).size !== item.bytes || hashFile(filePath) !== item.sha256) {
      failures.push(`${item.path}: checksum mismatch`);
    }
  }
  return { backupName, checked: manifest.files.length, failures };
}

async function restoreBackup(backupName) {
  const directory = path.join(backupRoot, backupName);
  const verification = verifyBackup(backupName);
  if (verification.failures.length) {
    throw new Error(`Backup verification failed: ${verification.failures.join("; ")}`);
  }

  const safety = await createBackup("before-restore");
  for (const item of historyItems) {
    const source = path.join(directory, item);
    const target = path.join(codexHome, item);
    if (!fs.existsSync(source)) continue;
    if (fs.existsSync(target)) fs.rmSync(target, { recursive: true, force: true });
    copyTree(source, target);
  }
  return { restoredFrom: directory, safetyBackup: safety.destination };
}

async function normalizeProvider(provider) {
  if (!/^[A-Za-z0-9_.-]+$/.test(provider)) {
    throw new Error("Invalid provider name.");
  }
  const safety = await createBackup(`before-provider-${provider}`);
  let changed = 0;
  for (const row of sessionMetadata()) {
    if (row.error) throw new Error(`${row.filePath}: ${row.error}`);
    const text = fs.readFileSync(row.filePath, "utf8");
    const newlineIndex = text.indexOf("\n");
    const firstLine = newlineIndex >= 0 ? text.slice(0, newlineIndex).replace(/\r$/, "") : text;
    const rest = newlineIndex >= 0 ? text.slice(newlineIndex) : "";
    const record = JSON.parse(firstLine);
    if (record.payload?.model_provider === provider) continue;
    record.payload.model_provider = provider;
    fs.writeFileSync(row.filePath, `${JSON.stringify(record)}${rest}`, "utf8");
    changed += 1;
  }
  return { provider, changed, safetyBackup: safety.destination };
}

function setUnifiedDesktopProvider() {
  const configPath = path.join(codexHome, "config.toml");
  const original = fs.readFileSync(configPath, "utf8");
  const lines = original.split(/\r?\n/);
  let section = "";
  let changed = false;
  let found = false;
  for (let index = 0; index < lines.length; index += 1) {
    const sectionMatch = lines[index].match(/^\s*\[([^\]]+)\]\s*$/);
    if (sectionMatch) {
      section = sectionMatch[1];
      continue;
    }
    if (section === "desktop" && /^\s*model_provider\s*=/.test(lines[index])) {
      found = true;
      if (lines[index].trim() !== 'model_provider = "openai"') {
        lines[index] = 'model_provider = "openai"';
        changed = true;
      }
    }
  }
  if (!found) {
    const desktopIndex = lines.findIndex((line) => /^\s*\[desktop\]\s*$/.test(line));
    if (desktopIndex < 0) {
      lines.push("", "[desktop]", 'model_provider = "openai"');
    } else {
      lines.splice(desktopIndex + 1, 0, 'model_provider = "openai"');
    }
    changed = true;
  }
  if (changed) {
    const backupPath = `${configPath}.history-manager-${Date.now()}.bak`;
    fs.copyFileSync(configPath, backupPath);
    fs.writeFileSync(configPath, lines.join("\r\n"), "utf8");
    return { changed, backupPath };
  }
  return { changed: false };
}

let result;
switch (action) {
  case "status":
    result = status();
    break;
  case "backup":
    result = await createBackup(argument || "manual");
    break;
  case "list":
    result = listBackups();
    break;
  case "verify":
    result = verifyBackup(argument);
    break;
  case "refresh-manifest":
    result = refreshManifest(argument);
    break;
  case "restore":
    result = await restoreBackup(argument);
    break;
  case "normalize-provider":
    result = await normalizeProvider(argument);
    break;
  case "unify-config":
    result = setUnifiedDesktopProvider();
    break;
  case "set-base-url":
    result = setOpenAiBaseUrl(argument);
    break;
  default:
    throw new Error(`Unknown action: ${action}`);
}

process.stdout.write(`${JSON.stringify(result, null, 2)}\n`);
