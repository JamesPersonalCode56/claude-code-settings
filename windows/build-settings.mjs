// Build a Windows-fleet ~/.claude/settings.json from the repo's settings.json,
// folding the Qwen connection + model lineup (read from env/models-qwen.env) into
// the `env` block so a headless `claude` (and `claude -p`) talks to the Alibaba
// MaaS endpoint with no shell switch. Cross-platform tweaks vs. the Linux
// daily-driver settings:
//   - DROP `hooks` (the rtk PreToolUse hook is a Linux-only ELF; would error on
//     every Bash call under Git Bash).
//   - DROP `statusLine` (depends on OMC plugin `hud/` files not shipped here).
//   - DROP `enabledPlugins` + `extraKnownMarketplaces` (the heavy OMC marketplace
//     is not part of this skill bundle and can destabilize a `claude -p` worker).
// Usage: node build-settings.mjs <repoDir> <outFile> <fleetName> <userId>
import fs from 'node:fs';
import path from 'node:path';

const [, , repoDir, outFile, fleetName, userId] = process.argv;
if (!repoDir || !outFile) {
  console.error('usage: node build-settings.mjs <repoDir> <outFile> [fleetName] [userId]');
  process.exit(2);
}

// Minimal `.env`-style parser: KEY='v' | KEY="v" | KEY=v, ignoring # comments.
function parseEnv(file) {
  const out = {};
  if (!fs.existsSync(file)) return out;
  for (const raw of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;
    const m = line.match(/^([A-Za-z_][A-Za-z0-9_]*)=(.*)$/);
    if (!m) continue;
    let v = m[2].trim();
    if ((v.startsWith("'") && v.endsWith("'")) || (v.startsWith('"') && v.endsWith('"'))) {
      v = v.slice(1, -1);
    }
    out[m[1]] = v;
  }
  return out;
}

// First existing Git-Bash bash.exe, normalized to forward slashes; else bare 'bash'.
// Claude Code runs apiKeyHelper via cmd, where Git Bash is usually NOT on PATH, so
// an absolute path is needed (the bare-`bash` form is a fallback only).
function findBashExe() {
  const candidates = [
    'C:\\Program Files\\Git\\bin\\bash.exe',
    'C:\\Program Files (x86)\\Git\\bin\\bash.exe',
  ];
  if (process.env.LOCALAPPDATA) {
    candidates.push(`${process.env.LOCALAPPDATA}\\Programs\\Git\\bin\\bash.exe`);
  }
  for (const c of candidates) {
    if (fs.existsSync(c)) return c.replace(/\\/g, '/');
  }
  return 'bash';
}

const settings = JSON.parse(fs.readFileSync(path.join(repoDir, 'settings', 'settings.json'), 'utf8'));
const qwen = parseEnv(path.join(repoDir, 'env', 'models-qwen.env'));

if (!qwen.BASE_URL || !qwen.API_KEYS) {
  console.error('build-settings: env/models-qwen.env missing BASE_URL/API_KEYS — cannot provision Qwen creds');
  process.exit(1);
}
if (qwen.API_KEYS.includes('xxxxxxxx')) {
  console.error('build-settings: API_KEYS is still the placeholder — refusing to write');
  process.exit(1);
}

settings.env = settings.env || {};
// Qwen connection. The token is NOT baked into settings.json — settings.json
// `env` is for non-sensitive values (per Claude Code docs), so the secret stays
// in the gitignored env/models-qwen.env and is fetched at runtime by apiKeyHelper.
// Base URL + model lineup are non-secret and remain in env.
settings.env.ANTHROPIC_BASE_URL = qwen.BASE_URL;
const bashExe = findBashExe();
const helper = path.join(repoDir, 'vendor', 'claude-switch', 'qwen-key-helper.sh').replace(/\\/g, '/');
// apiKeyHelper runs through the system shell (cmd on Windows); invoke the shared
// .sh reader via bash (the fleet ships Git Bash). Same script the Linux switch uses.
settings.apiKeyHelper = bashExe.includes(' ') ? `"${bashExe}" "${helper}"` : `${bashExe} "${helper}"`;
// Model lineup (version-controlled, non-secret) — exclude the secret + base url.
for (const [k, v] of Object.entries(qwen)) {
  if (k === 'BASE_URL' || k === 'API_KEYS') continue;
  settings.env[k] = v;
}
// Per-host telemetry identity (machine = fleet name, auth = qwen).
const machine = fleetName || 'unknown';
const uid = userId || 'agency';
settings.env.OTEL_RESOURCE_ATTRIBUTES = `machine=${machine},user.id=${uid},auth=qwen`;

// Windows-incompatible / out-of-scope blocks.
delete settings.hooks;          // rtk = Linux ELF
delete settings.statusLine;     // OMC hud/ not shipped
delete settings.enabledPlugins; // OMC marketplace out of scope for a fleet worker
delete settings.extraKnownMarketplaces;

fs.mkdirSync(path.dirname(outFile), { recursive: true });
fs.writeFileSync(outFile, JSON.stringify(settings, null, 2) + '\n');
console.log(`wrote ${outFile} (machine=${machine}, model=${settings.model}, base_url set, apiKeyHelper set)`);
