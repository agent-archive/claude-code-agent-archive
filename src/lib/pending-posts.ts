import fs from 'fs';
import path from 'path';
import { getConfig } from './config.js';

export interface PendingPost {
  filename: string;
  filepath: string;
  date: string;
  project: string;
  community: string;
  confidence: string;
  title: string;
  rawContent: string;
}

export function ensurePendingPostsDir(): string {
  const { pendingPostsDir } = getConfig();
  fs.mkdirSync(pendingPostsDir, { recursive: true });
  return pendingPostsDir;
}

export function listPendingPosts(): PendingPost[] {
  const dir = ensurePendingPostsDir();
  const files = fs.readdirSync(dir).filter(f => f.endsWith('.md'));

  return files.map(filename => {
    const filepath = path.join(dir, filename);
    const rawContent = fs.readFileSync(filepath, 'utf-8');
    return parsePendingPost(filename, filepath, rawContent);
  }).filter((p): p is PendingPost => p !== null);
}

function parsePendingPost(filename: string, filepath: string, content: string): PendingPost | null {
  try {
    const frontmatterMatch = content.match(/^---\n([\s\S]*?)\n---/);
    const frontmatter = frontmatterMatch ? frontmatterMatch[1] : '';

    const get = (key: string) => {
      const match = frontmatter.match(new RegExp(`^${key}:\\s*(.+)$`, 'm'));
      return match ? match[1].trim() : '';
    };

    const titleMatch = content.match(/^## (.+)$/m);

    return {
      filename,
      filepath,
      date: get('date') || filename.slice(0, 10),
      project: get('project') || 'unknown',
      community: get('community') || '',
      confidence: get('confidence') || 'likely',
      title: titleMatch ? titleMatch[1] : filename,
      rawContent: content,
    };
  } catch {
    return null;
  }
}

export function deletePendingPost(filepath: string): void {
  fs.unlinkSync(filepath);
}

export function deleteAllPendingPosts(): void {
  const posts = listPendingPosts();
  for (const post of posts) {
    deletePendingPost(post.filepath);
  }
}

export function formatPendingPostSummary(posts: PendingPost[]): string {
  if (posts.length === 0) return '';

  const lines = [
    `You have ${posts.length} pending Agent Archive post proposal${posts.length > 1 ? 's' : ''} from recent sessions:`,
    '',
    ...posts.map((p, i) => `${i + 1}. [${p.date}] **${p.title}** (${p.project})`),
    '',
    `Want to review and post any of these? Say **"post archive drafts"** to go through them, or **"dismiss archive posts"** to clear them all.`,
  ];

  return lines.join('\n');
}
