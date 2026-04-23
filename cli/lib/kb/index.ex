defmodule Kb.Index do
  @moduledoc """
  SQLite FTS5 index over `kb/wiki/**/*.md` (and optionally `kb/raw/**/*.md`).

  Also supports an optional per-chunk embeddings sidecar table populated via
  Ollama. RRF-based hybrid search is implemented in `Kb.Search`.

  Schema:

      pages(path TEXT, chunk_id TEXT, title TEXT, content TEXT, mtime INTEGER,
            PRIMARY KEY (path, chunk_id))
      pages_fts  -- FTS5 virtual table over (title, content)
      embeddings(path TEXT, chunk_id TEXT, model TEXT, dim INTEGER, vector BLOB,
                 PRIMARY KEY (path, chunk_id, model))
      meta(key TEXT PRIMARY KEY, value TEXT)

  Incremental: only chunks whose source file mtime differs from the recorded
  value are reindexed.
  """

  alias Exqlite.Sqlite3
  alias Kb.Chunk

  @default_index_path "kb/.index/search.sqlite"
  @fts_tokenizer "porter unicode61 remove_diacritics 2"

  @doc "Absolute or project-relative index path."
  def default_path, do: @default_index_path

  @doc """
  Open (and migrate) the SQLite index. Returns `{:ok, conn}`.

  Creates the parent directory if missing.
  """
  def open(path \\ @default_index_path) do
    File.mkdir_p!(Path.dirname(path))
    {:ok, conn} = Sqlite3.open(path)
    :ok = migrate!(conn)
    {:ok, conn}
  end

  @doc "Close the SQLite connection."
  def close(conn), do: Sqlite3.close(conn)

  defp migrate!(conn) do
    Sqlite3.execute(conn, "PRAGMA journal_mode=WAL;")
    Sqlite3.execute(conn, "PRAGMA synchronous=NORMAL;")

    Sqlite3.execute(conn, """
    CREATE TABLE IF NOT EXISTS pages (
      path     TEXT NOT NULL,
      chunk_id TEXT NOT NULL,
      title    TEXT,
      content  TEXT,
      mtime    INTEGER,
      PRIMARY KEY (path, chunk_id)
    );
    """)

    Sqlite3.execute(conn, """
    CREATE VIRTUAL TABLE IF NOT EXISTS pages_fts USING fts5(
      title, content, path UNINDEXED, chunk_id UNINDEXED,
      tokenize = '#{@fts_tokenizer}'
    );
    """)

    Sqlite3.execute(conn, """
    CREATE TABLE IF NOT EXISTS embeddings (
      path     TEXT NOT NULL,
      chunk_id TEXT NOT NULL,
      model    TEXT NOT NULL,
      dim      INTEGER NOT NULL,
      vector   BLOB NOT NULL,
      PRIMARY KEY (path, chunk_id, model)
    );
    """)

    Sqlite3.execute(conn, """
    CREATE TABLE IF NOT EXISTS meta (
      key   TEXT PRIMARY KEY,
      value TEXT
    );
    """)

    :ok
  end

  @doc """
  Build the FTS index over markdown files.

  Options:
    * `:root`          — project root (defaults to cwd)
    * `:index_path`    — override the sqlite path
    * `:include_raw`   — also index `kb/raw/**/*.md` (default false)
    * `:embeddings`    — also populate embeddings via Ollama (default false)
    * `:ollama_url`    — ollama endpoint (default `http://localhost:11434/api/embeddings`)
    * `:ollama_model`  — embeddings model (default `nomic-embed-text`)

  Returns a `{:ok, stats}` map `%{files: n, chunks: n, reindexed: n, embedded: n}`.
  """
  def build(opts \\ []) do
    root = Keyword.get(opts, :root, File.cwd!())
    index_path = Keyword.get(opts, :index_path, Path.join(root, @default_index_path))
    include_raw? = Keyword.get(opts, :include_raw, false)
    want_embeddings? = Keyword.get(opts, :embeddings, false)

    files = collect_files(root, include_raw?)
    {:ok, conn} = open(index_path)

    try do
      known_mtimes = load_mtimes(conn)

      stats =
        Enum.reduce(files, %{files: 0, chunks: 0, reindexed: 0, embedded: 0}, fn file, acc ->
          process_file(conn, file, root, known_mtimes, want_embeddings?, opts, acc)
        end)

      prune_missing(conn, files, root)

      {:ok, stats}
    after
      close(conn)
    end
  end

  defp collect_files(root, include_raw?) do
    wiki = Path.wildcard(Path.join(root, "kb/wiki/**/*.md"))
    raw = if include_raw?, do: Path.wildcard(Path.join(root, "kb/raw/**/*.md")), else: []
    Enum.sort(wiki ++ raw)
  end

  defp load_mtimes(conn) do
    {:ok, stmt} = Sqlite3.prepare(conn, "SELECT path, MAX(mtime) FROM pages GROUP BY path")
    rows = fetch_all(conn, stmt)
    Sqlite3.release(conn, stmt)
    Map.new(rows, fn [path, mtime] -> {path, mtime} end)
  end

  defp process_file(conn, abs_path, root, known_mtimes, want_embeddings?, opts, acc) do
    rel = Path.relative_to(abs_path, root)

    case File.stat(abs_path, time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} ->
        prev = Map.get(known_mtimes, rel)

        if prev == mtime do
          %{acc | files: acc.files + 1}
        else
          content = File.read!(abs_path)
          title = extract_title(content, rel)
          chunks = chunks_for(content)

          delete_file(conn, rel)
          insert_chunks(conn, rel, title, mtime, chunks)

          embedded =
            if want_embeddings? do
              embed_chunks(conn, rel, chunks, opts)
            else
              0
            end

          %{
            acc
            | files: acc.files + 1,
              chunks: acc.chunks + length(chunks),
              reindexed: acc.reindexed + 1,
              embedded: acc.embedded + embedded
          }
        end

      _ ->
        acc
    end
  end

  defp chunks_for(content) do
    case Chunk.chunk_by_heading(content) do
      [] ->
        trimmed = String.trim(content)

        if trimmed == "" do
          []
        else
          [
            %Chunk{
              id: "c-" <> Chunk.content_hash(trimmed),
              heading: "",
              content: trimmed,
              line_start: 0
            }
          ]
        end

      chunks ->
        chunks
    end
  end

  defp extract_title(content, rel) do
    case Regex.run(~r/^#\s+(.+)$/m, content) do
      [_, h] -> String.trim(h)
      _ -> Path.basename(rel, ".md")
    end
  end

  defp delete_file(conn, rel) do
    {:ok, s} = Sqlite3.prepare(conn, "DELETE FROM pages WHERE path = ?1")
    :ok = Sqlite3.bind(s, [rel])
    :done = Sqlite3.step(conn, s)
    Sqlite3.release(conn, s)

    {:ok, s2} = Sqlite3.prepare(conn, "DELETE FROM pages_fts WHERE path = ?1")
    :ok = Sqlite3.bind(s2, [rel])
    :done = Sqlite3.step(conn, s2)
    Sqlite3.release(conn, s2)

    {:ok, s3} = Sqlite3.prepare(conn, "DELETE FROM embeddings WHERE path = ?1")
    :ok = Sqlite3.bind(s3, [rel])
    :done = Sqlite3.step(conn, s3)
    Sqlite3.release(conn, s3)
  end

  defp insert_chunks(conn, rel, title, mtime, chunks) do
    Sqlite3.execute(conn, "BEGIN;")

    {:ok, page_stmt} =
      Sqlite3.prepare(
        conn,
        "INSERT INTO pages(path, chunk_id, title, content, mtime) VALUES (?1, ?2, ?3, ?4, ?5)"
      )

    {:ok, fts_stmt} =
      Sqlite3.prepare(
        conn,
        "INSERT INTO pages_fts(path, chunk_id, title, content) VALUES (?1, ?2, ?3, ?4)"
      )

    Enum.each(chunks, fn %Chunk{id: cid, content: content} ->
      :ok = Sqlite3.bind(page_stmt, [rel, cid, title, content, mtime])
      :done = Sqlite3.step(conn, page_stmt)

      :ok = Sqlite3.bind(fts_stmt, [rel, cid, title, content])
      :done = Sqlite3.step(conn, fts_stmt)
    end)

    Sqlite3.release(conn, page_stmt)
    Sqlite3.release(conn, fts_stmt)
    Sqlite3.execute(conn, "COMMIT;")
  end

  defp embed_chunks(conn, rel, chunks, opts) do
    model = Keyword.get(opts, :ollama_model, "nomic-embed-text")
    url = Keyword.get(opts, :ollama_url, "http://localhost:11434/api/embeddings")

    case Kb.Ollama.ping(url) do
      :ok ->
        {:ok, ins} =
          Sqlite3.prepare(
            conn,
            "INSERT OR REPLACE INTO embeddings(path, chunk_id, model, dim, vector) VALUES (?1, ?2, ?3, ?4, ?5)"
          )

        count =
          Enum.reduce(chunks, 0, fn %Chunk{id: cid, content: content}, n ->
            case Kb.Ollama.embed(content, url: url, model: model) do
              {:ok, vec} ->
                blob = Kb.Vector.to_blob(vec)
                :ok = Sqlite3.bind(ins, [rel, cid, model, length(vec), blob])
                :done = Sqlite3.step(conn, ins)
                n + 1

              {:error, _} ->
                n
            end
          end)

        Sqlite3.release(conn, ins)
        count

      {:error, _} ->
        0
    end
  end

  defp prune_missing(conn, files, root) do
    rels =
      files
      |> Enum.map(&Path.relative_to(&1, root))
      |> MapSet.new()

    {:ok, stmt} = Sqlite3.prepare(conn, "SELECT DISTINCT path FROM pages")
    all = fetch_all(conn, stmt) |> Enum.map(&hd/1)
    Sqlite3.release(conn, stmt)

    Enum.each(all, fn path ->
      if not MapSet.member?(rels, path), do: delete_file(conn, path)
    end)
  end

  @doc false
  def fetch_all(conn, stmt, acc \\ []) do
    case Sqlite3.step(conn, stmt) do
      {:row, row} -> fetch_all(conn, stmt, [row | acc])
      :done -> Enum.reverse(acc)
    end
  end
end
