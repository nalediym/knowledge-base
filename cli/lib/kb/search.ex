defmodule Kb.Search do
  @moduledoc """
  Hybrid retrieval over the SQLite index built by `Kb.Index`.

  - `fts/3`       — FTS5 keyword hits ranked by bm25.
  - `semantic/3`  — cosine similarity against the embeddings sidecar.
  - `hybrid/3`    — reciprocal-rank fusion of the two above.
  """

  alias Exqlite.Sqlite3
  alias Kb.Vector

  @rrf_k 60
  @default_top_k 20

  @type hit :: %{
          path: String.t(),
          chunk_id: String.t(),
          title: String.t() | nil,
          score: float(),
          source: :fts | :semantic | :hybrid,
          components: map()
        }

  @doc """
  Run a full-text search. Returns a list of `%{path, chunk_id, title, score}`
  ordered by bm25 ascending (lower is better), converted to descending score.

  `query` is escaped for FTS5 (quoted per-token) so questions can be raw user input.
  """
  def fts(conn, query, opts \\ []) do
    top_k = Keyword.get(opts, :top_k, @default_top_k)
    match = fts_query(query)

    case Sqlite3.prepare(
           conn,
           """
           SELECT path, chunk_id, title, bm25(pages_fts) AS score
           FROM pages_fts
           WHERE pages_fts MATCH ?1
           ORDER BY score ASC
           LIMIT ?2
           """
         ) do
      {:ok, stmt} ->
        :ok = Sqlite3.bind(stmt, [match, top_k])
        rows = Kb.Index.fetch_all(conn, stmt)
        Sqlite3.release(conn, stmt)

        rows
        |> Enum.map(fn [path, cid, title, bm25] ->
          %{
            path: path,
            chunk_id: cid,
            title: title,
            score: -1.0 * (bm25 || 0.0),
            source: :fts
          }
        end)

      {:error, _} ->
        []
    end
  end

  @doc """
  Run a semantic search by embedding `query` via Ollama and scoring cosine against
  stored chunk embeddings. Returns `[]` if embeddings table is empty or Ollama is
  unreachable.
  """
  def semantic(conn, query, opts \\ []) do
    top_k = Keyword.get(opts, :top_k, @default_top_k)

    if has_embeddings?(conn) do
      case Kb.Ollama.embed(query, opts) do
        {:ok, qvec} ->
          {:ok, stmt} =
            Sqlite3.prepare(conn, """
            SELECT e.path, e.chunk_id, p.title, e.vector
            FROM embeddings e
            JOIN pages p ON p.path = e.path AND p.chunk_id = e.chunk_id
            """)

          rows = Kb.Index.fetch_all(conn, stmt)
          Sqlite3.release(conn, stmt)

          rows
          |> Enum.map(fn [path, cid, title, blob] ->
            vec = Vector.from_blob(blob)
            score = Vector.cosine(qvec, vec)
            %{path: path, chunk_id: cid, title: title, score: score, source: :semantic}
          end)
          |> Enum.sort_by(& &1.score, :desc)
          |> Enum.take(top_k)

        {:error, _} ->
          []
      end
    else
      []
    end
  end

  @doc """
  Hybrid retrieval: run FTS, optionally run semantic, and merge results with
  reciprocal-rank fusion: `score = Σ 1 / (k + rank_i)`.

  Options:
    * `:top_k`       — per-source K (default #{@default_top_k})
    * `:top_n`       — returned merged count (default `top_k`)
    * `:k`           — RRF constant (default #{@rrf_k})
    * `:embeddings`  — force on/off. Default auto (on when sidecar populated).
    * `:ollama_url`, `:ollama_model`
  """
  def hybrid(conn, query, opts \\ []) do
    top_k = Keyword.get(opts, :top_k, @default_top_k)
    top_n = Keyword.get(opts, :top_n, top_k)
    k = Keyword.get(opts, :k, @rrf_k)
    use_embeddings? = Keyword.get(opts, :embeddings, has_embeddings?(conn))

    fts_hits = fts(conn, query, top_k: top_k)

    sem_hits =
      if use_embeddings?,
        do: semantic(conn, query, Keyword.put(opts, :top_k, top_k)),
        else: []

    rrf_merge(fts_hits, sem_hits, k: k, top_n: top_n)
  end

  @doc """
  Fuse two ranked lists with reciprocal-rank fusion. Pure function, exposed for tests.

  Each entry is matched by `{path, chunk_id}`.
  """
  def rrf_merge(list_a, list_b, opts \\ []) do
    k = Keyword.get(opts, :k, @rrf_k)
    top_n = Keyword.get(opts, :top_n, @default_top_k)

    a_ranked = Enum.with_index(list_a, 1)
    b_ranked = Enum.with_index(list_b, 1)

    scored_a =
      Enum.reduce(a_ranked, %{}, fn {hit, rank}, acc ->
        key = {hit.path, hit.chunk_id}
        rrf = 1.0 / (k + rank)
        Map.put(acc, key, {hit, rrf, 0.0})
      end)

    merged =
      Enum.reduce(b_ranked, scored_a, fn {hit, rank}, acc ->
        key = {hit.path, hit.chunk_id}
        rrf = 1.0 / (k + rank)

        Map.update(acc, key, {hit, 0.0, rrf}, fn {existing, fts_s, _} ->
          {existing, fts_s, rrf}
        end)
      end)

    merged
    |> Enum.map(fn {_key, {hit, fts_s, sem_s}} ->
      %{
        path: hit.path,
        chunk_id: hit.chunk_id,
        title: hit.title,
        score: fts_s + sem_s,
        source: :hybrid,
        components: %{fts: fts_s, semantic: sem_s}
      }
    end)
    |> Enum.sort_by(& &1.score, :desc)
    |> Enum.take(top_n)
  end

  @doc "Does the embeddings table contain rows?"
  def has_embeddings?(conn) do
    {:ok, stmt} = Sqlite3.prepare(conn, "SELECT COUNT(*) FROM embeddings LIMIT 1")

    case Sqlite3.step(conn, stmt) do
      {:row, [n]} ->
        Sqlite3.release(conn, stmt)
        n > 0

      _ ->
        Sqlite3.release(conn, stmt)
        false
    end
  end

  # --- helpers ---------------------------------------------------------------

  # Escape and quote each term so FTS5 accepts punctuation-heavy questions.
  # Also strip operator characters that can break the parser.
  defp fts_query(q) do
    q
    |> String.replace(~r/[^\p{L}\p{N}\s]/u, " ")
    |> String.split(~r/\s+/, trim: true)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&~s("#{&1}"))
    |> Enum.join(" OR ")
    |> case do
      "" -> ~s("")
      s -> s
    end
  end
end
