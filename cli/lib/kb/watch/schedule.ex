defmodule Kb.Watch.Schedule do
  @moduledoc """
  OS-specific scheduled-sync scaffold generator.

  Emits:

    * `macos`   → `launchd.plist`      (LaunchAgent)
    * `linux`   → a combined `systemd` unit + timer (printed side-by-side)
    * `windows` → a Windows Task Scheduler `task.xml` + `schtasks` command

  Cadence and run-time come from `kb.config.json` → `schedule` block, or
  defaults (daily at 04:30). Output goes to stdout unless `--output` is
  passed.
  """

  @label "com.nalediym.kb"

  def run(args) do
    platform = arg(args, "--platform") || detect_platform()
    output = arg(args, "--output")
    config = read_config()

    content =
      case platform do
        "macos" -> macos_plist(config)
        "linux" -> linux_units(config)
        "windows" -> windows_task(config)
        other -> raise "unsupported platform: #{other}"
      end

    if output do
      File.mkdir_p!(Path.dirname(output))
      File.write!(output, content)
      IO.puts("wrote #{platform} schedule → #{output}")
    else
      IO.puts(content)
    end

    if platform == "windows" do
      IO.puts("\n# To install:")
      IO.puts(~s{schtasks /Create /TN "#{@label}" /XML "#{output || "task.xml"}"})
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Generators
  # ---------------------------------------------------------------------------

  @doc false
  def macos_plist(config) do
    {hour, minute} = parse_time(config)
    kb_bin = config["kb_bin"] || "kb"
    working_dir = config["working_dir"] || System.get_env("HOME") || "."

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
    <plist version="1.0">
    <dict>
      <key>Label</key>
      <string>#{@label}</string>
      <key>ProgramArguments</key>
      <array>
        <string>#{kb_bin}</string>
        <string>ingest</string>
        <string>--sessions</string>
      </array>
      <key>WorkingDirectory</key>
      <string>#{working_dir}</string>
      <key>StartCalendarInterval</key>
      <dict>
        <key>Hour</key>
        <integer>#{hour}</integer>
        <key>Minute</key>
        <integer>#{minute}</integer>
      </dict>
      <key>StandardOutPath</key>
      <string>#{working_dir}/kb.schedule.log</string>
      <key>StandardErrorPath</key>
      <string>#{working_dir}/kb.schedule.err</string>
      <key>RunAtLoad</key>
      <false/>
    </dict>
    </plist>
    """
  end

  @doc false
  def linux_units(config) do
    {hour, minute} = parse_time(config)
    kb_bin = config["kb_bin"] || "kb"
    working_dir = config["working_dir"] || System.get_env("HOME") || "."

    service = """
    # ~/.config/systemd/user/kb.service
    [Unit]
    Description=kb knowledge-base scheduled ingest
    After=network-online.target

    [Service]
    Type=oneshot
    WorkingDirectory=#{working_dir}
    ExecStart=#{kb_bin} ingest --sessions

    [Install]
    WantedBy=default.target
    """

    timer = """
    # ~/.config/systemd/user/kb.timer
    [Unit]
    Description=Run kb ingest daily

    [Timer]
    OnCalendar=*-*-* #{pad(hour)}:#{pad(minute)}:00
    Persistent=true
    Unit=kb.service

    [Install]
    WantedBy=timers.target
    """

    service <> "\n---\n" <> timer
  end

  @doc false
  def windows_task(config) do
    {hour, minute} = parse_time(config)
    kb_bin = config["kb_bin"] || "kb"
    working_dir = config["working_dir"] || System.get_env("USERPROFILE") || "."
    # Task Scheduler prefers ISO-8601 with local time; we use a fixed date marker.
    start = "2026-01-01T#{pad(hour)}:#{pad(minute)}:00"

    """
    <?xml version="1.0" encoding="UTF-16"?>
    <Task version="1.3" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
      <RegistrationInfo>
        <Description>kb knowledge-base scheduled ingest</Description>
      </RegistrationInfo>
      <Triggers>
        <CalendarTrigger>
          <StartBoundary>#{start}</StartBoundary>
          <Enabled>true</Enabled>
          <ScheduleByDay>
            <DaysInterval>1</DaysInterval>
          </ScheduleByDay>
        </CalendarTrigger>
      </Triggers>
      <Principals>
        <Principal id="Author">
          <LogonType>InteractiveToken</LogonType>
          <RunLevel>LeastPrivilege</RunLevel>
        </Principal>
      </Principals>
      <Settings>
        <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
        <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
        <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
        <AllowHardTerminate>true</AllowHardTerminate>
        <StartWhenAvailable>true</StartWhenAvailable>
        <Enabled>true</Enabled>
      </Settings>
      <Actions Context="Author">
        <Exec>
          <Command>#{kb_bin}</Command>
          <Arguments>ingest --sessions</Arguments>
          <WorkingDirectory>#{working_dir}</WorkingDirectory>
        </Exec>
      </Actions>
    </Task>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp read_config do
    case File.read("kb.config.json") do
      {:ok, json} ->
        case Jason.decode(json) do
          {:ok, cfg} -> Map.get(cfg, "schedule", %{})
          _ -> %{}
        end

      _ ->
        %{}
    end
  end

  defp parse_time(config) do
    time = Map.get(config, "time", "04:30")

    case String.split(time, ":") do
      [h, m] -> {to_int(h), to_int(m)}
      _ -> {4, 30}
    end
  end

  defp to_int(s), do: s |> String.trim() |> String.to_integer()

  defp pad(n) when n < 10, do: "0#{n}"
  defp pad(n), do: "#{n}"

  defp arg(args, flag) do
    case Enum.find_index(args, &(&1 == flag)) do
      nil -> nil
      idx -> Enum.at(args, idx + 1)
    end
  end

  defp detect_platform do
    case :os.type() do
      {:unix, :darwin} -> "macos"
      {:unix, _} -> "linux"
      {:win32, _} -> "windows"
      _ -> "linux"
    end
  end
end
