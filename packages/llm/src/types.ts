export interface CompleteOptions {
  model?: string;
  maxTokens?: number;
  system?: string;
  cache?: { documentContext?: string };
}

export interface LLMProvider {
  readonly name: string;
  complete(prompt: string, opts?: CompleteOptions): Promise<string>;
}

export interface EmbedOptions {
  model?: string;
}

export interface EmbeddingProvider {
  readonly name: string;
  embed(text: string, opts?: EmbedOptions): Promise<Float32Array>;
  embedBatch(texts: string[], opts?: EmbedOptions): Promise<Float32Array[]>;
}
