import { execFile } from "node:child_process";
import { createHash } from "node:crypto";
import { mkdir, rename, rm, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

const SOURCE_PAGE = "https://store.line.me/stickershop/product/21802595/ja";
const PAGE_TITLE = "ちいかわ(うさぎ多)";
const USER_AGENT =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " +
  "(KHTML, like Gecko) Chrome/125.0 Safari/537.36";
const FETCH_TIMEOUT_MS = Number.parseInt(process.env.USAGI_IMPORT_TIMEOUT_MS || "30000", 10);

const uiDir = dirname(fileURLToPath(import.meta.url));
const assetRoot = join(uiDir, "private-assets", "line-usagi");
const manifestPath = join(assetRoot, "manifest.json");

// Manually selected from the public sticker previews on SOURCE_PAGE.
// Kept only when Usagi is the main subject; non-Usagi and tiny-side-character
// previews from the same page are intentionally excluded.
const SELECTED_STICKERS = [
  { id: "556658118", file: "usagi-556658118.png" },
  { id: "556658119", file: "usagi-556658119.png" },
  { id: "556658120", file: "usagi-556658120.png" },
  { id: "556658121", file: "usagi-556658121.png" },
  { id: "556658122", file: "usagi-556658122.png" },
  { id: "556658123", file: "usagi-556658123.png" },
  { id: "556658124", file: "usagi-556658124.png" },
  { id: "556658125", file: "usagi-556658125.png" },
  { id: "556658126", file: "usagi-556658126.png" },
  { id: "556658128", file: "usagi-556658128.png" },
  { id: "556658129", file: "usagi-556658129.png" },
  { id: "556658130", file: "usagi-556658130.png" },
  { id: "556658131", file: "usagi-556658131.png" },
  { id: "556658149", file: "usagi-556658149.png" },
  { id: "556658150", file: "usagi-556658150.png" },
  { id: "556658151", file: "usagi-556658151.png" },
  { id: "556658152", file: "usagi-556658152.png" },
  { id: "556658154", file: "usagi-556658154.png" },
  { id: "556658155", file: "usagi-556658155.png" },
];

const ROLE_ASSETS = [
  { role: "brand", id: "556658123" },
  { role: "hero", id: "556658122" },
  { role: "backup", id: "556658125" },
  { role: "login", id: "556658119" },
  { role: "network", id: "556658152" },
  { role: "tools", id: "556658154" },
];

function timeoutSignal(ms) {
  if (typeof AbortSignal !== "undefined" && typeof AbortSignal.timeout === "function") {
    return AbortSignal.timeout(ms);
  }
  const controller = new AbortController();
  setTimeout(() => controller.abort(), ms).unref?.();
  return controller.signal;
}

async function fetchWithNode(url, { binary = false } = {}) {
  const response = await fetch(url, {
    headers: {
      "user-agent": USER_AGENT,
      referer: SOURCE_PAGE,
    },
    signal: timeoutSignal(FETCH_TIMEOUT_MS),
  });
  if (!response.ok) {
    throw new Error(`HTTP ${response.status} ${response.statusText}`);
  }
  if (binary) {
    return Buffer.from(await response.arrayBuffer());
  }
  return response.text();
}

async function fetchWithCurl(url, { binary = false } = {}) {
  const curl = process.platform === "win32" ? "curl.exe" : "curl";
  const args = [
    "-L",
    "-f",
    "--retry",
    "3",
    "--retry-delay",
    "2",
    "--connect-timeout",
    "12",
    "--max-time",
    String(Math.max(20, Math.ceil(FETCH_TIMEOUT_MS / 1000))),
    "-A",
    USER_AGENT,
    "-e",
    SOURCE_PAGE,
    url,
  ];
  const { stdout } = await execFileAsync(curl, args, {
    encoding: binary ? "buffer" : "utf8",
    maxBuffer: 30 * 1024 * 1024,
    windowsHide: true,
  });
  return Buffer.isBuffer(stdout) ? stdout : String(stdout);
}

async function fetchAllowedUrl(url, options = {}) {
  try {
    return await fetchWithNode(url, options);
  } catch (nodeError) {
    try {
      return await fetchWithCurl(url, options);
    } catch (curlError) {
      throw new Error(`Failed to fetch ${url}: ${nodeError.message}; curl fallback: ${curlError.message}`);
    }
  }
}

function parseStickerUrls(html) {
  const pattern =
    /https:\/\/stickershop\.line-scdn\.net\/stickershop\/v1\/sticker\/(\d+)\/android\/sticker\.png\?v=1/g;
  const urls = new Map();
  for (const match of html.matchAll(pattern)) {
    urls.set(match[1], match[0]);
  }
  return urls;
}

async function importUsagiStickers() {
  const html = await fetchAllowedUrl(SOURCE_PAGE);
  const stickerUrls = parseStickerUrls(html);
  if (!stickerUrls.size) {
    throw new Error("The approved LINE Store page did not contain public sticker previews. It may be temporarily unavailable.");
  }
  const missing = SELECTED_STICKERS.filter((item) => !stickerUrls.has(item.id)).map((item) => item.id);
  if (missing.length) {
    throw new Error(`Selected sticker previews were not found on the approved page: ${missing.join(", ")}`);
  }

  const tempRoot = join(dirname(assetRoot), `.line-usagi-tmp-${Date.now()}`);
  await mkdir(tempRoot, { recursive: true });

  const imported = [];
  try {
    for (const item of SELECTED_STICKERS) {
      const url = stickerUrls.get(item.id);
      const content = await fetchAllowedUrl(url, { binary: true });
      const hash = createHash("sha256").update(content).digest("hex");
      await writeFile(join(tempRoot, item.file), content);
      imported.push({
        stickerId: item.id,
        file: item.file,
        src: `./private-assets/line-usagi/${item.file}`,
        sourceUrl: url,
        sha256: hash,
      });
    }

    await rm(assetRoot, { recursive: true, force: true });
    await mkdir(dirname(assetRoot), { recursive: true });
    await rename(tempRoot, assetRoot);

    const byId = new Map(imported.map((item) => [item.stickerId, item]));
    const manifest = {
      ok: true,
      sourcePage: SOURCE_PAGE,
      pageTitle: PAGE_TITLE,
      usage: "Local personal learning and UI prototype only. Official sticker previews are not bundled in this repository.",
      selectedRule: "Only public previews from the approved LINE Store page where Usagi is the main subject.",
      importedAt: new Date().toISOString(),
      assets: imported,
      roleAssets: ROLE_ASSETS.map((roleAsset) => ({
        role: roleAsset.role,
        ...byId.get(roleAsset.id),
      })),
    };
    await writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, "utf8");
    return manifest;
  } catch (error) {
    await rm(tempRoot, { recursive: true, force: true });
    throw error;
  }
}

try {
  const manifest = await importUsagiStickers();
  process.stdout.write(
    `${JSON.stringify({
      ok: true,
      sourcePage: manifest.sourcePage,
      imported: manifest.assets.length,
      roleAssets: manifest.roleAssets.map((asset) => ({
        role: asset.role,
        stickerId: asset.stickerId,
        src: asset.src,
      })),
      manifestPath,
    })}\n`,
  );
} catch (error) {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.stdout.write(`${JSON.stringify({ ok: false, error: error.message })}\n`);
  process.exit(1);
}
