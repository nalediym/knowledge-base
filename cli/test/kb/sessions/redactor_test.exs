defmodule KB.Sessions.RedactorTest do
  use ExUnit.Case, async: true

  alias KB.Sessions.Redactor

  describe "redact/2" do
    test "strips sk-* API keys" do
      input = "before sk-ABCDEFGHIJKLMNOPQRSTUVWX after"
      assert Redactor.redact(input, username: nil) == "before [REDACTED_API_KEY] after"
    end

    test "strips GitHub ghp_ tokens" do
      input = "token ghp_abcdefghijklmnopqrstuvwxyz0123456789 here"
      assert Redactor.redact(input, username: nil) == "token [REDACTED_GH_TOKEN] here"
    end

    test "strips named credentials" do
      input = ~s(api_key: "abc123def456")
      assert Redactor.redact(input, username: nil) =~ "[REDACTED_CREDENTIAL]"
    end

    test "strips emails" do
      input = "ping alice@example.com about this"
      assert Redactor.redact(input, username: nil) == "ping [REDACTED_EMAIL] about this"
    end

    test "replaces the configured username with USER" do
      input = "/Users/naledi/Projects and user naledi"
      out = Redactor.redact(input, username: "naledi")
      refute out =~ "naledi"
      assert out =~ "USER"
    end

    test "username is only replaced on word boundaries" do
      # Don't clobber substrings — "naledition" shouldn't match.
      input = "naledition continues"
      out = Redactor.redact(input, username: "naledi")
      assert out =~ "naledition"
    end

    test "applies extra_patterns from config" do
      input = "MY-CUSTOM-SECRET-XYZ"
      out = Redactor.redact(input, username: nil, extra_patterns: ["MY-CUSTOM-SECRET-[A-Z]+"])
      assert out == "[REDACTED_CUSTOM]"
    end

    test "is idempotent" do
      input = "sk-ABCDEFGHIJKLMNOPQRSTUVWX and sk-1234567890123456789012"
      once = Redactor.redact(input, username: nil)
      twice = Redactor.redact(once, username: nil)
      assert once == twice
    end
  end
end
