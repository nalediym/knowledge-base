defmodule Kb.Test.HTTPClient do
  @moduledoc """
  Minimal HTTP/1.1 client for tests — avoids bringing in httpc/inets, which
  interact poorly with the escript build + OTP 28 test env.
  """

  def get(url) do
    request("GET", url, nil)
  end

  def post(url, body, content_type \\ "application/json") do
    request("POST", url, body, [{"content-type", content_type}])
  end

  defp request(method, url, body, extra_headers \\ []) do
    %URI{host: host, port: port, path: path, query: query} = URI.parse(url)
    path = path || "/"
    request_target = if query, do: "#{path}?#{query}", else: path

    host = host || "localhost"
    port = port || 80

    headers =
      [{"host", "#{host}:#{port}"}, {"connection", "close"}] ++ extra_headers

    headers =
      if body do
        [{"content-length", Integer.to_string(byte_size(body))} | headers]
      else
        headers
      end

    header_lines =
      Enum.map_join(headers, "", fn {k, v} -> "#{k}: #{v}\r\n" end)

    payload = [
      "#{method} #{request_target} HTTP/1.1\r\n",
      header_lines,
      "\r\n",
      body || ""
    ]

    {:ok, sock} =
      :gen_tcp.connect(String.to_charlist(host), port, [:binary, active: false], 5_000)

    :ok = :gen_tcp.send(sock, payload)
    data = recv_all(sock, "")
    :gen_tcp.close(sock)

    parse(data)
  end

  defp recv_all(sock, acc) do
    case :gen_tcp.recv(sock, 0, 5_000) do
      {:ok, chunk} -> recv_all(sock, acc <> chunk)
      {:error, :closed} -> acc
      {:error, _} -> acc
    end
  end

  defp parse(data) do
    [head, body] =
      case :binary.split(data, "\r\n\r\n", [:global]) do
        [h, b] -> [h, b]
        [h, b | rest] -> [h, Enum.join([b | rest], "\r\n\r\n")]
        [h] -> [h, ""]
      end

    [status_line | header_lines] = String.split(head, "\r\n")

    [_, status_code, _] =
      Regex.run(~r/HTTP\/\d\.\d\s+(\d+)\s*(.*)/, status_line) ||
        [status_line, "0", ""]

    status = String.to_integer(status_code)

    headers =
      Enum.map(header_lines, fn line ->
        case String.split(line, ":", parts: 2) do
          [k, v] -> {String.downcase(String.trim(k)), String.trim(v)}
          _ -> {"", ""}
        end
      end)

    body =
      case List.keyfind(headers, "transfer-encoding", 0) do
        {_, "chunked"} -> dechunk(body)
        _ -> body
      end

    %{status: status, headers: headers, body: body}
  end

  defp dechunk(data), do: dechunk(data, "")

  defp dechunk("", acc), do: acc

  defp dechunk(data, acc) do
    case :binary.split(data, "\r\n") do
      [size_hex, rest] ->
        case Integer.parse(size_hex, 16) do
          {0, _} ->
            acc

          {size, _} ->
            case rest do
              <<chunk::binary-size(size), "\r\n", tail::binary>> ->
                dechunk(tail, acc <> chunk)

              _ ->
                acc
            end

          :error ->
            acc
        end

      _ ->
        acc
    end
  end
end
