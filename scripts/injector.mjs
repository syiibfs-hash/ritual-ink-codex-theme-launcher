import fs from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const scriptPath = fileURLToPath(import.meta.url);
const scriptDir = path.dirname(scriptPath);
const engineRoot = path.resolve(scriptDir, "..");
const assetsDir = path.join(engineRoot, "assets");
const allowedHosts = new Set(["127.0.0.1", "localhost", "::1", "[::1]"]);
const maxArtBytes = 16 * 1024 * 1024;

function parseArgs(argv) {
  const options = {
    mode: "watch",
    port: 9335,
    themeDir: path.join(path.dirname(engineRoot), "active-theme"),
    timeoutMs: 30000,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--watch") options.mode = "watch";
    else if (arg === "--once") options.mode = "once";
    else if (arg === "--verify") options.mode = "verify";
    else if (arg === "--remove") options.mode = "remove";
    else if (arg === "--self-test") options.mode = "self-test";
    else if (arg === "--port") options.port = Number(argv[++index]);
    else if (arg === "--theme-dir") options.themeDir = path.resolve(argv[++index]);
    else if (arg === "--timeout-ms") options.timeoutMs = Number(argv[++index]);
    else throw new Error(`Unknown argument: ${arg}`);
  }
  if (!Number.isInteger(options.port) || options.port < 1024 || options.port > 65535) {
    throw new Error(`Invalid CDP port: ${options.port}`);
  }
  if (!Number.isInteger(options.timeoutMs) || options.timeoutMs < 250 || options.timeoutMs > 120000) {
    throw new Error(`Invalid timeout: ${options.timeoutMs}`);
  }
  return options;
}

async function readJson(filePath, fallback) {
  try {
    return JSON.parse(await fs.readFile(filePath, "utf8"));
  } catch (error) {
    if (error?.code === "ENOENT") return fallback;
    throw error;
  }
}

function mimeFor(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  if (ext === ".svg") return "image/svg+xml";
  if (ext === ".jpg" || ext === ".jpeg") return "image/jpeg";
  if (ext === ".png") return "image/png";
  if (ext === ".webp") return "image/webp";
  if (ext === ".gif") return "image/gif";
  throw new Error(`Unsupported wallpaper type: ${ext}`);
}

async function buildPayload(themeDir) {
  const cssText = await fs.readFile(path.join(assetsDir, "dream-skin.css"), "utf8");
  const rendererSource = await fs.readFile(path.join(assetsDir, "renderer-inject.js"), "utf8");
  const defaultTheme = await readJson(path.join(assetsDir, "theme.json"), {});
  const theme = await readJson(path.join(themeDir, "theme.json"), defaultTheme);
  const configuredImage = typeof theme?.image === "string" && theme.image.trim()
    ? theme.image.trim()
    : null;
  const configuredArtFile = typeof theme?.art?.file === "string" && theme.art.file.trim()
    ? theme.art.file.trim()
    : null;
  const artFile = configuredImage || configuredArtFile || "wallpaper.svg";
  const artPath = path.resolve(themeDir, artFile);
  const themeRoot = path.resolve(themeDir);
  if (!artPath.toLowerCase().startsWith(themeRoot.toLowerCase() + path.sep.toLowerCase())) {
    throw new Error("Wallpaper path must stay inside the active theme directory");
  }
  const stat = await fs.stat(artPath);
  if (!stat.isFile() || stat.size <= 0 || stat.size > maxArtBytes) {
    throw new Error("Wallpaper must be a non-empty image no larger than 16 MB");
  }
  const artBuffer = await fs.readFile(artPath);
  const artDataUrl = `data:${mimeFor(artPath)};base64,${artBuffer.toString("base64")}`;
  if (rendererSource.includes("__DREAM_CSS_JSON__")) {
    return `;${rendererSource
      .replaceAll("__DREAM_CSS_JSON__", JSON.stringify(cssText))
      .replaceAll("__DREAM_ART_JSON__", JSON.stringify(artDataUrl))
      .replaceAll("__DREAM_THEME_JSON__", JSON.stringify(theme))};`;
  }
  return `;(${rendererSource})(${JSON.stringify(cssText)}, ${JSON.stringify(artDataUrl)}, ${JSON.stringify(theme)});`;
}

async function getJson(url, timeoutMs = 4000) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, { signal: controller.signal });
    if (!response.ok) throw new Error(`${response.status} ${response.statusText}`);
    return await response.json();
  } finally {
    clearTimeout(timer);
  }
}

function validWebSocketUrl(value, port) {
  const url = new URL(value);
  return url.protocol === "ws:" &&
    allowedHosts.has(url.hostname) &&
    Number(url.port) === port &&
    /^\/devtools\/page\/[A-Za-z0-9._-]{1,200}$/.test(url.pathname) &&
    !url.username &&
    !url.password &&
    !url.search &&
    !url.hash;
}

async function listTargets(port) {
  const targets = await getJson(`http://127.0.0.1:${port}/json/list`, 2500);
  return targets.filter((target) => {
    if (target?.type !== "page" || typeof target.url !== "string" || !target.url.startsWith("app://")) {
      return false;
    }
    if (typeof target.id !== "string" || !/^[A-Za-z0-9._-]{1,200}$/.test(target.id)) return false;
    if (typeof target.webSocketDebuggerUrl !== "string") return false;
    try {
      return validWebSocketUrl(target.webSocketDebuggerUrl, port);
    } catch {
      return false;
    }
  });
}

class CdpSession {
  constructor(target, port) {
    if (!validWebSocketUrl(target.webSocketDebuggerUrl, port)) {
      throw new Error("Rejected non-loopback CDP WebSocket URL");
    }
    this.target = target;
    this.socket = new WebSocket(target.webSocketDebuggerUrl);
    this.nextId = 1;
    this.pending = new Map();
    this.closed = false;
    this.socket.addEventListener("message", (event) => this.onMessage(event.data));
    this.socket.addEventListener("close", () => {
      this.closed = true;
      for (const { reject } of this.pending.values()) reject(new Error("CDP socket closed"));
      this.pending.clear();
    });
  }

  async open() {
    await new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error("CDP socket open timed out")), 5000);
      this.socket.addEventListener("open", () => {
        clearTimeout(timer);
        resolve();
      }, { once: true });
      this.socket.addEventListener("error", () => {
        clearTimeout(timer);
        reject(new Error("CDP socket open failed"));
      }, { once: true });
    });
  }

  onMessage(data) {
    let message;
    try {
      message = JSON.parse(String(data));
    } catch {
      return;
    }
    if (!message.id || !this.pending.has(message.id)) return;
    const { resolve, reject } = this.pending.get(message.id);
    this.pending.delete(message.id);
    if (message.error) reject(new Error(message.error.message || "CDP command failed"));
    else resolve(message.result);
  }

  send(method, params = {}) {
    if (this.closed) return Promise.reject(new Error("CDP socket is closed"));
    const id = this.nextId++;
    const payload = JSON.stringify({ id, method, params });
    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.socket.send(payload);
      setTimeout(() => {
        if (!this.pending.has(id)) return;
        this.pending.delete(id);
        reject(new Error(`CDP command timed out: ${method}`));
      }, 8000);
    });
  }

  close() {
    try {
      this.socket.close();
    } catch {
      this.closed = true;
    }
  }
}

async function withSession(target, port, callback) {
  const session = new CdpSession(target, port);
  await session.open();
  try {
    await session.send("Runtime.enable");
    await session.send("Page.enable");
    return await callback(session);
  } finally {
    session.close();
  }
}

async function injectTarget(target, port, payload) {
  return withSession(target, port, async (session) => {
    await session.send("Page.addScriptToEvaluateOnNewDocument", { source: payload });
    await session.send("Runtime.evaluate", {
      expression: payload,
      awaitPromise: false,
      returnByValue: true
    });
  });
}

async function removeTarget(target, port) {
  return withSession(target, port, async (session) => {
    await session.send("Runtime.evaluate", {
      expression: "window.__CODEX_DREAM_SKIN_STATE__?.cleanup?.(); window.__CODEX_THEME_LAUNCHER_REMOVE__?.(); true;",
      awaitPromise: false,
      returnByValue: true
    });
  });
}

async function verifyTarget(target, port) {
  return withSession(target, port, async (session) => {
    const result = await session.send("Runtime.evaluate", {
      expression: "Boolean((document.documentElement.classList.contains('codex-dream-skin') && document.getElementById('codex-dream-skin-style')) || (document.documentElement.classList.contains('codex-theme-launcher-active') && document.getElementById('codex-theme-launcher-style')))",
      awaitPromise: false,
      returnByValue: true
    });
    return Boolean(result?.result?.value);
  });
}

async function once(options) {
  const payload = await buildPayload(options.themeDir);
  const targets = await listTargets(options.port);
  if (targets.length === 0) throw new Error("No Codex renderer target is available");
  await Promise.all(targets.map((target) => injectTarget(target, options.port, payload)));
  console.log(`Injected Codex skin into ${targets.length} renderer target(s).`);
}

async function remove(options) {
  const targets = await listTargets(options.port);
  await Promise.allSettled(targets.map((target) => removeTarget(target, options.port)));
  console.log(`Removed live Codex skin from ${targets.length} renderer target(s).`);
}

async function verify(options) {
  const deadline = Date.now() + options.timeoutMs;
  while (Date.now() < deadline) {
    const targets = await listTargets(options.port).catch(() => []);
    for (const target of targets) {
      if (await verifyTarget(target, options.port).catch(() => false)) {
        console.log("Codex skin injection marker is present.");
        return;
      }
    }
    await new Promise((resolve) => setTimeout(resolve, 500));
  }
  throw new Error("Codex skin injection marker was not found before timeout");
}

async function watch(options) {
  let payload = await buildPayload(options.themeDir);
  const injected = new Map();
  let lastPayloadRefresh = Date.now();
  while (true) {
    if (Date.now() - lastPayloadRefresh > 5000) {
      payload = await buildPayload(options.themeDir);
      lastPayloadRefresh = Date.now();
    }
    const targets = await listTargets(options.port).catch(() => []);
    for (const target of targets) {
      const key = `${target.id}:${target.url}`;
      if (injected.get(key) === payload) continue;
      try {
        await injectTarget(target, options.port, payload);
        injected.set(key, payload);
      } catch (error) {
        console.error(`Injection failed for ${target.id}: ${error.message}`);
      }
    }
    for (const key of [...injected.keys()]) {
      if (!targets.some((target) => `${target.id}:${target.url}` === key)) injected.delete(key);
    }
    await new Promise((resolve) => setTimeout(resolve, 1200));
  }
}

async function selfTest(options) {
  await buildPayload(options.themeDir);
  console.log("Payload build succeeded.");
}

const options = parseArgs(process.argv.slice(2));
try {
  if (options.mode === "once") await once(options);
  else if (options.mode === "remove") await remove(options);
  else if (options.mode === "verify") await verify(options);
  else if (options.mode === "self-test") await selfTest(options);
  else await watch(options);
} catch (error) {
  console.error(error?.stack || error?.message || String(error));
  process.exitCode = 1;
}
