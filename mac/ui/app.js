const state = {
  status: null,
  selectedBackup: "",
  busy: false,
};

const $ = (selector) => document.querySelector(selector);
const $$ = (selector) => Array.from(document.querySelectorAll(selector));

function setBusy(busy) {
  state.busy = busy;
  $$("button").forEach((button) => {
    button.disabled = busy;
  });
}

function log(message, data) {
  const output = $("#logOutput");
  const stamp = new Date().toLocaleTimeString();
  const detail = data ? `\n${typeof data === "string" ? data : JSON.stringify(data, null, 2)}` : "";
  output.textContent = `[${stamp}] ${message}${detail}\n\n${output.textContent}`.trim();
}

async function requestJson(path, options = {}) {
  const response = await fetch(path, {
    headers: { "content-type": "application/json" },
    ...options,
  });
  const data = await response.json();
  return data;
}

async function refreshPrivateUsagiAssets() {
  try {
    const data = await requestJson("/api/private-assets");
    if (!Array.isArray(data.roleAssets) || !data.roleAssets.length) {
      return data;
    }
    const byRole = new Map(data.roleAssets.filter((asset) => asset?.role && asset?.src).map((asset) => [asset.role, asset]));
    $$(".js-usagi-role").forEach((image) => {
      const asset = byRole.get(image.dataset.usagiRole);
      if (!asset) return;
      image.src = `${asset.src}?v=${encodeURIComponent(data.importedAt || asset.sha256 || asset.stickerId || "")}`;
      image.classList.add("private-usagi");
      image.title = `LINE sticker ${asset.stickerId}`;
    });
    return data;
  } catch (error) {
    return { ok: false, error: error.message };
  }
}

async function runAction(action, options = {}) {
  setBusy(true);
  try {
    const data = await requestJson("/api/action", {
      method: "POST",
      body: JSON.stringify({ action, ...options }),
    });
    if (!data.ok) {
      log(`失败：${data.error || action}`, data.stderr || data.stdout || data);
      return data;
    }
    log(`完成：${action}`, data.result);
    await refreshStatus();
    return data;
  } catch (error) {
    log(`异常：${error.message}`);
    return { ok: false, error: error.message };
  } finally {
    setBusy(false);
  }
}

function renderStatus(data) {
  state.status = data.result || data;
  const status = state.status;
  $("#authMode").textContent = status.authMode || "-";
  $("#activeProfile").textContent = status.activeProfile || "-";
  $("#codexRunning").textContent = status.codexRunning ? "运行中" : "已退出";
  $("#baseUrl").textContent = status.openaiBaseUrl || "OpenAI 默认地址";
  $("#baseUrlInput").value = status.openaiBaseUrl || "";
  $("#sessionFiles").textContent = `${status.totalSessionFiles || 0} 个，有效 ${status.validSessionFiles || 0}，异常 ${status.invalidSessionFiles || 0}`;
  $("#indexLines").textContent = `${status.indexLines || 0} 条`;
  $("#providerList").textContent = Object.entries(status.providers || {})
    .map(([name, count]) => `${name}: ${count}`)
    .join("，") || "-";
  renderBackups(status.backups || []);
}

function renderBackups(backups) {
  const list = $("#backupList");
  list.textContent = "";
  if (!backups.length) {
    const empty = document.createElement("div");
    empty.className = "box";
    empty.textContent = "暂无备份。";
    list.append(empty);
    return;
  }
  for (const backup of backups) {
    const item = document.createElement("button");
    item.type = "button";
    item.className = `backup-item${state.selectedBackup === backup.name ? " selected" : ""}`;
    item.innerHTML = `
      <span>
        <strong>${escapeHtml(backup.name)}</strong>
        <small>${escapeHtml(backup.credentialProtection || "history-only")} · ${backup.files || 0} 文件</small>
      </span>
      <small>${escapeHtml(backup.createdAt || "")}</small>
    `;
    item.addEventListener("click", () => {
      state.selectedBackup = backup.name;
      renderBackups(backups);
    });
    list.append(item);
  }
}

async function refreshStatus() {
  const data = await requestJson("/api/status");
  if (!data.ok) {
    log(`状态读取失败：${data.error || "unknown"}`, data);
    return;
  }
  renderStatus(data);
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function selectedBackupOrWarn() {
  if (!state.selectedBackup) {
    log("请先选择一个备份。");
    return "";
  }
  return state.selectedBackup;
}

function confirmAction(title, text) {
  const dialog = $("#confirmDialog");
  $("#confirmTitle").textContent = title;
  $("#confirmText").textContent = text;
  return new Promise((resolve) => {
    dialog.addEventListener("close", () => resolve(dialog.returnValue === "ok"), { once: true });
    dialog.showModal();
  });
}

function setupTabs() {
  $$(".tab").forEach((button) => {
    button.addEventListener("click", () => {
      $$(".tab").forEach((item) => item.classList.toggle("active", item === button));
      $$(".panel").forEach((panel) => panel.classList.toggle("active", panel.id === button.dataset.tab));
      $("#pageTitle").textContent = button.textContent;
    });
  });
}

function setupActions() {
  $("#refreshButton").addEventListener("click", refreshStatus);
  $$("[data-action]").forEach((button) => {
    button.addEventListener("click", async () => {
      const action = button.dataset.action;
      if (button.classList.contains("danger")) {
        const ok = await confirmAction("确认操作", "这个操作会修改登录或配置状态，请确认 Codex Desktop 已完全退出。");
        if (!ok) return;
      }
      await runAction(action);
    });
  });

  $("#saveBaseUrlButton").addEventListener("click", () => {
    runAction("ui-set-base-url", { argument: $("#baseUrlInput").value.trim() });
  });

  $("#apiLoginButton").addEventListener("click", async () => {
    const secret = $("#apiKeyInput").value.trim();
    if (!secret) return log("请输入 API Key。");
    const ok = await confirmAction("API Key 登录", "登录前会先创建完整安全备份，API Key 只通过标准输入传给脚本。");
    if (!ok) return;
    $("#apiKeyInput").value = "";
    await runAction("ui-login-api-key", { secret });
  });

  $("#firstApiLoginButton").addEventListener("click", async () => {
    const secret = $("#apiKeyInput").value.trim();
    if (!secret) return log("请输入 API Key。");
    const ok = await confirmAction("新用户首次登录", "仅在完全没有登录状态的新 Codex Home 使用。登录成功后会创建完整备份。");
    if (!ok) return;
    $("#apiKeyInput").value = "";
    await runAction("ui-first-login-api-key", { secret });
  });

  $("#verifyBackupButton").addEventListener("click", () => {
    const name = selectedBackupOrWarn();
    if (name) runAction("ui-verify-backup", { argument: name });
  });

  $("#restoreBackupButton").addEventListener("click", async () => {
    const name = selectedBackupOrWarn();
    if (!name) return;
    const ok = await confirmAction("恢复备份", "恢复会覆盖当前聊天记录，并在恢复前自动创建完整安全备份。");
    if (!ok) return;
    await runAction("ui-restore-backup", {
      argument: name,
      restoreLogin: $("#restoreLogin").checked,
    });
  });

  $("#compatButton").addEventListener("click", async () => {
    const data = await runAction("ui-api-compatibility", { argument: $("#modelInput").value.trim() });
    $("#compatOutput").textContent = data.ok ? JSON.stringify(data.result, null, 2) : data.error || "检查失败";
  });

  $("#importUsagiButton").addEventListener("click", async () => {
    setBusy(true);
    try {
      log("正在从指定 LINE 页面导入乌萨奇贴图...");
      const data = await requestJson("/api/import-line-usagi", { method: "POST" });
      if (!data.ok) {
        log(`导入失败：${data.error || "unknown"}`, data.stderr || data.stdout || data);
        return;
      }
      await refreshPrivateUsagiAssets();
      log(`导入完成：${data.imported || 0} 张乌萨奇贴图`, data.roleAssets);
    } catch (error) {
      log(`导入异常：${error.message}`);
    } finally {
      setBusy(false);
    }
  });

  $("#quitButton").addEventListener("click", async () => {
    await fetch("/api/quit", { method: "POST" });
    document.body.innerHTML = "<main class='shell'><section class='workspace'><h2>服务已关闭</h2></section></main>";
  });
}

setupTabs();
setupActions();
refreshPrivateUsagiAssets();
refreshStatus().catch((error) => log(`启动失败：${error.message}`));
