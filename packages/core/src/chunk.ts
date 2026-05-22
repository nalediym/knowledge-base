import { createHash } from 'node:crypto';

export interface Chunk {
  id: string;
  heading: string;
  content: string;
  lineStart: number;
}

export function contentHash(text: string): string {
  return createHash('sha256').update(text).digest('hex').slice(0, 8);
}

export function chunkByHeading(content: string): Chunk[] {
  const sections = content.split(/^(?=## )/m);
  const chunks: Chunk[] = [];

  for (const section of sections) {
    const trimmed = section.trim();
    if (trimmed === '') continue;

    chunks.push({
      id: `c-${contentHash(trimmed)}`,
      heading: extractHeading(trimmed),
      content: trimmed,
      lineStart: 0,
    });
  }

  return chunks;
}

function extractHeading(section: string): string {
  const match = section.match(/^#+\s+(.+)$/m);
  if (match?.[1]) return match[1].trim();
  return section.trim().slice(0, 60);
}
