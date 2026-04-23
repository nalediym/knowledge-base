defmodule Kb.Output.AiTest do
  use ExUnit.Case, async: false

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    wiki_dir = Path.join(tmp_dir, "wiki")
    output_dir = Path.join(tmp_dir, "output")
    File.mkdir_p!(Path.join(wiki_dir, "concepts"))
    File.mkdir_p!(Path.join(wiki_dir, "sources"))
    File.mkdir_p!(output_dir)

    File.write!(Path.join(wiki_dir, "index.md"), """
    # Fixture KB

    ## Summary
    Three-page fixture KB for AI-consumable export tests.

    ## Sources
    - [auth](sources/auth.md)
    """)

    File.write!(Path.join(wiki_dir, "concepts/jwt.md"), """
    # JWT Authentication

    ## Summary
    Stateless authentication using JSON Web Tokens.

    ## Details
    JWTs are signed. See [auth](../sources/auth.md).

    ```elixir
    :jwt
    ```

    <!-- comment -->
    """)

    File.write!(Path.join(wiki_dir, "sources/auth.md"), """
    # Auth Design

    ## Summary
    Design document for JWT auth.

    ## Chunks
    ### c-aaaa: Overview
    > We use JWT tokens.

    ### c-bbbb: Flow
    > User logs in.
    """)

    {:ok, wiki_dir: wiki_dir, output_dir: output_dir}
  end

  describe "llms-txt" do
    test "writes an llms.txt with one entry per page (minus index)", %{
      wiki_dir: wiki_dir,
      output_dir: output_dir
    } do
      assert {:ok, path} =
               Kb.Output.Ai.run("llms-txt",
                 wiki_dir: wiki_dir,
                 output_dir: output_dir
               )

      assert File.exists?(path)
      content = File.read!(path)

      # llmstxt.org: H1 title + blockquote summary + H2 section(s)
      assert content =~ ~r/^# Fixture KB/
      assert content =~ ~r/^> /m
      assert content =~ "## Concepts"
      assert content =~ "## Sources"
      # Both non-index pages appear
      assert content =~ "[JWT Authentication](concepts/jwt.md)"
      assert content =~ "[Auth Design](sources/auth.md)"
    end
  end

  describe "llms-full" do
    test "writes llms-full.txt with all pages flattened", %{
      wiki_dir: wiki_dir,
      output_dir: output_dir
    } do
      assert {:ok, path} =
               Kb.Output.Ai.run("llms-full",
                 wiki_dir: wiki_dir,
                 output_dir: output_dir
               )

      content = File.read!(path)
      assert content =~ "JWT Authentication"
      assert content =~ "Auth Design"
      # HTML comments stripped
      refute content =~ "<!-- comment -->"
      # Under cap => no truncation marker
      refute content =~ "llms-full truncated"
    end
  end

  describe "jsonld" do
    test "emits a valid schema.org JSON-LD graph", %{
      wiki_dir: wiki_dir,
      output_dir: output_dir
    } do
      assert {:ok, path} =
               Kb.Output.Ai.run("jsonld",
                 wiki_dir: wiki_dir,
                 output_dir: output_dir
               )

      {:ok, parsed} = Jason.decode(File.read!(path))
      assert parsed["@context"] == "https://schema.org"
      assert is_list(parsed["@graph"])
      assert length(parsed["@graph"]) == 3

      concept = Enum.find(parsed["@graph"], &(&1["name"] == "JWT Authentication"))
      assert concept["@type"] == "DefinedTerm"
      assert concept["@id"] =~ "jwt.md"

      source = Enum.find(parsed["@graph"], &(&1["name"] == "Auth Design"))
      assert source["@type"] == "CreativeWork"

      # Concept links to source → isRelatedTo populated
      assert is_list(concept["isRelatedTo"])
      assert Enum.any?(concept["isRelatedTo"], &String.contains?(&1["@id"], "auth.md"))
    end
  end

  describe "sitemap" do
    test "emits a well-formed sitemap.xml with <loc> and <lastmod>", %{
      wiki_dir: wiki_dir,
      output_dir: output_dir
    } do
      assert {:ok, path} =
               Kb.Output.Ai.run("sitemap",
                 wiki_dir: wiki_dir,
                 output_dir: output_dir
               )

      xml = File.read!(path)
      assert xml =~ ~r/<\?xml version="1\.0" encoding="UTF-8"\?>/
      assert xml =~ "<urlset xmlns=\"http://www.sitemaps.org/schemas/sitemap/0.9\">"

      loc_count = Regex.scan(~r/<loc>/, xml) |> length()
      lastmod_count = Regex.scan(~r/<lastmod>/, xml) |> length()
      assert loc_count == 3
      assert lastmod_count == 3
      assert xml =~ "</urlset>"
    end
  end

  describe "all" do
    test "writes all four artifacts", %{wiki_dir: wiki_dir, output_dir: output_dir} do
      Kb.Output.Ai.run("all", wiki_dir: wiki_dir, output_dir: output_dir)

      for file <- ["llms.txt", "llms-full.txt", "graph.jsonld", "sitemap.xml"] do
        assert File.exists?(Path.join(output_dir, file)), "missing #{file}"
      end
    end
  end

  describe "siblings" do
    test "emits .txt and .json next to each .md", %{wiki_dir: wiki_dir} do
      written = Kb.Output.Ai.write_siblings(wiki_dir: wiki_dir)

      for md <- Path.wildcard(Path.join(wiki_dir, "**/*.md")) do
        txt = Path.rootname(md) <> ".txt"
        json = Path.rootname(md) <> ".json"
        assert File.exists?(txt), "missing #{txt}"
        assert File.exists?(json), "missing #{json}"
        assert txt in written
        assert json in written
      end

      json_path = Path.join(wiki_dir, "concepts/jwt.json")
      {:ok, parsed} = Jason.decode(File.read!(json_path))
      assert parsed["title"] == "JWT Authentication"
      assert parsed["path"] == "concepts/jwt.md"
      assert is_list(parsed["chunks"])
      assert is_binary(parsed["body"])
      assert Map.has_key?(parsed, "frontmatter")

      txt = File.read!(Path.join(wiki_dir, "concepts/jwt.txt"))
      # Markdown stripped to plain text
      refute txt =~ "<!--"
      refute txt =~ "```"
      assert txt =~ "Stateless authentication"
    end
  end

  describe "llms-full cap" do
    test "truncates with a note when size exceeds cap", %{wiki_dir: wiki_dir} do
      # Craft oversized content by passing a small cap via a helper:
      # we test the cap indirectly by injecting a huge page and checking marker.
      big_path = Path.join(wiki_dir, "big.md")
      File.write!(big_path, "# Big\n\n" <> String.duplicate("lorem ipsum ", 600_000))

      output_dir = Path.join([wiki_dir, "..", "output-big"])
      File.mkdir_p!(output_dir)

      {:ok, path} =
        Kb.Output.Ai.run("llms-full", wiki_dir: wiki_dir, output_dir: output_dir)

      content = File.read!(path)
      # 600_000 * 12 ≈ 7.2 MB > 5 MB cap
      assert byte_size(content) <= 5 * 1024 * 1024 + 200
      assert content =~ "llms-full truncated"
    end
  end
end
