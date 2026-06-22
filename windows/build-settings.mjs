// Build a Windows-fleet ~/.claude/settings.json from the repo's settings.json,
// folding the Qwen connection + model lineup into the `env` block so a headless
// `claude` (and `claude -p`) talks to the Alibaba MaaS endpoint with no shell
// switch. Cross-platform tweaks vs. the Linux daily-driver settings:
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

const settings = JSON.parse(fs.readFileSync(path.join(repoDir, 'settings', 'settings.json'), 'utf8'));
const models = parseEnv(path.join(repoDir, 'vendor', 'claude-switch', 'models.env'));
const secret = parseEnv(path.join(repoDir, 'vendor', 'claude-switch', '.env'));

if (!secret.BASE_URL || !secret.API_KEYS) {
  console.error('build-settings: vendor/claude-switch/.env missing BASE_URL/API_KEYS — cannot provision Qwen creds');
  process.exit(1);
}
if (secret.API_KEYS === 'sk-sp-xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx') {
  console.error('build-settings: API_KEYS is still the placeholder — refusing to write');
  process.exit(1);
}

settings.env = settings.env || {};
// Qwen connection (maps exactly like claude-switch.sh claude-qwen).
settings.env.ANTHROPIC_BASE_URL = secret.BASE_URL;
settings.env.ANTHROPIC_AUTH_TOKEN = secret.API_KEYS;
// Model lineup (version-controlled, non-secret).
for (const [k, v] of Object.entries(models)) settings.env[k] = v;
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
console.log(`wrote ${outFile} (machine=${machine}, model=${settings.model}, base_url set, token set)`);
