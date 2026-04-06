/**
 * Content sanitization — TypeScript port of openclaw-agent-archive/scripts/sanitize.py
 * Strips credentials, PII, paths, and tokens before content is shown to users for approval.
 */

export type SanitizeResult =
  | { ok: true; content: string; redactionCount: number }
  | { ok: false; reason: string };

// Private file markers that cause an immediate block (exit code 1 equivalent)
const BLOCKED_MARKERS = [
  '# MEMORY.md',
  '# CLAUDE.md',
  '# AGENTS.md',
  '# SOUL.md',
  '# USER.md',
  '# IDENTITY.md',
  'openclaw.json',
];

interface RedactRule {
  pattern: RegExp;
  replacement: string;
}

const REDACT_RULES: RedactRule[] = [
  // Private key material
  { pattern: /-----BEGIN [A-Z ]+PRIVATE KEY-----[\s\S]*?-----END [A-Z ]+PRIVATE KEY-----/g, replacement: '[REDACTED_PRIVATE_KEY]' },

  // AWS keys
  { pattern: /\bAKIA[A-Z0-9]{16}\b/g, replacement: '[REDACTED_AWS_KEY]' },

  // Anthropic / OpenAI API keys
  { pattern: /\bsk-ant-[a-zA-Z0-9\-_]{20,}\b/g, replacement: '[REDACTED_ANTHROPIC_KEY]' },
  { pattern: /\bsk-[a-zA-Z0-9]{32,}\b/g, replacement: '[REDACTED_API_KEY]' },

  // Agent Archive API keys
  { pattern: /\bagentarchive_[a-zA-Z0-9_\-]{16,}\b/g, replacement: '[REDACTED_AGENT_ARCHIVE_KEY]' },

  // Generic Bearer tokens
  { pattern: /Bearer\s+[a-zA-Z0-9\-._~+/]+=*/g, replacement: 'Bearer [REDACTED_TOKEN]' },

  // Authorization headers
  { pattern: /Authorization:\s*[^\n]+/gi, replacement: 'Authorization: [REDACTED]' },

  // Notion / Slack / GitHub / Telegram tokens
  { pattern: /\bsecret_[a-zA-Z0-9]{32,}\b/g, replacement: '[REDACTED_NOTION_KEY]' },
  { pattern: /\bxoxb-[a-zA-Z0-9\-]{32,}\b/g, replacement: '[REDACTED_SLACK_TOKEN]' },
  { pattern: /\bghp_[a-zA-Z0-9]{36,}\b/g, replacement: '[REDACTED_GITHUB_TOKEN]' },
  { pattern: /\b\d{8,10}:[a-zA-Z0-9_\-]{35,}\b/g, replacement: '[REDACTED_TELEGRAM_TOKEN]' },

  // URL query secrets
  { pattern: /([?&](?:token|key|password|secret|api_key|apikey|access_token)=)[^\s&"']+/gi, replacement: '$1[REDACTED]' },

  // Environment variable assignments with secret keywords
  { pattern: /\b(PASSWORD|SECRET|API_KEY|APIKEY|TOKEN|PRIVATE_KEY|ACCESS_TOKEN)\s*=\s*[^\s\n"']+/gi, replacement: '$1=[REDACTED]' },

  // Email addresses
  { pattern: /\b[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}\b/g, replacement: '[REDACTED_EMAIL]' },

  // Phone numbers (various formats)
  { pattern: /\b(\+?1[-.\s]?)?\(?\d{3}\)?[-.\s]?\d{3}[-.\s]?\d{4}\b/g, replacement: '[REDACTED_PHONE]' },

  // macOS / Linux / Windows home directory paths
  { pattern: /\/Users\/[a-zA-Z0-9_\-]+\//g, replacement: '/Users/[REDACTED]/' },
  { pattern: /\/home\/[a-zA-Z0-9_\-]+\//g, replacement: '/home/[REDACTED]/' },
  { pattern: /C:\\Users\\[a-zA-Z0-9_\-]+\\/g, replacement: 'C:\\Users\\[REDACTED]\\' },

  // Public IPv4 addresses (excludes private/loopback/test ranges)
  {
    pattern: /\b(?!(?:10\.|172\.(?:1[6-9]|2\d|3[01])\.|192\.168\.|127\.|0\.|169\.254\.|100\.6[4-9]\.|100\.[7-9]\d\.|100\.1[01]\d\.|100\.12[0-7]\.))\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/g,
    replacement: '[REDACTED_IP]',
  },

  // Long hex strings (likely tokens/hashes, 32+ chars)
  { pattern: /\b[a-f0-9]{32,}\b/gi, replacement: '[REDACTED_HEX]' },
];

export function sanitize(content: string, dryRun = false): SanitizeResult {
  // Check for blocked markers first
  for (const marker of BLOCKED_MARKERS) {
    if (content.includes(marker)) {
      return {
        ok: false,
        reason: `Content contains blocked private file marker: "${marker}". Rewrite from scratch without referencing private files.`,
      };
    }
  }

  let result = content;
  let redactionCount = 0;

  for (const rule of REDACT_RULES) {
    const replaced = result.replace(rule.pattern, (match) => {
      redactionCount++;
      return dryRun ? `>>>REDACTED: ${match}<<<` : rule.replacement;
    });
    result = replaced;
  }

  return { ok: true, content: result, redactionCount };
}
