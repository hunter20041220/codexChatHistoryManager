#!/usr/bin/env bash

set -u
set -o pipefail

ACTION="menu"
while [ "$#" -gt 0 ]; do
  case "$1" in
    -Action|--action)
      ACTION="${2:-menu}"
      shift 2
      ;;
    menu|status|backup|help|profiles|save-chatgpt|first-login|export-tool)
      ACTION="$1"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
TOOL_DIRECTORY="${CODEX_HISTORY_MANAGER_HOME:-$CODEX_HOME_DIR/tools/history-manager-mac}"
CORE_SCRIPT="$TOOL_DIRECTORY/codex-history-core.mjs"
if [ ! -f "$CORE_SCRIPT" ] && [ -f "$SCRIPT_DIR/codex-history-core.mjs" ]; then
  TOOL_DIRECTORY="$SCRIPT_DIR"
  CORE_SCRIPT="$SCRIPT_DIR/codex-history-core.mjs"
fi

BACKUP_DIRECTORY="$CODEX_HOME_DIR/chat-history-backups"
PROFILE_DIRECTORY="$CODEX_HOME_DIR/login-profiles"
CREDENTIAL_IMPORT_DIRECTORY="$CODEX_HOME_DIR/credential-import"
CREDENTIAL_PACKAGE_NAME="credentials.keychain.json"
CREDENTIAL_FILES=("auth.json" ".cockpit_codex_auth.json" "config.toml" ".env")
KEYCHAIN_SERVICE="Codex Chat History Manager"
KEYCHAIN_ACCOUNT="${USER:-codex}"

NODE_EXE=""
CODEX_EXE=""

die() {
  echo "  [错误] $*" >&2
  return 1
}

pause() {
  printf "\n"
  read -r -p "  按 Enter 继续" _
}

find_runtime() {
  local override="$1"
  local file_name="$2"
  shift 2
  local roots=("$@")

  if [ -n "$override" ] && [ -x "$override" ]; then
    printf '%s\n' "$override"
    return 0
  fi

  local root
  local candidate
  for root in "${roots[@]}"; do
    if [ -d "$root" ]; then
      candidate="$(find "$root" -type f -name "$file_name" -perm -111 2>/dev/null | head -n 1)"
      if [ -n "$candidate" ]; then
        printf '%s\n' "$candidate"
        return 0
      fi
    fi
  done

  if command -v "$file_name" >/dev/null 2>&1; then
    command -v "$file_name"
    return 0
  fi

  return 1
}

init_runtimes() {
  local roots=(
    "$HOME/Library/Application Support/OpenAI/Codex"
    "$HOME/Library/Application Support/Codex"
    "/Applications/Codex.app"
    "/Applications/OpenAI Codex.app"
  )

  NODE_EXE="$(find_runtime "${CODEX_NODE:-}" "node" "${roots[@]}")" ||
    die "未找到 node。请安装 Codex Desktop，或设置 CODEX_NODE 指向可用的 node。"
  CODEX_EXE="$(find_runtime "${CODEX_CLI:-}" "codex" "${roots[@]}")" ||
    die "未找到 codex CLI。请安装 Codex Desktop，或设置 CODEX_CLI 指向 codex。"

  if [ ! -f "$CORE_SCRIPT" ]; then
    die "未找到核心脚本：$CORE_SCRIPT。请先运行 mac/install.sh。"
  fi
}

invoke_core() {
  local core_action="$1"
  local argument="${2:-}"
  if [ -n "$argument" ]; then
    "$NODE_EXE" --disable-warning=ExperimentalWarning "$CORE_SCRIPT" "$core_action" "$argument"
  else
    "$NODE_EXE" --disable-warning=ExperimentalWarning "$CORE_SCRIPT" "$core_action"
  fi
}

json_get() {
  local field="$1"
  "$NODE_EXE" -e '
const fs = require("node:fs");
const field = process.argv[1];
const data = JSON.parse(fs.readFileSync(0, "utf8"));
const value = field.split(".").reduce((item, key) => item?.[key], data);
if (value === undefined || value === null) process.exit(0);
if (typeof value === "object") process.stdout.write(JSON.stringify(value));
else process.stdout.write(String(value));
' "$field"
}

json_file_get() {
  local file_path="$1"
  local field="$2"
  "$NODE_EXE" -e '
const fs = require("node:fs");
const filePath = process.argv[1];
const field = process.argv[2];
const data = JSON.parse(fs.readFileSync(filePath, "utf8"));
const value = field.split(".").reduce((item, key) => item?.[key], data);
if (value === undefined || value === null) process.exit(0);
if (typeof value === "object") process.stdout.write(JSON.stringify(value));
else process.stdout.write(String(value));
' "$file_path" "$field"
}

sha256_file() {
  shasum -a 256 "$1" | awk '{print $1}'
}

file_size() {
  wc -c < "$1" | tr -d '[:space:]'
}

current_millis() {
  "$NODE_EXE" -e 'process.stdout.write(String(Date.now()))'
}

get_auth_mode() {
  local auth_path="$CODEX_HOME_DIR/auth.json"
  if [ ! -f "$auth_path" ]; then
    printf '%s\n' "未找到登录凭证"
    return 0
  fi

  "$NODE_EXE" -e '
const fs = require("node:fs");
try {
  const auth = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const mode = String(auth.auth_mode || "");
  if (mode === "chatgpt") console.log("ChatGPT 账号登录");
  else if (mode === "apikey" || mode === "api_key") console.log("OpenAI API Key");
  else console.log(mode || "已存在凭证");
} catch {
  console.log("凭证存在，但无法读取登录类型");
}
' "$auth_path"
}

test_codex_running() {
  pgrep -f 'Codex|codex' >/dev/null 2>&1
}

assert_codex_closed() {
  if test_codex_running; then
    die "Codex 当前仍在运行。请先完全退出 Codex，再执行恢复或配置修改。"
    return 1
  fi
}

get_keychain_secret() {
  local existing
  existing="$(security find-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$KEYCHAIN_SERVICE" -w 2>/dev/null || true)"
  if [ -n "$existing" ]; then
    printf '%s' "$existing"
    return 0
  fi

  local secret
  secret="$(openssl rand -base64 48)"
  security add-generic-password -a "$KEYCHAIN_ACCOUNT" -s "$KEYCHAIN_SERVICE" -w "$secret" -U >/dev/null ||
    die "无法写入 macOS Keychain。"
  printf '%s' "$secret"
}

openssl_supports_pbkdf2() {
  openssl enc -help 2>&1 | grep -q -- '-pbkdf2'
}

openssl_kdf_name() {
  if openssl_supports_pbkdf2; then
    printf '%s\n' "pbkdf2"
  else
    printf '%s\n' "legacy"
  fi
}

openssl_encrypt_file() {
  local input_path="$1"
  local output_path="$2"
  local passphrase="$3"
  local kdf_name="$4"
  local args=(-aes-256-cbc -salt -base64 -A)
  if [ "$kdf_name" = "pbkdf2" ]; then
    args+=(-pbkdf2 -iter 200000)
  fi
  CHM_KEYCHAIN_PASSPHRASE="$passphrase" openssl enc "${args[@]}" -in "$input_path" -out "$output_path" -pass env:CHM_KEYCHAIN_PASSPHRASE
}

openssl_decrypt_to_file() {
  local encrypted_text="$1"
  local output_path="$2"
  local passphrase="$3"
  local kdf_name="$4"
  local args=(-d -aes-256-cbc -base64 -A)
  if [ "$kdf_name" = "pbkdf2" ]; then
    args+=(-pbkdf2 -iter 200000)
  fi
  printf '%s' "$encrypted_text" |
    CHM_KEYCHAIN_PASSPHRASE="$passphrase" openssl enc "${args[@]}" -out "$output_path" -pass env:CHM_KEYCHAIN_PASSPHRASE >/dev/null 2>&1
}

protect_login_state() {
  local backup_path="$1"
  mkdir -p "$backup_path"

  local passphrase
  passphrase="$(get_keychain_secret)" || return 1
  local kdf_name
  kdf_name="$(openssl_kdf_name)"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local entries_file="$tmp_dir/entries.jsonl"
  : > "$entries_file"

  local count=0
  local name source_path encrypted_path encrypted_text bytes sha
  for name in "${CREDENTIAL_FILES[@]}"; do
    source_path="$CODEX_HOME_DIR/$name"
    if [ ! -f "$source_path" ]; then
      continue
    fi
    encrypted_path="$tmp_dir/${name//\//_}.enc"
    openssl_encrypt_file "$source_path" "$encrypted_path" "$passphrase" "$kdf_name" || {
      rm -rf "$tmp_dir"
      die "加密失败：$name"
      return 1
    }
    encrypted_text="$(cat "$encrypted_path")"
    bytes="$(file_size "$source_path")"
    sha="$(sha256_file "$source_path")"
    CHM_ENTRY_NAME="$name" \
    CHM_ENTRY_BYTES="$bytes" \
    CHM_ENTRY_SHA="$sha" \
    CHM_ENTRY_ENCRYPTED="$encrypted_text" \
      "$NODE_EXE" -e '
const entry = {
  name: process.env.CHM_ENTRY_NAME,
  bytes: Number(process.env.CHM_ENTRY_BYTES || 0),
  sha256: process.env.CHM_ENTRY_SHA,
  encrypted: process.env.CHM_ENTRY_ENCRYPTED,
};
process.stdout.write(`${JSON.stringify(entry)}\n`);
' >> "$entries_file"
    count=$((count + 1))
  done

  CHM_PACKAGE_PATH="$backup_path/$CREDENTIAL_PACKAGE_NAME" \
  CHM_ENTRIES_FILE="$entries_file" \
  CHM_KEYCHAIN_SERVICE="$KEYCHAIN_SERVICE" \
  CHM_KEYCHAIN_ACCOUNT="$KEYCHAIN_ACCOUNT" \
  CHM_OPENSSL_KDF="$kdf_name" \
  CHM_HOSTNAME="$(hostname)" \
  CHM_USER="${USER:-}" \
    "$NODE_EXE" -e '
const fs = require("node:fs");
const entriesText = fs.existsSync(process.env.CHM_ENTRIES_FILE)
  ? fs.readFileSync(process.env.CHM_ENTRIES_FILE, "utf8").trim()
  : "";
const files = entriesText ? entriesText.split(/\r?\n/).map((line) => JSON.parse(line)) : [];
const pkg = {
  version: 1,
  protection: "macOS Keychain + OpenSSL AES-256-CBC",
  credentialProtection: "macos-keychain-current-user",
  keychainService: process.env.CHM_KEYCHAIN_SERVICE,
  keychainAccount: process.env.CHM_KEYCHAIN_ACCOUNT,
  opensslKdf: process.env.CHM_OPENSSL_KDF,
  computer: process.env.CHM_HOSTNAME,
  user: process.env.CHM_USER,
  createdAt: new Date().toISOString(),
  files,
};
fs.writeFileSync(process.env.CHM_PACKAGE_PATH, JSON.stringify(pkg, null, 2), "utf8");
'

  rm -rf "$tmp_dir"
  printf '%s\n' "$count"
}

package_entries_tsv() {
  local package_path="$1"
  "$NODE_EXE" -e '
const fs = require("node:fs");
const pkg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
for (const entry of pkg.files || []) {
  console.log([entry.name, entry.bytes, entry.sha256, entry.encrypted].join("\t"));
}
' "$package_path"
}

package_kdf() {
  local package_path="$1"
  json_file_get "$package_path" "opensslKdf"
}

count_login_state_package() {
  local package_path="$1"
  if [ ! -f "$package_path" ]; then
    printf '0\n'
    return 0
  fi
  "$NODE_EXE" -e '
const fs = require("node:fs");
const pkg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
console.log((pkg.files || []).length);
' "$package_path"
}

verify_login_state_package() {
  local package_path="$1"
  if [ ! -f "$package_path" ]; then
    return 2
  fi

  local passphrase
  passphrase="$(get_keychain_secret)" || return 1
  local kdf_name
  kdf_name="$(package_kdf "$package_path")"
  [ -n "$kdf_name" ] || kdf_name="$(openssl_kdf_name)"

  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local failures=0
  local checked=0
  local name bytes sha encrypted plain_path plain_sha
  while IFS=$'\t' read -r name bytes sha encrypted; do
    [ -n "$name" ] || continue
    plain_path="$tmp_dir/plain"
    if ! openssl_decrypt_to_file "$encrypted" "$plain_path" "$passphrase" "$kdf_name"; then
      echo "  [失败] $name：无法解密" >&2
      failures=$((failures + 1))
      continue
    fi
    plain_sha="$(sha256_file "$plain_path")"
    if [ "$plain_sha" != "$sha" ]; then
      echo "  [失败] $name：解密后哈希不一致" >&2
      failures=$((failures + 1))
    fi
    checked=$((checked + 1))
  done < <(package_entries_tsv "$package_path")
  rm -rf "$tmp_dir"

  [ "$checked" -gt 0 ] || return 1
  [ "$failures" -eq 0 ]
}

restore_login_state() {
  local package_path="$1"
  if ! verify_login_state_package "$package_path"; then
    die "登录状态加密包校验失败。"
    return 1
  fi

  local passphrase
  passphrase="$(get_keychain_secret)" || return 1
  local kdf_name
  kdf_name="$(package_kdf "$package_path")"
  [ -n "$kdf_name" ] || kdf_name="$(openssl_kdf_name)"

  local name bytes sha encrypted target temporary restored_sha
  while IFS=$'\t' read -r name bytes sha encrypted; do
    [ -n "$name" ] || continue
    target="$CODEX_HOME_DIR/$name"
    temporary="$target.history-manager.tmp"
    mkdir -p "$(dirname "$target")"
    openssl_decrypt_to_file "$encrypted" "$temporary" "$passphrase" "$kdf_name" || {
      rm -f "$temporary"
      die "无法解密：$name"
      return 1
    }
    restored_sha="$(sha256_file "$temporary")"
    if [ "$restored_sha" != "$sha" ]; then
      rm -f "$temporary"
      die "恢复校验失败：$name"
      return 1
    fi
    mv -f "$temporary" "$target"
  done < <(package_entries_tsv "$package_path")
}

set_backup_permissions() {
  local backup_path="$1"
  chmod -R go-rwx "$backup_path" 2>/dev/null || true
}

get_profile_path() {
  local slot="$1"
  printf '%s\n' "$PROFILE_DIRECTORY/$slot"
}

save_login_profile() {
  local slot="$1"
  local label="$2"
  local profile_path
  profile_path="$(get_profile_path "$slot")"

  case "$slot" in
    chatgpt|custom-api) ;;
    *) die "登录档案槽位无效。"; return 1 ;;
  esac

  rm -rf "$profile_path"
  mkdir -p "$profile_path"
  local count
  count="$(protect_login_state "$profile_path")" || return 1
  if [ "$count" -eq 0 ]; then
    rm -rf "$profile_path"
    die "没有可保存的登录或配置文件。"
    return 1
  fi

  local status_json provider base_url auth_mode
  status_json="$(invoke_core status)" || return 1
  provider="$(printf '%s' "$status_json" | json_get "desktopProvider")"
  base_url="$(printf '%s' "$status_json" | json_get "openaiBaseUrl")"
  auth_mode="$(get_auth_mode)"

  CHM_PROFILE_PATH="$profile_path/profile.json" \
  CHM_SLOT="$slot" \
  CHM_LABEL="$label" \
  CHM_AUTH_MODE="$auth_mode" \
  CHM_PROVIDER="$provider" \
  CHM_BASE_URL="$base_url" \
  CHM_COUNT="$count" \
    "$NODE_EXE" -e '
const fs = require("node:fs");
const metadata = {
  version: 1,
  slot: process.env.CHM_SLOT,
  label: process.env.CHM_LABEL,
  savedAt: new Date().toISOString(),
  authMode: process.env.CHM_AUTH_MODE,
  provider: process.env.CHM_PROVIDER,
  openaiBaseUrl: process.env.CHM_BASE_URL,
  encryptedFiles: Number(process.env.CHM_COUNT || 0),
  credentialProtection: "macos-keychain-current-user",
};
fs.writeFileSync(process.env.CHM_PROFILE_PATH, JSON.stringify(metadata, null, 2), "utf8");
'
  set_backup_permissions "$profile_path"
  verify_login_state_package "$profile_path/$CREDENTIAL_PACKAGE_NAME" >/dev/null || {
    die "登录档案保存后校验失败。"
    return 1
  }
  printf '%s\n' "$profile_path/profile.json"
}

current_profile_match() {
  local profile_path="$1"
  local package_path="$profile_path/$CREDENTIAL_PACKAGE_NAME"
  [ -f "$package_path" ] || return 1

  local name bytes sha encrypted current_path current_sha count=0
  while IFS=$'\t' read -r name bytes sha encrypted; do
    [ -n "$name" ] || continue
    current_path="$CODEX_HOME_DIR/$name"
    [ -f "$current_path" ] || return 1
    current_sha="$(sha256_file "$current_path")"
    [ "$current_sha" = "$sha" ] || return 1
    count=$((count + 1))
  done < <(package_entries_tsv "$package_path")
  [ "$count" -gt 0 ]
}

active_profile_label() {
  local slot profile_path
  for slot in chatgpt custom-api; do
    profile_path="$(get_profile_path "$slot")"
    if current_profile_match "$profile_path"; then
      if [ "$slot" = "chatgpt" ]; then
        printf '%s\n' "ChatGPT 账号档案"
      else
        printf '%s\n' "自定义 API 档案"
      fi
      return 0
    fi
  done
  printf '%s\n' "当前状态尚未保存为登录档案"
}

show_login_profiles() {
  printf "\n  登录档案状态\n"
  printf "  %s\n" "----------------------------------------------------------------------------"
  local slot slot_label profile_path metadata_path package_path auth_mode base_url valid active
  for slot in chatgpt custom-api; do
    profile_path="$(get_profile_path "$slot")"
    metadata_path="$profile_path/profile.json"
    package_path="$profile_path/$CREDENTIAL_PACKAGE_NAME"
    if [ "$slot" = "chatgpt" ]; then
      slot_label="ChatGPT 账号"
    else
      slot_label="自定义 API"
    fi
    if [ ! -f "$metadata_path" ]; then
      printf "  %-16s 未保存\n" "$slot_label"
      continue
    fi
    auth_mode="$(json_file_get "$metadata_path" "authMode")"
    base_url="$(json_file_get "$metadata_path" "openaiBaseUrl")"
    if verify_login_state_package "$package_path" >/dev/null 2>&1; then
      valid="正常"
    else
      valid="损坏或无法解密"
    fi
    active=""
    if current_profile_match "$profile_path"; then
      active=" [当前使用]"
    fi
    printf "  %-16s %-18s %s%s\n" "$slot_label" "$auth_mode" "$valid" "$active"
    if [ -n "$base_url" ]; then
      printf "  %-16s %s\n" "" "$base_url"
    fi
  done
  printf "  %s\n" "----------------------------------------------------------------------------"
}

read_top_level_base_url() {
  local status_json
  status_json="$(invoke_core status)" || return 1
  printf '%s' "$status_json" | json_get "openaiBaseUrl"
}

read_current_model_name() {
  local config_path="$CODEX_HOME_DIR/config.toml"
  [ -f "$config_path" ] || return 0
  "$NODE_EXE" -e '
const fs = require("node:fs");
const configPath = process.argv[1];
const lines = fs.readFileSync(configPath, "utf8").split(/\r?\n/);
let section = "";
for (const line of lines) {
  const sectionMatch = line.match(/^\s*\[([^\]]+)\]\s*$/);
  if (sectionMatch) {
    section = sectionMatch[1];
    continue;
  }
  if (!section) {
    const match = line.match(/^\s*model\s*=\s*"(.+?)"\s*$/);
    if (match) {
      process.stdout.write(match[1].trim());
      process.exit(0);
    }
  }
}
' "$config_path"
}

save_custom_api_profile_if_active() {
  if [[ "$(get_auth_mode)" == OpenAI\ API\ Key* ]]; then
    save_login_profile "custom-api" "自定义 API" >/dev/null || return 1
    echo "  [完成] 已同步更新自定义 API 加密档案。"
  fi
}

env_no_proxy_contains() {
  local host_name="$1"
  local env_path="$CODEX_HOME_DIR/.env"
  [ -f "$env_path" ] || return 1
  "$NODE_EXE" -e '
const fs = require("node:fs");
const host = process.argv[1];
const envPath = process.argv[2];
const text = fs.existsSync(envPath) ? fs.readFileSync(envPath, "utf8") : "";
for (const line of text.split(/\r?\n/)) {
  const match = line.match(/^\s*(NO_PROXY|no_proxy)\s*=\s*(.*?)\s*$/);
  if (!match) continue;
  const value = match[2].replace(/^["\x27]|["\x27]$/g, "");
  if (value.split(",").map((item) => item.trim()).includes(host)) process.exit(0);
}
process.exit(1);
' "$host_name" "$env_path"
}

update_no_proxy_host() {
  local mode="$1"
  local host_name="$2"
  mkdir -p "$CODEX_HOME_DIR"
  CHM_ENV_PATH="$CODEX_HOME_DIR/.env" CHM_MODE="$mode" CHM_HOST="$host_name" "$NODE_EXE" -e '
const fs = require("node:fs");
const envPath = process.env.CHM_ENV_PATH;
const mode = process.env.CHM_MODE;
const host = process.env.CHM_HOST;
const text = fs.existsSync(envPath) ? fs.readFileSync(envPath, "utf8") : "";
const lines = text ? text.split(/\r?\n/) : [];
let found = false;
function normalize(value) {
  const items = value
    .replace(/^["\x27]|["\x27]$/g, "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
  const set = new Set(items);
  if (mode === "add") {
    for (const item of ["localhost", "127.0.0.1", "::1", host]) set.add(item);
  } else {
    set.delete(host);
  }
  return [...set].join(",");
}
const output = lines.map((line) => {
  const match = line.match(/^\s*(NO_PROXY|no_proxy)\s*=\s*(.*?)\s*$/);
  if (!match) return line;
  found = true;
  return `${match[1]}="${normalize(match[2])}"`;
});
if (!found && mode === "add") {
  output.push(`NO_PROXY="${normalize("")}"`);
  output.push(`no_proxy="${normalize("")}"`);
}
fs.writeFileSync(envPath, `${output.filter((line, index) => line || index < output.length - 1).join("\n")}\n`, "utf8");
'
}

test_api_latency() {
  local base_url="$1"
  local api_key="$2"
  local mode="$3"
  local uri="${base_url%/}/models"
  local start end elapsed status
  start="$(current_millis)"
  if [ "$mode" = "proxy" ]; then
    status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 --proxy http://127.0.0.1:10808 -H "Authorization: Bearer $api_key" "$uri" 2>/dev/null || true)"
  else
    status="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 --noproxy '*' -H "Authorization: Bearer $api_key" "$uri" 2>/dev/null || true)"
  fi
  end="$(current_millis)"
  elapsed=$((end - start))
  if [[ "$status" =~ ^[23] ]]; then
    printf '%s\t1\t%s\t%s\n' "$mode" "$status" "$elapsed"
  else
    printf '%s\t0\t%s\t%s\n' "$mode" "${status:-000}" "$elapsed"
  fi
}

test_responses_endpoint() {
  local base_url="$1"
  local api_key="$2"
  local model="$3"
  local mode="$4"
  local uri="${base_url%/}/responses"
  local payload tmp_body status start end elapsed
  payload="$("$NODE_EXE" -e 'process.stdout.write(JSON.stringify({model: process.argv[1], input: "ping", max_output_tokens: 1, stream: false}))' "$model")"
  tmp_body="$(mktemp)"
  start="$(current_millis)"
  if [ "$mode" = "proxy" ]; then
    status="$(curl -sS -o "$tmp_body" -w '%{http_code}' --max-time 30 --proxy http://127.0.0.1:10808 -H "Authorization: Bearer $api_key" -H "Content-Type: application/json" -d "$payload" "$uri" 2>/dev/null || true)"
  else
    status="$(curl -sS -o "$tmp_body" -w '%{http_code}' --max-time 30 --noproxy '*' -H "Authorization: Bearer $api_key" -H "Content-Type: application/json" -d "$payload" "$uri" 2>/dev/null || true)"
  fi
  end="$(current_millis)"
  elapsed=$((end - start))
  local ok body
  if [[ "$status" =~ ^[23] ]]; then
    ok=1
  else
    ok=0
  fi
  body="$(head -c 300 "$tmp_body" | tr '\n' ' ')"
  rm -f "$tmp_body"
  printf '%s\t%s\t%s\t%s\t%s\n' "$mode" "$ok" "${status:-000}" "$elapsed" "$body"
}

show_custom_api_compatibility() {
  local base_url
  base_url="$(read_top_level_base_url)" || return 1
  if [ -z "$base_url" ]; then
    echo "  [提示] 当前没有配置自定义 API 地址。"
    return 0
  fi

  local auth_path="$CODEX_HOME_DIR/auth.json"
  if [ ! -f "$auth_path" ]; then
    echo "  [提示] 未找到 auth.json，无法检查 API 兼容性。"
    return 0
  fi
  local api_key auth_mode
  auth_mode="$(json_file_get "$auth_path" "auth_mode")"
  if [ "$auth_mode" != "apikey" ] && [ "$auth_mode" != "api_key" ]; then
    echo "  [提示] 当前不是 API Key 登录，跳过 API 兼容性检查。"
    return 0
  fi
  api_key="$(json_file_get "$auth_path" "OPENAI_API_KEY")"
  if [ -z "$api_key" ]; then
    echo "  [提示] auth.json 中没有 API Key，无法检查 API 兼容性。"
    return 0
  fi

  local model
  model="$(read_current_model_name || true)"
  if [ -z "$model" ]; then
    read -r -p "  未在 config.toml 中找到 model，请输入要测试的模型名（例如 gpt-5.5） " model
  fi
  if [ -z "$model" ]; then
    die "没有模型名，已取消兼容性检查。"
    return 1
  fi

  printf "\n  自定义 API /v1/responses 兼容性检查\n"
  printf "  地址：%s\n" "$base_url"
  printf "  模型：%s\n" "$model"
  local direct proxy
  direct="$(test_responses_endpoint "$base_url" "$api_key" "$model" "direct")"
  proxy="$(test_responses_endpoint "$base_url" "$api_key" "$model" "proxy")"
  printf "  %-8s %-6s %-8s %-8s\n" "Mode" "Ok" "Status" "Ms"
  printf "  %-8s %-6s %-8s %-8s\n" $(printf '%s' "$direct" | awk -F '\t' '{print $1, $2, $3, $4}')
  printf "  %-8s %-6s %-8s %-8s\n" $(printf '%s' "$proxy" | awk -F '\t' '{print $1, $2, $3, $4}')

  local row mode ok status ms body
  for row in "$direct" "$proxy"; do
    mode="$(printf '%s' "$row" | awk -F '\t' '{print $1}')"
    ok="$(printf '%s' "$row" | awk -F '\t' '{print $2}')"
    status="$(printf '%s' "$row" | awk -F '\t' '{print $3}')"
    body="$(printf '%s' "$row" | cut -f5-)"
    if [ "$ok" = "1" ]; then
      echo "  [正常] $mode 路径可以调用 /v1/responses。"
    elif [ "$status" = "503" ]; then
      echo "  [服务不可用] $mode 路径返回 503：服务商上游暂不可用或该模型暂不可用。"
    elif [ "$status" = "404" ] || [ "$status" = "405" ]; then
      echo "  [不兼容] $mode 路径返回 $status：该服务可能不支持 Codex Desktop 需要的 /v1/responses。"
    elif [ "$status" = "401" ] || [ "$status" = "403" ]; then
      echo "  [认证失败] $mode 路径返回 $status：请检查 API Key 或服务商权限。"
    elif [ "$status" = "400" ]; then
      echo "  [请求被拒绝] $mode 路径返回 400：请检查模型名是否正确，或服务商是否兼容 Responses API 请求格式。"
    else
      echo "  [失败] $mode 路径调用失败，状态码：$status。"
    fi
    if [ -n "$body" ]; then
      echo "    响应：$body"
    fi
  done
}

optimize_custom_api_network() {
  local base_url
  base_url="$(read_top_level_base_url)" || return 1
  if [ -z "$base_url" ]; then
    echo "  [提示] 当前没有配置自定义 API 地址。"
    return 0
  fi

  local auth_path="$CODEX_HOME_DIR/auth.json"
  if [ ! -f "$auth_path" ]; then
    echo "  [提示] 未找到 auth.json，无法测速 API。"
    return 0
  fi
  local api_key auth_mode
  auth_mode="$(json_file_get "$auth_path" "auth_mode")"
  if [ "$auth_mode" != "apikey" ] && [ "$auth_mode" != "api_key" ]; then
    echo "  [提示] 当前不是 API Key 登录，跳过 API 网络优化。"
    return 0
  fi
  api_key="$(json_file_get "$auth_path" "OPENAI_API_KEY")"
  if [ -z "$api_key" ]; then
    echo "  [提示] auth.json 中没有 API Key，无法测速。"
    return 0
  fi

  local host_name
  host_name="$("$NODE_EXE" -e 'console.log(new URL(process.argv[1]).hostname)' "$base_url")"
  printf "\n  API 网络测速\n"
  printf "  地址：%s\n" "$base_url"
  local direct proxy
  direct="$(test_api_latency "$base_url" "$api_key" "direct")"
  proxy="$(test_api_latency "$base_url" "$api_key" "proxy")"
  printf "  %-8s %-6s %-8s %-8s\n" "Mode" "Ok" "Status" "Ms"
  printf "  %-8s %-6s %-8s %-8s\n" $(printf '%s' "$direct" | tr '\t' ' ')
  printf "  %-8s %-6s %-8s %-8s\n" $(printf '%s' "$proxy" | tr '\t' ' ')

  local direct_ok direct_ms proxy_ok proxy_ms
  direct_ok="$(printf '%s' "$direct" | awk -F '\t' '{print $2}')"
  direct_ms="$(printf '%s' "$direct" | awk -F '\t' '{print $4}')"
  proxy_ok="$(printf '%s' "$proxy" | awk -F '\t' '{print $2}')"
  proxy_ms="$(printf '%s' "$proxy" | awk -F '\t' '{print $4}')"
  if [ "$direct_ok" = "1" ] && { [ "$proxy_ok" != "1" ] || [ "$direct_ms" -lt "$proxy_ms" ]; }; then
    update_no_proxy_host add "$host_name"
    echo "  [完成] 已将 $host_name 加入 .env 的 NO_PROXY，API 请求会优先直连。"
    save_custom_api_profile_if_active || true
    echo "  请完全退出并重新打开 Codex，让 .env 生效。"
  elif [ "$proxy_ok" = "1" ]; then
    echo "  [结果] 代理路径可用，保持当前代理配置。"
  else
    echo "  [警告] 直连和代理测速都失败，请检查自定义 API 服务或 Key。"
  fi
}

show_api_network_menu() {
  while true; do
    local base_url host_name mode choice
    base_url="$(read_top_level_base_url || true)"
    host_name=""
    if [ -n "$base_url" ]; then
      host_name="$("$NODE_EXE" -e 'console.log(new URL(process.argv[1]).hostname)' "$base_url")"
    fi
    mode="默认走代理"
    if [ -n "$host_name" ] && env_no_proxy_contains "$host_name"; then
      mode="强制直连该 API 域名"
    fi
    clear
    printf "%s\n" "=========================================================================="
    printf "                         自定义 API 网络模式\n"
    printf "%s\n\n" "=========================================================================="
    printf "  API 地址     : %s\n" "${base_url:-未配置}"
    printf "  API 域名     : %s\n" "${host_name:-无}"
    printf "  当前模式     : %s\n\n" "$mode"
    printf "    [1] 自动测速并按结果优化\n"
    printf "    [2] 强制直连自定义 API 域名（加入 NO_PROXY）\n"
    printf "    [3] 强制走本机代理（从 NO_PROXY 移除该域名）\n"
    printf "    [4] 查看当前 .env 代理配置\n"
    printf "    [5] 检查 /v1/responses 兼容性\n"
    printf "    [B] 返回\n\n"
    read -r -p "  请选择 " choice
    choice="$(printf '%s' "$choice" | tr '[:lower:]' '[:upper:]')"
    case "$choice" in
      1) optimize_custom_api_network ;;
      2)
        [ -n "$host_name" ] || { echo "  [错误] 当前没有配置自定义 API 地址。"; pause; continue; }
        update_no_proxy_host add "$host_name"
        save_custom_api_profile_if_active || true
        echo "  [完成] 已强制直连：$host_name"
        echo "  请完全退出并重新打开 Codex，让 .env 生效。"
        ;;
      3)
        [ -n "$host_name" ] || { echo "  [错误] 当前没有配置自定义 API 地址。"; pause; continue; }
        update_no_proxy_host remove "$host_name"
        save_custom_api_profile_if_active || true
        echo "  [完成] 已强制该域名走代理：$host_name"
        echo "  请完全退出并重新打开 Codex，让 .env 生效。"
        ;;
      4)
        printf "\n"
        if [ -f "$CODEX_HOME_DIR/.env" ]; then
          grep -E '^(http_proxy|https_proxy|HTTP_PROXY|HTTPS_PROXY|ALL_PROXY|NO_PROXY|no_proxy)=' "$CODEX_HOME_DIR/.env" || true
        else
          echo "  未找到 .env。"
        fi
        ;;
      5) show_custom_api_compatibility ;;
      B) return 0 ;;
      *) echo "  [提示] 输入无效。" ;;
    esac
    pause
  done
}

get_api_key_from_text_file() {
  local text_file="$1"
  local source_label="$2"
  "$NODE_EXE" -e '
const fs = require("node:fs");
let content = fs.readFileSync(process.argv[1], "utf8").trim().replace(/^\uFEFF/, "");
const label = process.argv[2];
if (!content) throw new Error(`${label} 中没有 API Key。`);
if (content.startsWith("{")) {
  const json = JSON.parse(content);
  for (const name of ["apiKey", "api_key", "OPENAI_API_KEY", "key"]) {
    if (json[name] && String(json[name]).trim()) {
      content = String(json[name]).trim();
      break;
    }
  }
} else {
  const line = content.split(/\r?\n/).find((item) => /^\s*(OPENAI_API_KEY|API_KEY)\s*=/.test(item));
  if (line) {
    content = line.replace(/^\s*(OPENAI_API_KEY|API_KEY)\s*=\s*/, "").trim().replace(/^["\x27]|["\x27]$/g, "");
  } else {
    const lines = content.split(/\r?\n/).filter((item) => item.trim());
    if (lines.length !== 1) throw new Error(`${label} 包含多行内容，且未找到 OPENAI_API_KEY=...。`);
    content = lines[0].trim();
  }
}
if (!content) throw new Error(`${label} 中的 API Key 为空。`);
if (/\s/.test(content)) throw new Error("API Key 中包含空格或换行，请检查来源内容。");
process.stdout.write(content);
' "$text_file" "$source_label"
}

read_api_key() {
  printf "\n  选择 API Key 输入方式\n" >&2
  printf "    [1] 从 macOS 剪贴板读取（推荐）\n" >&2
  printf "    [2] 从 TXT / KEY / ENV / JSON 文件读取\n" >&2
  printf "    [3] 隐藏手动输入\n" >&2
  printf "    [B] 取消\n" >&2
  local choice plain_key tmp_file file_path suffix_len suffix confirm
  read -r -p "  请选择 " choice
  choice="$(printf '%s' "$choice" | tr '[:lower:]' '[:upper:]')"

  case "$choice" in
    1)
      command -v pbpaste >/dev/null 2>&1 || { die "当前系统没有 pbpaste。"; return 1; }
      tmp_file="$(mktemp)"
      pbpaste > "$tmp_file"
      plain_key="$(get_api_key_from_text_file "$tmp_file" "剪贴板")" || { rm -f "$tmp_file"; return 1; }
      rm -f "$tmp_file"
      ;;
    2)
      read -r -p "  请输入文件路径 " file_path
      file_path="${file_path/#\~/$HOME}"
      [ -f "$file_path" ] || { die "文件不存在：$file_path"; return 1; }
      plain_key="$(get_api_key_from_text_file "$file_path" "所选文件")" || return 1
      echo "  已读取文件：$file_path" >&2
      echo "  注意：原文件仍是明文，请自行妥善保管或删除。" >&2
      ;;
    3)
      read -r -s -p "  请输入 API Key " plain_key
      printf "\n"
      tmp_file="$(mktemp)"
      printf '%s' "$plain_key" > "$tmp_file"
      plain_key="$(get_api_key_from_text_file "$tmp_file" "手动输入")" || { rm -f "$tmp_file"; return 1; }
      rm -f "$tmp_file"
      ;;
    B) return 2 ;;
    *) die "输入无效，请选择 1、2、3 或 B。"; return 1 ;;
  esac

  suffix_len=4
  if [ "${#plain_key}" -lt 4 ]; then
    suffix_len="${#plain_key}"
  fi
  suffix="${plain_key:$((${#plain_key} - suffix_len)):suffix_len}"
  echo "  [已读取] 长度 ${#plain_key}，末尾 $suffix_len 位：$suffix" >&2
  read -r -p "  确认使用这个 Key？[Y/N] " confirm
  confirm="$(printf '%s' "$confirm" | tr '[:lower:]' '[:upper:]')"
  if [ "$confirm" != "Y" ]; then
    return 2
  fi
  printf '%s' "$plain_key"
}

set_custom_api_address() {
  assert_codex_closed || return 1
  local current url result
  current="$(read_top_level_base_url || true)"
  printf "\n  配置自定义 OpenAI API 地址\n"
  printf "  当前地址：%s\n" "${current:-OpenAI 默认地址}"
  printf "  示例：https://example.com/v1\n"
  printf "  直接按 Enter 可清除自定义地址并恢复默认。\n"
  read -r -p "  新地址 " url
  url="$(printf '%s' "$url" | xargs)"
  if [ -n "$url" ] && [[ ! "$url" =~ ^https?:// ]]; then
    die "地址必须以 http:// 或 https:// 开头。"
    return 1
  fi
  if [ -n "$url" ] && [[ ! "$url" =~ /v1/?$ ]]; then
    echo "  [提示] 地址未以 /v1 结尾，请确认你的服务商要求。"
  fi
  result="$(invoke_core set-base-url "$url")" || return 1
  echo "  [完成] 自定义 API 地址：$(printf '%s' "$result" | json_get "baseUrl")"
  echo "  Provider 已保持为 openai，历史记录不会因登录方式切换而分组消失。"
  echo "  配置备份：$(printf '%s' "$result" | json_get "backupPath")"
}

login_with_api_key() {
  assert_codex_closed || return 1
  printf "\n  OpenAI API Key 登录\n"
  echo "  API Key 不会显示，也不会写入命令行参数或日志。"
  echo "  登录前先创建当前状态的完整安全备份。"
  new_backup true || return 1

  local plain_key
  plain_key="$(read_api_key)" || { echo "  [取消] 已取消 API Key 登录。"; return 1; }
  printf '%s\n' "$plain_key" | "$CODEX_EXE" login --with-api-key || {
    plain_key=""
    die "API Key 登录失败。"
    return 1
  }
  plain_key=""
  echo "  [完成] API Key 登录成功。"
  optimize_custom_api_network || true
  new_backup true
}

first_login_with_api_key() {
  assert_codex_closed || return 1
  printf "\n  新用户首次 API Key 登录\n"
  echo "  适用于当前 Codex Home 还没有登录状态的新用户。"
  echo "  这一步不会先创建登录前备份；登录成功后会自动创建完整备份。"

  if [[ "$(get_auth_mode)" != "未找到登录凭证" ]]; then
    echo "  [提示] 当前已经存在登录凭证。若要保留现有状态，请优先使用菜单 [8]。"
    local confirm
    read -r -p "  仍然继续首次登录流程？[Y/N] " confirm
    confirm="$(printf '%s' "$confirm" | tr '[:lower:]' '[:upper:]')"
    if [ "$confirm" != "Y" ]; then
      die "已取消首次登录。"
      return 1
    fi
  fi

  local plain_key
  plain_key="$(read_api_key)" || { echo "  [取消] 已取消 API Key 登录。"; return 1; }
  printf '%s\n' "$plain_key" | "$CODEX_EXE" login --with-api-key || {
    plain_key=""
    die "API Key 登录失败。"
    return 1
  }
  plain_key=""
  echo "  [完成] API Key 登录成功。"
  echo "  如需调整自定义 API 的直连/代理模式，可稍后使用主菜单 [N]。"
  new_backup true
}

configure_custom_api_profile() {
  assert_codex_closed || return 1

  local chat_profile
  chat_profile="$(get_profile_path chatgpt)"
  if [ ! -f "$chat_profile/profile.json" ] && [[ "$(get_auth_mode)" == ChatGPT* ]]; then
    echo "  正在先保存当前 ChatGPT 登录档案..."
    save_login_profile "chatgpt" "当前 ChatGPT 账号" >/dev/null || return 1
  fi

  set_custom_api_address || return 1
  printf "\n  读取自定义 API 对应的 Key。\n"
  local plain_key
  plain_key="$(read_api_key)" || { die "已取消配置自定义 API 档案。"; return 1; }
  printf '%s\n' "$plain_key" | "$CODEX_EXE" login --with-api-key || {
    plain_key=""
    die "API Key 登录失败。"
    return 1
  }
  plain_key=""

  local metadata_path base_url
  metadata_path="$(save_login_profile "custom-api" "自定义 API")" || return 1
  base_url="$(json_file_get "$metadata_path" "openaiBaseUrl")"
  echo "  [完成] 自定义 API 登录档案已保存，以后可一键切换。"
  echo "  API 地址：$base_url"
  optimize_custom_api_network || true
}

save_current_chatgpt_profile() {
  local auth_mode
  auth_mode="$(get_auth_mode)"
  if [[ "$auth_mode" != ChatGPT* ]]; then
    die "当前不是 ChatGPT 账号登录，不能覆盖 ChatGPT 登录档案。"
    return 1
  fi
  local metadata_path saved_at
  metadata_path="$(save_login_profile "chatgpt" "当前 ChatGPT 账号")" || return 1
  saved_at="$(json_file_get "$metadata_path" "savedAt")"
  echo "  [完成] 当前 ChatGPT 登录已加密保存。"
  echo "  保存时间：$saved_at"
}

open_credential_import_directory() {
  mkdir -p "$CREDENTIAL_IMPORT_DIRECTORY"
  local readme_path="$CREDENTIAL_IMPORT_DIRECTORY/README.txt"
  if [ ! -f "$readme_path" ]; then
    cat > "$readme_path" <<'EOF'
Place both files from the same ChatGPT account here:

1. auth.json
2. .cockpit_codex_auth.json

Then fully quit Codex Desktop and choose:
[P] -> [7] Import ChatGPT credentials from this folder

Do not place account passwords here. This folder only accepts credential files
from an already logged-in Codex environment.
EOF
  fi
  open "$CREDENTIAL_IMPORT_DIRECTORY"
  echo "  [完成] 已打开：$CREDENTIAL_IMPORT_DIRECTORY"
}

validate_imported_chatgpt_credentials() {
  local auth_path="$CREDENTIAL_IMPORT_DIRECTORY/auth.json"
  local cockpit_path="$CREDENTIAL_IMPORT_DIRECTORY/.cockpit_codex_auth.json"
  [ -f "$auth_path" ] || { die "导入文件夹缺少：auth.json。"; return 1; }
  [ -f "$cockpit_path" ] || { die "导入文件夹缺少：.cockpit_codex_auth.json。"; return 1; }

  "$NODE_EXE" -e '
const fs = require("node:fs");
const authPath = process.argv[1];
const cockpitPath = process.argv[2];
let auth;
try {
  auth = JSON.parse(fs.readFileSync(authPath, "utf8"));
} catch (error) {
  throw new Error(`auth.json 不是有效 JSON：${error.message}`);
}
if (auth.auth_mode !== "chatgpt") throw new Error("auth.json 不是 ChatGPT 账号凭证，auth_mode 必须是 chatgpt。");
for (const name of ["access_token", "refresh_token", "account_id"]) {
  if (!auth.tokens?.[name]) throw new Error(`auth.json 缺少必要字段 tokens.${name}。`);
}
try {
  JSON.parse(fs.readFileSync(cockpitPath, "utf8"));
} catch (error) {
  throw new Error(`.cockpit_codex_auth.json 不是有效 JSON：${error.message}`);
}
process.stdout.write(String(auth.tokens.account_id || ""));
' "$auth_path" "$cockpit_path"
}

import_chatgpt_credentials() {
  assert_codex_closed || return 1
  mkdir -p "$CREDENTIAL_IMPORT_DIRECTORY"
  local account_hint
  account_hint="$(validate_imported_chatgpt_credentials)" || return 1
  if [ "${#account_hint}" -gt 8 ]; then
    account_hint="${account_hint:0:4}...${account_hint:$((${#account_hint} - 4)):4}"
  fi
  printf "\n  已找到一组结构有效的 ChatGPT 凭证。\n"
  echo "  账号标识：$account_hint"
  echo "  工具无法仅靠文件结构确认令牌是否仍被服务器接受。"
  local confirm
  read -r -p "  确认备份当前状态并导入？[Y/N] " confirm
  confirm="$(printf '%s' "$confirm" | tr '[:lower:]' '[:upper:]')"
  [ "$confirm" = "Y" ] || { die "已取消导入。"; return 1; }

  new_backup true || return 1
  cp "$CREDENTIAL_IMPORT_DIRECTORY/auth.json" "$CODEX_HOME_DIR/auth.json.history-manager.import"
  mv -f "$CODEX_HOME_DIR/auth.json.history-manager.import" "$CODEX_HOME_DIR/auth.json"
  cp "$CREDENTIAL_IMPORT_DIRECTORY/.cockpit_codex_auth.json" "$CODEX_HOME_DIR/.cockpit_codex_auth.json.history-manager.import"
  mv -f "$CODEX_HOME_DIR/.cockpit_codex_auth.json.history-manager.import" "$CODEX_HOME_DIR/.cockpit_codex_auth.json"

  invoke_core set-base-url "" >/dev/null || return 1
  if [[ "$(get_auth_mode)" != ChatGPT* ]]; then
    die "凭证文件已复制，但登录类型校验失败。请使用刚才创建的完整备份恢复。"
    return 1
  fi

  local metadata_path saved_at
  metadata_path="$(save_login_profile "chatgpt" "导入的 ChatGPT 账号")" || return 1
  saved_at="$(json_file_get "$metadata_path" "savedAt")"
  echo "  [完成] ChatGPT 凭证已导入，并已保存为 Keychain 加密档案。"
  echo "  档案保存时间：$saved_at"
  "$CODEX_EXE" login status || echo "  [警告] 本地文件已导入，但 Codex 登录状态检查未通过；令牌可能已过期或被撤销。"

  read -r -p "  是否删除导入文件夹中的两个明文凭证文件？[Y/N] " confirm
  confirm="$(printf '%s' "$confirm" | tr '[:lower:]' '[:upper:]')"
  if [ "$confirm" = "Y" ]; then
    rm -f "$CREDENTIAL_IMPORT_DIRECTORY/auth.json" "$CREDENTIAL_IMPORT_DIRECTORY/.cockpit_codex_auth.json"
    echo "  [完成] 已删除导入文件夹中的明文凭证文件。"
  else
    echo "  [提醒] 明文凭证仍保留在：$CREDENTIAL_IMPORT_DIRECTORY"
  fi
}

switch_login_profile() {
  local slot="$1"
  assert_codex_closed || return 1
  local profile_path package_path label
  profile_path="$(get_profile_path "$slot")"
  package_path="$profile_path/$CREDENTIAL_PACKAGE_NAME"
  [ -f "$package_path" ] || { die "该登录档案尚未保存。"; return 1; }
  verify_login_state_package "$package_path" >/dev/null || { die "登录档案校验失败。"; return 1; }

  new_backup true || return 1
  restore_login_state "$package_path" || return 1
  if [ "$slot" = "chatgpt" ]; then
    label="ChatGPT 账号"
  else
    label="自定义 API"
  fi
  echo "  [完成] 已切换到：$label"
  if [ "$slot" = "custom-api" ]; then
    optimize_custom_api_network || true
  fi
  echo "  请重新打开 Codex；聊天记录不会被替换或删除。"
  "$CODEX_EXE" login status || true
}

show_profile_menu() {
  while true; do
    clear
    printf "%s\n" "=========================================================================="
    printf "                       登录档案快速切换\n"
    printf "%s\n\n" "=========================================================================="
    printf "    [1] 保存或更新当前 ChatGPT 登录档案\n"
    printf "    [2] 首次配置或更新自定义 API 档案\n"
    printf "    [3] 一键切换到 ChatGPT 账号\n"
    printf "    [4] 一键切换到自定义 API\n"
    printf "    [5] 查看两个登录档案状态\n"
    printf "    [6] 打开 ChatGPT 凭证导入文件夹\n"
    printf "    [7] 从导入文件夹登录 ChatGPT 账号\n\n"
    printf "    [B] 返回主菜单\n\n"
    local choice
    read -r -p "  请选择功能 " choice
    choice="$(printf '%s' "$choice" | tr '[:lower:]' '[:upper:]')"
    case "$choice" in
      1) save_current_chatgpt_profile ;;
      2) configure_custom_api_profile ;;
      3) switch_login_profile chatgpt ;;
      4) switch_login_profile custom-api ;;
      5) show_login_profiles ;;
      6) open_credential_import_directory ;;
      7) import_chatgpt_credentials ;;
      B) return 0 ;;
      *) echo "  [提示] 输入无效。" ;;
    esac
    pause
  done
}

show_status() {
  local status_json backups_json auth_mode active_label
  status_json="$(invoke_core status)" || return 1
  backups_json="$(invoke_core list)" || return 1
  auth_mode="$(get_auth_mode)"
  active_label="$(active_profile_label)"

  CHM_STATUS_JSON="$status_json" \
  CHM_BACKUPS_JSON="$backups_json" \
  CHM_AUTH_MODE="$auth_mode" \
  CHM_ACTIVE_LABEL="$active_label" \
  CHM_CODEX_RUNNING="$(test_codex_running && echo running || echo stopped)" \
    "$NODE_EXE" -e '
const status = JSON.parse(process.env.CHM_STATUS_JSON);
const backups = JSON.parse(process.env.CHM_BACKUPS_JSON);
console.log("");
console.log("  本地状态总览");
console.log("  ----------------------------------------------------------------------");
console.log(`  登录方式          ${process.env.CHM_AUTH_MODE}`);
console.log(`  当前登录档案      ${process.env.CHM_ACTIVE_LABEL}`);
console.log(`  桌面 Provider     ${status.desktopProvider || ""}`);
console.log(`  自定义 API 地址   ${status.openaiBaseUrl || "未配置（使用 OpenAI 默认地址）"}`);
console.log(`  会话文件          ${status.totalSessionFiles} 个（有效 ${status.validSessionFiles}，异常 ${status.invalidSessionFiles}）`);
console.log(`  会话索引          ${status.indexLines} 条`);
console.log(`  可用备份          ${backups.length} 份`);
console.log(`  Codex 运行状态    ${process.env.CHM_CODEX_RUNNING === "running" ? "运行中" : "已退出"}`);
console.log("");
console.log("  会话 Provider 分布");
for (const [provider, count] of Object.entries(status.providers || {})) {
  console.log(`    ${provider.padEnd(24)} ${String(count).padStart(6)}`);
}
if (status.desktopProvider && !Object.prototype.hasOwnProperty.call(status.providers || {}, status.desktopProvider)) {
  console.log("");
  console.log("  [警告] 桌面 Provider 与历史会话不一致，历史列表可能被过滤。");
}
console.log("  ----------------------------------------------------------------------");
'
}

new_backup() {
  local include_login_state="$1"
  local kind result backup_path backup_name verification failures count package_path checked
  if [ "$include_login_state" = "true" ]; then
    kind="完整备份"
    result="$(invoke_core backup full)" || return 1
  else
    kind="聊天记录备份"
    result="$(invoke_core backup history)" || return 1
  fi
  printf "\n  正在创建%s...\n" "$kind"
  backup_path="$(printf '%s' "$result" | json_get "destination")"

  count=0
  if [ "$include_login_state" = "true" ]; then
    count="$(protect_login_state "$backup_path")" || return 1
    backup_name="$(basename "$backup_path")"
    invoke_core refresh-manifest "$backup_name" >/dev/null || return 1
  fi

  set_backup_permissions "$backup_path"
  verification="$(invoke_core verify "$(basename "$backup_path")")" || return 1
  failures="$(printf '%s' "$verification" | json_get "failures")"
  if [ "$failures" != "[]" ]; then
    die "备份完成，但自动校验未通过。"
    return 1
  fi

  package_path="$backup_path/$CREDENTIAL_PACKAGE_NAME"
  if [ "$include_login_state" = "true" ]; then
    verify_login_state_package "$package_path" >/dev/null || {
      die "备份完成，但登录状态解密测试未通过。"
      return 1
    }
  fi

  checked="$(printf '%s' "$verification" | json_get "checked")"
  echo "  [完成] 文件校验通过：$checked 个"
  if [ "$include_login_state" = "true" ]; then
    echo "  [完成] 已加密登录与配置文件：$count 个"
    echo "  加密方式：macOS Keychain + OpenSSL，仅当前用户可解密。"
  fi
  echo "  保存位置：$backup_path"
}

select_backup() {
  local backups_json count selection
  backups_json="$(invoke_core list)" || return 1
  count="$(printf '%s' "$backups_json" | "$NODE_EXE" -e 'const fs=require("node:fs"); console.log(JSON.parse(fs.readFileSync(0,"utf8")).length)')"
  if [ "$count" -eq 0 ]; then
    die "目前没有可用备份。"
    return 1
  fi

  printf "\n  可用备份\n"
  printf "  %s\n" "--------------------------------------------------------------------------------------"
  printf '%s' "$backups_json" | "$NODE_EXE" -e '
const fs = require("node:fs");
const backups = JSON.parse(fs.readFileSync(0, "utf8"));
backups.forEach((backup, index) => {
  let label = "仅聊天记录";
  if (backup.credentialProtection === "windows-dpapi-current-user") label = "聊天 + Windows 加密登录";
  if (backup.credentialProtection === "macos-keychain-current-user") label = "聊天 + macOS 加密登录";
  console.log(`  [${String(index + 1).padStart(2)}] ${backup.name.padEnd(42)} ${label.padEnd(24)} ${String(backup.files).padStart(4)} 文件`);
});
'
  read -r -p "  请输入备份编号 " selection
  if ! [[ "$selection" =~ ^[0-9]+$ ]] || [ "$selection" -lt 1 ] || [ "$selection" -gt "$count" ]; then
    die "备份编号无效。"
    return 1
  fi

  SELECTED_BACKUP_JSON="$(printf '%s' "$backups_json" | "$NODE_EXE" -e '
const fs = require("node:fs");
const backups = JSON.parse(fs.readFileSync(0, "utf8"));
const index = Number(process.argv[1]) - 1;
process.stdout.write(JSON.stringify(backups[index]));
' "$selection")"
}

verify_backup_by_json() {
  local backup_json="$1"
  local name path result failures package_path protection
  name="$(printf '%s' "$backup_json" | json_get "name")"
  path="$(printf '%s' "$backup_json" | json_get "path")"
  protection="$(printf '%s' "$backup_json" | json_get "credentialProtection")"
  result="$(invoke_core verify "$name")" || return 1
  failures="$(printf '%s' "$result" | json_get "failures")"
  if [ "$failures" != "[]" ]; then
    printf '%s\n' "$failures"
    die "备份校验失败。"
    return 1
  fi
  if [ "$protection" = "macos-keychain-current-user" ]; then
    package_path="$path/$CREDENTIAL_PACKAGE_NAME"
    verify_login_state_package "$package_path" >/dev/null || {
      die "登录状态解密测试失败。"
      return 1
    }
  fi
}

verify_backup() {
  select_backup || return 1
  verify_backup_by_json "$SELECTED_BACKUP_JSON" || return 1
  local name checked result path package_path protection count
  name="$(printf '%s' "$SELECTED_BACKUP_JSON" | json_get "name")"
  path="$(printf '%s' "$SELECTED_BACKUP_JSON" | json_get "path")"
  protection="$(printf '%s' "$SELECTED_BACKUP_JSON" | json_get "credentialProtection")"
  result="$(invoke_core verify "$name")"
  checked="$(printf '%s' "$result" | json_get "checked")"
  echo "  [正常] 文件完整性校验通过：$checked 个文件。"
  if [ "$protection" = "macos-keychain-current-user" ]; then
    package_path="$path/$CREDENTIAL_PACKAGE_NAME"
    count="$(count_login_state_package "$package_path")"
    echo "  [正常] 登录状态解密测试通过：$count 个文件。"
  elif [ "$protection" = "windows-dpapi-current-user" ]; then
    echo "  [提示] 这是 Windows DPAPI 凭证包，macOS 不能解密。"
  fi
}

restore_backup() {
  assert_codex_closed || return 1
  select_backup || return 1
  verify_backup_by_json "$SELECTED_BACKUP_JSON" || return 1

  local confirm name path protection result package_path restore_login
  printf "\n  恢复会覆盖当前聊天记录；操作前会自动创建完整安全备份。\n"
  read -r -p "  输入 RESTORE 确认 " confirm
  [ "$confirm" = "RESTORE" ] || { echo "  [取消] 未做修改。"; return 0; }

  new_backup true || return 1
  name="$(printf '%s' "$SELECTED_BACKUP_JSON" | json_get "name")"
  path="$(printf '%s' "$SELECTED_BACKUP_JSON" | json_get "path")"
  protection="$(printf '%s' "$SELECTED_BACKUP_JSON" | json_get "credentialProtection")"
  result="$(invoke_core restore "$name")" || return 1
  if [ "$protection" = "macos-keychain-current-user" ]; then
    package_path="$path/$CREDENTIAL_PACKAGE_NAME"
    read -r -p "  是否同时恢复登录状态和 API 配置？[Y/N] " restore_login
    restore_login="$(printf '%s' "$restore_login" | tr '[:lower:]' '[:upper:]')"
    if [ "$restore_login" = "Y" ]; then
      restore_login_state "$package_path" || return 1
      echo "  [完成] 登录状态和 API 配置已恢复。"
    fi
  elif [ "$protection" = "windows-dpapi-current-user" ]; then
    echo "  [提示] 这是 Windows DPAPI 凭证包，macOS 只能恢复聊天记录。"
  fi
  echo "  [完成] 聊天记录已恢复，请重新启动 Codex。"
  echo "  恢复来源：$(printf '%s' "$result" | json_get "restoredFrom")"
}

enable_unified_history() {
  assert_codex_closed || return 1
  local config_result history_result
  config_result="$(invoke_core unify-config)" || return 1
  history_result="$(invoke_core normalize-provider openai)" || return 1
  echo "  [完成] 桌面 Provider：openai；更新历史会话：$(printf '%s' "$history_result" | json_get "changed") 个。"
  local backup_path
  backup_path="$(printf '%s' "$config_result" | json_get "backupPath")"
  if [ -n "$backup_path" ]; then
    echo "  配置备份：$backup_path"
  fi
}

show_login_status() {
  printf "\n  Codex 登录状态\n"
  "$CODEX_EXE" login status || {
    die "Codex 登录状态检查失败。"
    return 1
  }
}

open_resume_picker() {
  osascript <<EOF >/dev/null 2>&1 || "$CODEX_EXE" resume --all
tell application "Terminal"
  do script "$(printf '%q resume --all' "$CODEX_EXE")"
  activate
end tell
EOF
}

write_portable_install_files() {
  local package_dir="$1"
  cat > "$package_dir/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="$HOME/.codex/tools/history-manager-mac"
mkdir -p "$TARGET"
cp "$SOURCE_DIR/Codex-History-Manager.sh" "$TARGET/"
cp "$SOURCE_DIR/codex-history-core.mjs" "$TARGET/"
cp "$SOURCE_DIR/README-zh.md" "$TARGET/使用说明.md"
chmod +x "$TARGET/Codex-History-Manager.sh"

DESKTOP="$HOME/Desktop"
mkdir -p "$DESKTOP"
LAUNCHER="$DESKTOP/Codex-Chat-History-Manager.command"
cat > "$LAUNCHER" <<LAUNCHER_EOF
#!/usr/bin/env bash
"$TARGET/Codex-History-Manager.sh" "\$@"
printf "\\n"
read -r -p "Press Enter to close..."
LAUNCHER_EOF
chmod +x "$LAUNCHER"

echo ""
echo "Installed to: $TARGET"
echo "Desktop launcher: $LAUNCHER"
echo ""
EOF
  chmod +x "$package_dir/install.sh"
  cat > "$package_dir/README.md" <<'EOF'
# Codex Chat History Manager macOS Portable Package

Install:

1. Make sure Codex Desktop is installed.
2. Unzip this package.
3. Open Terminal in the package folder.
4. Run `chmod +x install.sh && ./install.sh`.
5. Open `Codex-Chat-History-Manager.command` on your Desktop.

This package contains only the manager scripts and documentation. It does not contain the exporter user's chat history, login credentials, API keys, backups, or personal configuration.

The tool manages the current user's `~/.codex` directory by default. Set `CODEX_HOME` first if you use a custom Codex Home.
EOF
}

export_portable_tool_package() {
  local export_root stamp package_dir zip_path
  export_root="$CODEX_HOME_DIR/tool-exports"
  mkdir -p "$export_root"
  stamp="$(date +%Y%m%d-%H%M%S)"
  package_dir="$export_root/Codex-Chat-History-Manager-mac-$stamp"
  mkdir -p "$package_dir"

  cp "$TOOL_DIRECTORY/Codex-History-Manager.sh" "$package_dir/"
  cp "$CORE_SCRIPT" "$package_dir/codex-history-core.mjs"
  if [ -f "$TOOL_DIRECTORY/使用说明.md" ]; then
    cp "$TOOL_DIRECTORY/使用说明.md" "$package_dir/README-zh.md"
  elif [ -f "$SCRIPT_DIR/../README-zh.md" ]; then
    cp "$SCRIPT_DIR/../README-zh.md" "$package_dir/README-zh.md"
  else
    touch "$package_dir/README-zh.md"
  fi
  write_portable_install_files "$package_dir"

  zip_path="$package_dir.zip"
  rm -f "$zip_path"
  (cd "$export_root" && zip -qr "$(basename "$zip_path")" "$(basename "$package_dir")") || {
    die "便携安装包压缩失败：$zip_path"
    return 1
  }
  echo ""
  echo "  [完成] 已导出 macOS 便携安装包。"
  echo "  ZIP：$zip_path"
  echo "  该包不包含你的聊天记录、登录凭证、API Key 或备份。"
  open "$export_root"
}

show_help() {
  clear
  cat <<'EOF'
==========================================================================
                         使用说明（macOS）
==========================================================================

  推荐操作
    1. 平时选择 [2] 创建完整备份。
    2. ChatGPT 与 API Key 切换后，历史仍应统一使用 openai Provider。
    3. 使用自定义 API 地址时选择 [7]，不要再创建 openai_http Provider。
    4. 使用主菜单 [P] 保存两个登录档案并一键切换。
    5. 已有合法 ChatGPT 凭证可放入 credential-import，再用 [P] -> [7] 导入。

  凭证安全
    完整备份包含 auth.json、桌面认证文件、config.toml 和 .env。
    这些文件使用 macOS Keychain 保存的密钥 + OpenSSL 加密。
    Keychain 加密包通常只能由当前 macOS 用户解密。
    ChatGPT 令牌被服务器撤销或 API Key 被删除后，旧备份不能恢复其有效性。

  自定义 API 地址
    配置结果使用：model_provider = "openai"
    并在顶层写入：openai_base_url = "https://地址/v1"
    登录仍通过 Codex 的 API Key 登录完成。
    新用户第一次登录可用菜单 [0]，登录成功后再自动备份。
    菜单 [8] 会安全读取 API Key，并通过标准输入交给 Codex。

  命令行调用
    Codex-History-Manager.sh
    Codex-History-Manager.sh -Action status
    Codex-History-Manager.sh -Action backup
    Codex-History-Manager.sh -Action help
    Codex-History-Manager.sh -Action profiles
    Codex-History-Manager.sh -Action first-login
    Codex-History-Manager.sh -Action export-tool

--------------------------------------------------------------------------
EOF
}

show_menu() {
  clear
  cat <<'EOF'
==========================================================================
                    Codex 聊天与登录管理器（macOS）
==========================================================================

  状态与备份
    [1] 查看聊天、登录和 API 配置状态
    [2] 创建完整备份（聊天 + Keychain 加密登录状态）
    [3] 仅备份聊天记录
    [4] 查看并校验已有备份
    [5] 恢复备份

  登录与 API
    [0] 新用户首次 API Key 登录（无登录状态时使用）
    [6] 修复统一历史模式（ChatGPT / API Key 共用）
    [7] 设置或清除自定义 API 地址
    [8] 安全输入 API Key 并登录
    [9] 查看 Codex 登录状态
    [N] 自定义 API 网络模式（自动 / 直连 / 代理）
    [P] ChatGPT / 自定义 API 一键切换

  历史工具
    [A] 用 CLI 打开全部本地历史
    [E] 导出便携安装包（给其他电脑使用）
    [L] 打开备份目录
    [H] 查看内置使用说明

    [Q] 退出

--------------------------------------------------------------------------
EOF
}

run_action() {
  case "$1" in
    status) show_status ;;
    backup) new_backup true ;;
    help) show_help ;;
    profiles) show_login_profiles ;;
    save-chatgpt) save_current_chatgpt_profile ;;
    first-login) first_login_with_api_key ;;
    export-tool) export_portable_tool_package ;;
    *) return 2 ;;
  esac
}

init_runtimes || exit 1

case "$ACTION" in
  menu) ;;
  status|backup|help|profiles|save-chatgpt|first-login|export-tool)
    run_action "$ACTION"
    exit $?
    ;;
  *)
    echo "Unknown action: $ACTION" >&2
    exit 2
    ;;
esac

while true; do
  show_menu
  read -r -p "  请选择功能 " selection
  selection="$(printf '%s' "$selection" | tr '[:lower:]' '[:upper:]')"
  case "$selection" in
    0) first_login_with_api_key ;;
    1) show_status ;;
    2) new_backup true ;;
    3) new_backup false ;;
    4) verify_backup ;;
    5) restore_backup ;;
    6) enable_unified_history ;;
    7) set_custom_api_address ;;
    8) login_with_api_key ;;
    9) show_login_status ;;
    N) show_api_network_menu ;;
    P) show_profile_menu ;;
    A) open_resume_picker ;;
    E) export_portable_tool_package ;;
    L) mkdir -p "$BACKUP_DIRECTORY"; open "$BACKUP_DIRECTORY" ;;
    H) show_help ;;
    Q) break ;;
    *) echo "  [提示] 请输入菜单中的编号或字母。" ;;
  esac
  [ "$selection" = "Q" ] || pause
done
