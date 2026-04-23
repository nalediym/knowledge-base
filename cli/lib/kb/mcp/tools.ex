defmodule Kb.MCP.Tools do
  @moduledoc """
  Tool registry + handlers for the `kb mcp` stdio server.

  Each handler returns `{:ok, text}` on success or `{:error, message}` on
  failure. The outer protocol wraps these into MCP tool-call result envelopes.

  Handlers delegate to the existing `Kb.*` command modules where possible.
  When the underlying CLI command streams to stdout (rather than returning a
  value), handlers capture the output with `ExUnit.CaptureIO`-style IO-group
  redirection via `capture/1`.
  """

  alias Kb.MCP

  # ─── Registry ───────────────────────────────────────────────────────────

  @tools [
    %{
      "name" => "kb_query",
      "description" =>
        "Search the knowledge base for a natural-language question. Returns matching source and concept pages with a short snippet. Uses the CLI's keyword search; full LLM synthesis requires the Claude Code skill.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "question" => %{
            "type" => "string",
            "description" => "Natural-language question or keyword(s) to search for."
          },
          "max_pages" => %{
            "type" => "integer",
            "description" => "Maximum pages to include in results (default 10).",
            "default" => 10
          }
        },
        "required" => ["question"]
      }
    },
    %{
      "name" => "kb_search",
      "description" =>
        "Literal substring search across kb/wiki/ (and optionally kb/raw/). Returns file:line matches with no synthesis.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "term" => %{"type" => "string", "description" => "Literal substring to grep for."},
          "include_raw" => %{
            "type" => "boolean",
            "description" => "Also search kb/raw/. Defaults to false (wiki only).",
            "default" => false
          }
        },
        "required" => ["term"]
      }
    },
    %{
      "name" => "kb_list_sources",
      "description" =>
        "List all sources recorded in the KB manifest. Returns path, slug, hash, ingested timestamp, chunk count. Optionally filter by project name.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "project" => %{
            "type" => "string",
            "description" => "Optional project name to filter by (matches manifest.name)."
          }
        }
      }
    },
    %{
      "name" => "kb_read_page",
      "description" =>
        "Return the full content of a single page inside the KB. Path is relative to KB_ROOT. Rejects path traversal.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "path" => %{
            "type" => "string",
            "description" =>
              "Page path relative to KB_ROOT (e.g. 'kb/wiki/sources/docs--README.md')."
          }
        },
        "required" => ["path"]
      }
    },
    %{
      "name" => "kb_lint",
      "description" => "Run the KB health scorecard (orphans, staleness, broken links, ...) and return the report.",
      "inputSchema" => %{"type" => "object", "properties" => %{}}
    },
    %{
      "name" => "kb_ingest",
      "description" =>
        "Ingest a file, directory, or URL into the KB. Path is validated against KB_ROOT for local sources. URLs are delegated to the Claude Code skill.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "path" => %{
            "type" => "string",
            "description" => "Path to a file or directory under KB_ROOT, or a URL starting with http(s)://"
          }
        },
        "required" => ["path"]
      }
    },
    %{
      "name" => "kb_compile",
      "description" =>
        "(Re)compile the wiki from raw sources. Pass dry_run=true to preview without writing.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "dry_run" => %{
            "type" => "boolean",
            "description" => "If true, report staleness counts without writing. Default false.",
            "default" => false
          }
        }
      }
    },
    %{
      "name" => "kb_export",
      "description" =>
        "Render the wiki in a chosen format. Supported: slides (Marp), diagram (Mermaid), graph (Mermaid concept graph), summary. Returns the written artifact path.",
      "inputSchema" => %{
        "type" => "object",
        "properties" => %{
          "format" => %{
            "type" => "string",
            "enum" => ["slides", "diagram", "graph", "summary"],
            "description" => "Which export format to render."
          }
        },
        "required" => ["format"]
      }
    },
    %{
      "name" => "kb_dashboard",
      "description" =>
        "Return a compact dashboard of KB contents: source count, concept count, generated ratio, last compiled timestamp.",
      "inputSchema" => %{"type" => "object", "properties" => %{}}
    }
  ]

  @doc "Return the list of tool definitions for `tools/list`."
  def list, do: @tools

  @doc "Return true if the given name is a known tool."
  def known?(name), do: Enum.any?(@tools, &(&1["name"] == name))

  @doc """
  Dispatch a `tools/call` request.

  Returns `{:ok, text}`, `{:error, message}`, or `{:unknown_tool, name}`.
  """
  def call(name, args) do
    if known?(name) do
      do_call(name, args || %{})
    else
      {:unknown_tool, name}
    end
  rescue
    e -> {:error, "#{name} failed: #{Exception.message(e)}"}
  end

  # ─── Handlers ───────────────────────────────────────────────────────────

  defp do_call("kb_query", %{"question" => question} = args) when is_binary(question) do
    max_pages = Map.get(args, "max_pages", 10) |> to_int(10)
    root = MCP.kb_root()

    wiki_sources = Path.wildcard(Path.join(root, "kb/wiki/sources/*.md"))
    wiki_concepts = Path.wildcard(Path.join(root, "kb/wiki/concepts/*.md"))

    needle = question |> String.trim() |> String.downcase()

    if needle == "" do
      {:error, "question must not be empty"}
    else
      matches =
        (wiki_concepts ++ wiki_sources)
        |> Enum.map(fn path ->
          case File.read(path) do
            {:ok, content} ->
              if String.contains?(String.downcase(content), needle),
                do: {path, snippet(content, needle)},
                else: nil

            _ ->
              nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.take(max_pages)

      if matches == [] do
        {:ok, "No matches found for #{inspect(question)}. KB may be empty or unindexed."}
      else
        body =
          matches
          |> Enum.map_join("\n\n", fn {path, snip} ->
            rel = Path.relative_to(path, root)
            "- #{rel}\n  #{snip}"
          end)

        {:ok,
         "# kb_query: #{question}\n\n#{length(matches)} matching pages (CLI keyword search; full LLM synthesis requires the Claude Code skill).\n\n#{body}"}
      end
    end
  end

  defp do_call("kb_query", _), do: {:error, "question is required"}

  defp do_call("kb_search", %{"term" => term} = args) when is_binary(term) do
    include_raw = Map.get(args, "include_raw", false) == true
    root = MCP.kb_root()

    dirs =
      if include_raw,
        do: ["kb/wiki", "kb/raw"],
        else: ["kb/wiki"]

    needle = String.downcase(term)

    matches =
      dirs
      |> Enum.flat_map(fn dir ->
        Path.join(root, dir <> "/**/*.md") |> Path.wildcard()
      end)
      |> Enum.flat_map(fn file ->
        case File.read(file) do
          {:ok, content} -> grep_lines(file, content, needle, root)
          _ -> []
        end
      end)
      |> Enum.take(200)

    if matches == [] do
      {:ok, "No matches for #{inspect(term)}."}
    else
      {:ok, "# kb_search: #{term}\n\n" <> Enum.join(matches, "\n")}
    end
  end

  defp do_call("kb_search", _), do: {:error, "term is required"}

  defp do_call("kb_list_sources", args) do
    root = MCP.kb_root()
    manifest_path = Path.join(root, "kb/.kb-manifest.json")

    case File.read(manifest_path) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, manifest} ->
            project_filter = Map.get(args, "project")

            if is_binary(project_filter) and Map.get(manifest, "name") != project_filter do
              {:ok, "No sources for project #{inspect(project_filter)} (manifest name is #{inspect(manifest["name"])})."}
            else
              sources = Map.get(manifest, "sources", [])
              payload = Jason.encode!(%{"project" => manifest["name"], "count" => length(sources), "sources" => sources}, pretty: true)
              {:ok, payload}
            end

          {:error, e} ->
            {:error, "manifest parse error: #{inspect(e)}"}
        end

      {:error, :enoent} ->
        {:error, "no KB found at #{root} — run `kb init` first"}

      {:error, reason} ->
        {:error, "manifest read error: #{inspect(reason)}"}
    end
  end

  defp do_call("kb_read_page", %{"path" => path}) when is_binary(path) do
    with {:ok, abs} <- MCP.safe_path(path),
         {:ok, content} <- File.read(abs) do
      # Cap response at 200 KB to keep MCP responses sane.
      capped =
        if byte_size(content) > 200 * 1024 do
          String.slice(content, 0, 200 * 1024) <>
            "\n\n…(truncated at 200 KB; full file is #{byte_size(content)} bytes)"
        else
          content
        end

      {:ok, capped}
    else
      {:error, :enoent} -> {:error, "file not found: #{path}"}
      {:error, :eisdir} -> {:error, "path is a directory: #{path}"}
      {:error, reason} when is_binary(reason) -> {:error, reason}
      {:error, reason} -> {:error, "read error: #{inspect(reason)}"}
    end
  end

  defp do_call("kb_read_page", _), do: {:error, "path is required"}

  defp do_call("kb_lint", _args) do
    case in_kb_root(fn -> capture(fn -> Kb.Lint.run() end) end) do
      {:ok, output} -> {:ok, output}
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_call("kb_ingest", %{"path" => path}) when is_binary(path) do
    cond do
      String.starts_with?(path, "http://") or String.starts_with?(path, "https://") ->
        # TODO(mcp): URL ingest is not implemented in the CLI yet — delegate
        # to the Claude Code skill. The underlying Kb.Ingest.ingest_url/1 is a
        # stub that currently prints a TODO.
        {:ok, "URL ingest is not implemented in the CLI. Use the Claude Code skill for URL sources."}

      true ->
        with {:ok, abs} <- MCP.safe_path(path) do
          case in_kb_root(fn -> capture(fn -> Kb.Ingest.run(abs) end) end) do
            {:ok, output} -> {:ok, output}
            {:error, reason} -> {:error, reason}
          end
        end
    end
  end

  defp do_call("kb_ingest", _), do: {:error, "path is required"}

  defp do_call("kb_compile", args) do
    dry_run = Map.get(args, "dry_run", false) == true

    if dry_run do
      # TODO(mcp): Kb.Compile.run/0 currently has no dry_run flag. For now
      # we surface a staleness summary from the manifest without writing.
      root = MCP.kb_root()
      manifest_path = Path.join(root, "kb/.kb-manifest.json")

      case File.read(manifest_path) do
        {:ok, json} ->
          case Jason.decode(json) do
            {:ok, manifest} ->
              sources = Map.get(manifest, "sources", [])

              {:ok,
               "dry_run: would compile #{length(sources)} sources from #{root}. Full compile requires `dry_run: false`."}

            {:error, e} ->
              {:error, "manifest parse error: #{inspect(e)}"}
          end

        {:error, :enoent} ->
          {:error, "no KB found at #{root} — run `kb init` first"}
      end
    else
      case in_kb_root(fn -> capture(fn -> Kb.Compile.run() end) end) do
        {:ok, output} -> {:ok, output}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp do_call("kb_export", %{"format" => format}) when is_binary(format) do
    if format in ["slides", "diagram", "graph", "summary"] do
      case in_kb_root(fn -> capture(fn -> Kb.Output.run(format) end) end) do
        {:ok, output} -> {:ok, output}
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, "unknown format: #{format} (expected: slides|diagram|graph|summary)"}
    end
  end

  defp do_call("kb_export", _), do: {:error, "format is required"}

  defp do_call("kb_dashboard", _args) do
    root = MCP.kb_root()
    manifest_path = Path.join(root, "kb/.kb-manifest.json")

    case File.read(manifest_path) do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, manifest} ->
            sources = Map.get(manifest, "sources", [])
            total = length(sources)
            generated = Enum.count(sources, &(&1["generated"] == true))
            concepts = Path.wildcard(Path.join(root, "kb/wiki/concepts/*.md")) |> length()

            payload =
              %{
                "project" => Map.get(manifest, "name"),
                "last_compiled" => Map.get(manifest, "last_compiled"),
                "sources" => total,
                "generated_sources" => generated,
                "generated_ratio" =>
                  if(total > 0, do: Float.round(generated / (total * 1.0), 2), else: 0.0),
                "concepts" => concepts
              }
              |> Jason.encode!(pretty: true)

            {:ok, payload}

          {:error, e} ->
            {:error, "manifest parse error: #{inspect(e)}"}
        end

      {:error, :enoent} ->
        {:error, "no KB found at #{root} — run `kb init` first"}
    end
  end

  # Fallback (shouldn't be reachable because of known?/1)
  defp do_call(name, _), do: {:unknown_tool, name}

  # ─── Support ────────────────────────────────────────────────────────────

  defp to_int(n, _default) when is_integer(n), do: n

  defp to_int(s, default) when is_binary(s) do
    case Integer.parse(s) do
      {i, _} -> i
      :error -> default
    end
  end

  defp to_int(_, default), do: default

  defp snippet(content, needle) do
    down = String.downcase(content)

    case :binary.match(down, needle) do
      {pos, len} ->
        start = max(pos - 60, 0)
        stop = min(pos + len + 60, byte_size(content))
        chunk = binary_part(content, start, stop - start)
        chunk |> String.replace(~r/\s+/, " ") |> String.trim()

      :nomatch ->
        content |> String.slice(0, 120) |> String.replace(~r/\s+/, " ")
    end
  end

  defp grep_lines(file, content, needle, root) do
    rel = Path.relative_to(file, root)

    content
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line, lineno} ->
      if String.contains?(String.downcase(line), needle) do
        ["#{rel}:#{lineno}: #{String.trim(line)}"]
      else
        []
      end
    end)
  end

  @doc false
  # Run `fun` with :stdio redirected into a StringIO device, returning the
  # captured text. Errors propagate.
  def capture(fun) when is_function(fun, 0) do
    {:ok, device} = StringIO.open("")
    original_group_leader = Process.group_leader()
    Process.group_leader(self(), device)

    try do
      fun.()
    after
      Process.group_leader(self(), original_group_leader)
    end

    {:ok, {_in, out}} = StringIO.close(device)
    out
  end

  # Run `fun` with the current process's cwd set to KB_ROOT for the duration
  # of the call. The existing `Kb.*` modules use relative paths like
  # `kb/raw/...`, so we pin cwd rather than refactoring them.
  #
  # Refuses with a structured error if no KB was discovered — prevents silent
  # operation on the wrong directory when Claude Code's workspace has no KB.
  defp in_kb_root(fun) do
    case MCP.kb_root_with_status() do
      {_root, :not_found} ->
        {:error,
         "no KB found (looked up from cwd for kb/.kb-manifest.json). " <>
           "Run `kb init` in the workspace, or set KB_ROOT to a valid KB directory."}

      {root, :found} ->
        case File.cd(root) do
          :ok ->
            try do
              {:ok, fun.()}
            rescue
              e -> {:error, "error: #{Exception.message(e)}"}
            end

          {:error, reason} ->
            {:error, "could not cd to #{root}: #{inspect(reason)}"}
        end
    end
  end
end
