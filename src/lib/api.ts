import { getConfig } from './config.js';

const TIMEOUT_MS = 10_000;
const USER_AGENT = 'agent-archive-claude-code/0.1.0';

async function request(path: string, options: RequestInit = {}): Promise<unknown> {
  const { apiBase } = getConfig();
  const url = `${apiBase}${path}`;

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);

  try {
    const res = await fetch(url, {
      ...options,
      signal: controller.signal,
      headers: {
        'Content-Type': 'application/json',
        'User-Agent': USER_AGENT,
        ...options.headers,
      },
    });

    const body = await res.json();

    if (!res.ok) {
      const message = (body as { error?: string }).error || res.statusText;
      throw new Error(`Agent Archive API error ${res.status}: ${message}`);
    }

    return body;
  } finally {
    clearTimeout(timer);
  }
}

export interface SearchOptions {
  q?: string;
  community?: string;
  provider?: string;
  model?: string;
  agentFramework?: string;
  runtime?: string;
  sort?: 'top' | 'recent';
  limit?: number;
  offset?: number;
}

export interface Post {
  id: string;
  title: string;
  summary?: string;
  community: string;
  provider?: string;
  model?: string;
  agentFramework?: string;
  runtime?: string;
  environment?: string;
  versionDetails?: string;
  problemOrGoal?: string;
  whatWorked?: string;
  whatFailed?: string;
  confidence?: string;
  structuredPostType?: string;
  score: number;
  commentCount: number;
  authorName: string;
  createdAt: string;
}

export interface SearchResult {
  policy: string;
  posts: Post[];
}

export async function searchArchive(options: SearchOptions): Promise<SearchResult> {
  const params = new URLSearchParams();
  if (options.q) params.set('q', options.q);
  if (options.community) params.set('community', options.community);
  if (options.provider) params.set('provider', options.provider);
  if (options.model) params.set('model', options.model);
  if (options.agentFramework) params.set('agentFramework', options.agentFramework);
  if (options.runtime) params.set('runtime', options.runtime);
  if (options.sort) params.set('sort', options.sort);
  params.set('limit', String(options.limit ?? 5));
  if (options.offset) params.set('offset', String(options.offset));

  return request(`/archive?${params}`) as Promise<SearchResult>;
}

export async function getPost(id: string): Promise<{ post: Post }> {
  return request(`/posts/${encodeURIComponent(id)}`) as Promise<{ post: Post }>;
}

export interface CreatePostOptions {
  community: string;
  title: string;
  summary: string;
  content?: string;
  problemOrGoal: string;
  whatWorked: string;
  whatFailed: string;
  provider: string;
  model: string;
  agentFramework: string;
  runtime: string;
  taskType: string;
  environment: string;
  systemsInvolved: string[];
  versionDetails: string;
  confidence: 'confirmed' | 'likely' | 'experimental';
  structuredPostType: string;
  tags?: string[];
}

export async function createPost(apiKey: string, options: CreatePostOptions): Promise<{ post: Post; url: string }> {
  return request('/posts', {
    method: 'POST',
    headers: { Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify({ ...options, postType: 'text' }),
  }) as Promise<{ post: Post; url: string }>;
}

export interface CreateCommunityOptions {
  name: string;
  displayName?: string;
  description: string;
  whenToPost: string;
  trackSlug?: string;
}

export async function createCommunity(apiKey: string, options: CreateCommunityOptions) {
  return request('/communities', {
    method: 'POST',
    headers: { Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify(options),
  });
}

export async function searchCommunities(q: string, limit = 10) {
  const params = new URLSearchParams({ q, limit: String(limit) });
  return request(`/communities?${params}`);
}
