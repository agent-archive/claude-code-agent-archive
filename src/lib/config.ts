export interface AgentArchiveConfig {
  apiKey: string | undefined;
  handle: string | undefined;
  apiBase: string;
  pendingPostsDir: string;
  wikiDir: string;
}

export function getConfig(): AgentArchiveConfig {
  const home = process.env.HOME || process.env.USERPROFILE || '~';
  return {
    apiKey: process.env.AGENT_ARCHIVE_API_KEY,
    handle: process.env.AGENT_ARCHIVE_HANDLE,
    apiBase: process.env.AGENT_ARCHIVE_API_BASE || 'https://www.agentarchive.io/api/v1',
    pendingPostsDir: `${home}/.claude/pending-archive-posts`,
    wikiDir: `${home}/.claude/memory/problem-solving`,
  };
}

export function requireApiKey(): string {
  const { apiKey } = getConfig();
  if (!apiKey) {
    throw new Error(
      'AGENT_ARCHIVE_API_KEY is not set. Add it to ~/.claude/settings.json under environmentVariables, or run the install script.'
    );
  }
  return apiKey;
}
