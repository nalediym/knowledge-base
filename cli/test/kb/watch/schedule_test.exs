defmodule Kb.Watch.ScheduleTest do
  use ExUnit.Case, async: true

  test "macos_plist is valid XML with LaunchAgent keys" do
    xml = Kb.Watch.Schedule.macos_plist(%{"time" => "04:30"})

    assert String.contains?(xml, ~s{<?xml version="1.0" encoding="UTF-8"?>})
    assert String.contains?(xml, "<!DOCTYPE plist")
    assert String.contains?(xml, "<key>Label</key>")
    assert String.contains?(xml, "<key>StartCalendarInterval</key>")
    assert String.contains?(xml, "<integer>4</integer>")
    assert String.contains?(xml, "<integer>30</integer>")

    # xmerl should parse it without error.
    {:ok, parsed} = parse_xml(xml)
    assert parsed != nil
  end

  test "linux_units emits both service and timer sections" do
    out = Kb.Watch.Schedule.linux_units(%{"time" => "09:15"})
    assert String.contains?(out, "[Service]")
    assert String.contains?(out, "[Timer]")
    assert String.contains?(out, "OnCalendar=*-*-* 09:15:00")
    assert String.contains?(out, "ExecStart=")
  end

  test "windows_task is valid XML with CalendarTrigger" do
    xml = Kb.Watch.Schedule.windows_task(%{"time" => "22:00"})

    assert String.contains?(xml, ~s{<?xml version="1.0" encoding="UTF-16"?>})
    assert String.contains?(xml, "<Task ")
    assert String.contains?(xml, "<CalendarTrigger>")
    assert String.contains?(xml, "<Command>")
    assert String.contains?(xml, "T22:00:00")

    # xmerl doesn't love UTF-16 declarations for string parsing; swap to UTF-8
    # before parsing so we still verify well-formedness.
    utf8 = String.replace(xml, "UTF-16", "UTF-8")
    {:ok, parsed} = parse_xml(utf8)
    assert parsed != nil
  end

  defp parse_xml(xml) do
    try do
      {doc, _rest} = :xmerl_scan.string(String.to_charlist(xml))
      {:ok, doc}
    rescue
      e -> {:error, e}
    catch
      kind, reason -> {:error, {kind, reason}}
    end
  end
end
