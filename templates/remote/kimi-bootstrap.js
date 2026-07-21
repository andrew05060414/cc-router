// ccr kimi bootstrap: enable third-party model support, skip onboarding,
// and remove stale model-id env keys from ~/.claude/settings.json so the
// runtime env (exported by `ccr kimi`) is the single source of model config.
// Mirrors the official Kimi-for-coding Claude Code onboarding script.
const path = require('path');
const os = require('os');
const fs = require('fs');

// 1. enable third-party model support + fast mode, mark onboarding done
const claudeJsonFilePath = path.join(os.homedir(), '.claude.json');
if (fs.existsSync(claudeJsonFilePath)) {
  const content = JSON.parse(fs.readFileSync(claudeJsonFilePath, 'utf-8'));
  fs.writeFileSync(
    claudeJsonFilePath,
    JSON.stringify({ ...content, penguinModeOrgEnabled: true, hasCompletedOnboarding: true }, null, 2),
    'utf-8'
  );
} else {
  fs.writeFileSync(
    claudeJsonFilePath,
    JSON.stringify({ penguinModeOrgEnabled: true, hasCompletedOnboarding: true }, null, 2),
    'utf-8'
  );
}

// 2. delete stale model-id keys from ~/.claude/settings.json env
const claudeSettingsJsonFilePath = path.join(os.homedir(), '.claude', 'settings.json');
if (fs.existsSync(claudeSettingsJsonFilePath)) {
  const content = JSON.parse(fs.readFileSync(claudeSettingsJsonFilePath, 'utf-8'));
  if (typeof content === 'object' && typeof content.env === 'object') {
    for (const element of [
      'ANTHROPIC_MODEL',
      'ANTHROPIC_SMALL_FAST_MODEL',
      'CLAUDE_CODE_SUBAGENT_MODEL',
      'ANTHROPIC_DEFAULT_FABLE_MODEL',
      'ANTHROPIC_DEFAULT_FABLE_MODEL_NAME',
      'ANTHROPIC_DEFAULT_OPUS_MODEL',
      'ANTHROPIC_DEFAULT_OPUS_MODEL_NAME',
      'ANTHROPIC_DEFAULT_SONNET_MODEL',
      'ANTHROPIC_DEFAULT_SONNET_MODEL_NAME',
      'ANTHROPIC_DEFAULT_HAIKU_MODEL',
      'ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME',
    ]) {
      delete content.env[element];
    }
    fs.writeFileSync(claudeSettingsJsonFilePath, JSON.stringify(content, null, 2), 'utf-8');
  }
}

console.log('[ccr kimi] bootstrap done: ~/.claude.json onboarding set, stale model env keys removed');
