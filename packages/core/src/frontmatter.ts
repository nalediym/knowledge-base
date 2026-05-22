export type FrontmatterValue = string | number | boolean;
export type Frontmatter = Record<string, FrontmatterValue>;

export interface ParsedDoc {
  data: Frontmatter;
  body: string;
}

const FENCE = '---';

export function parseFrontmatter(input: string): ParsedDoc {
  if (!input.startsWith(`${FENCE}\n`)) {
    return { data: {}, body: input };
  }

  const rest = input.slice(FENCE.length + 1);
  const endIdx = rest.indexOf(`\n${FENCE}\n`);
  if (endIdx === -1) {
    return { data: {}, body: input };
  }

  const yaml = rest.slice(0, endIdx);
  let body = rest.slice(endIdx + FENCE.length + 2);
  if (body.startsWith('\n')) body = body.slice(1);
  const data = parseSimpleYaml(yaml);

  return { data, body };
}

export function stringifyFrontmatter(data: Frontmatter, body: string): string {
  if (Object.keys(data).length === 0) return body;

  const lines: string[] = [];
  for (const [k, v] of Object.entries(data)) {
    lines.push(`${k}: ${formatValue(v)}`);
  }
  return `${FENCE}\n${lines.join('\n')}\n${FENCE}\n\n${body}`;
}

function parseSimpleYaml(yaml: string): Frontmatter {
  const out: Frontmatter = {};
  for (const rawLine of yaml.split('\n')) {
    const line = rawLine.trim();
    if (!line || line.startsWith('#')) continue;
    const colonIdx = line.indexOf(':');
    if (colonIdx === -1) continue;
    const key = line.slice(0, colonIdx).trim();
    const raw = line.slice(colonIdx + 1).trim();
    out[key] = coerce(raw);
  }
  return out;
}

function coerce(raw: string): FrontmatterValue {
  const stripped = raw.replace(/^['"]|['"]$/g, '');
  if (stripped === 'true') return true;
  if (stripped === 'false') return false;
  if (/^-?\d+(\.\d+)?$/.test(stripped)) return Number(stripped);
  return stripped;
}

function formatValue(v: FrontmatterValue): string {
  return String(v);
}
