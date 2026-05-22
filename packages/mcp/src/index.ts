import { TOOLS, callTool, type ToolDef } from './tools.ts';

export const PROTOCOL_VERSION = '2024-11-05';
export const SERVER_NAME = 'kb';
export const SERVER_VERSION = '0.3.0-dev';

export interface JsonRpcRequest {
  jsonrpc?: string;
  id?: number | string | null;
  method?: string;
  params?: unknown;
}

export interface JsonRpcResponse {
  jsonrpc: '2.0';
  id: number | string | null;
  result?: unknown;
  error?: { code: number; message: string };
}

/**
 * Handle a single JSON-RPC line. Returns the response object to send,
 * or `null` if the request was a notification.
 */
export async function handleLine(line: string): Promise<JsonRpcResponse | null> {
  const trimmed = line.trim();
  if (!trimmed) return null;
  let req: JsonRpcRequest;
  try {
    req = JSON.parse(trimmed) as JsonRpcRequest;
  } catch {
    return parseErrorResponse();
  }
  return handleRequest(req);
}

export async function handleRequest(req: JsonRpcRequest): Promise<JsonRpcResponse | null> {
  const id = req.id ?? null;
  const method = req.method ?? '';
  const params = (req.params ?? {}) as Record<string, unknown>;

  try {
    const result = await dispatch(method, params);
    if (result === 'notification') return null;
    if (result.kind === 'ok') {
      return { jsonrpc: '2.0', id, result: result.value };
    }
    if (id === undefined || id === null) return null;
    return errorResponse(id, result.code, result.message);
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    if (id === undefined || id === null) return null;
    return errorResponse(id, -32603, `Internal error: ${msg}`);
  }
}

type DispatchOutcome =
  | 'notification'
  | { kind: 'ok'; value: unknown }
  | { kind: 'error'; code: number; message: string };

async function dispatch(method: string, params: Record<string, unknown>): Promise<DispatchOutcome> {
  switch (method) {
    case 'initialize':
      return {
        kind: 'ok',
        value: {
          protocolVersion: PROTOCOL_VERSION,
          serverInfo: { name: SERVER_NAME, version: SERVER_VERSION },
          capabilities: { tools: {} },
        },
      };
    case 'initialized':
    case 'notifications/initialized':
      return 'notification';
    case 'ping':
    case 'shutdown':
      return { kind: 'ok', value: {} };
    case 'tools/list':
      return { kind: 'ok', value: { tools: TOOLS } };
    case 'tools/call': {
      const name = typeof params.name === 'string' ? params.name : '';
      const args = (params.arguments ?? {}) as Record<string, unknown>;
      const result = await callTool(name, args);
      if (result.kind === 'unknown_tool') {
        return { kind: 'error', code: -32602, message: `Unknown tool: ${result.name}` };
      }
      const isError = result.kind === 'error';
      const text = isError ? result.message : result.text;
      return {
        kind: 'ok',
        value: { content: [{ type: 'text', text }], isError },
      };
    }
    default:
      return { kind: 'error', code: -32601, message: `Method not found: ${method}` };
  }
}

function errorResponse(id: number | string | null, code: number, message: string): JsonRpcResponse {
  return { jsonrpc: '2.0', id, error: { code, message } };
}

function parseErrorResponse(): JsonRpcResponse {
  return { jsonrpc: '2.0', id: null, error: { code: -32700, message: 'Parse error' } };
}

/**
 * Run the stdio MCP loop. Blocks until stdin is closed.
 */
export async function runStdio(): Promise<void> {
  process.stderr.write(`[kb-mcp] starting (pid=${process.pid})\n`);
  const decoder = new TextDecoder();
  let buffer = '';
  for await (const chunk of process.stdin as AsyncIterable<Uint8Array>) {
    buffer += decoder.decode(chunk, { stream: true });
    let nl = buffer.indexOf('\n');
    while (nl !== -1) {
      const line = buffer.slice(0, nl);
      buffer = buffer.slice(nl + 1);
      const response = await handleLine(line);
      if (response) process.stdout.write(JSON.stringify(response) + '\n');
      nl = buffer.indexOf('\n');
    }
  }
  if (buffer.trim()) {
    const response = await handleLine(buffer);
    if (response) process.stdout.write(JSON.stringify(response) + '\n');
  }
  process.stderr.write('[kb-mcp] stdin closed; exiting\n');
}

export { TOOLS, callTool };
export type { ToolDef };
export { kbRoot, kbRootWithStatus, kbPresent, safePath } from './path-guard.ts';
