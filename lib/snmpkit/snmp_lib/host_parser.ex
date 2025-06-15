defmodule SnmpKit.SnmpLib.HostParser do
  @moduledoc """
  Comprehensive host and port parsing for all possible input formats.

  This module handles parsing of host and port information from any conceivable
  input format and returns exactly what gen_udp needs: an IP tuple and integer port.

  ## Supported Input Formats

  ### IPv4
  - Tuples: `{192, 168, 1, 1}`, `{{192, 168, 1, 1}, 161}`
  - Strings: `"192.168.1.1"`, `"192.168.1.1:161"`
  - Charlists: `'192.168.1.1'`, `'192.168.1.1:161'`
  - Hostnames: `"router.local"`, `"router.local:161"`

  ### IPv6
  - Tuples: `{0x2001, 0xdb8, 0, 0, 0, 0, 0, 1}`, `{{0x2001, 0xdb8, 0, 0, 0, 0, 0, 1}, 161}`
  - Strings: `"2001:db8::1"`, `"[2001:db8::1]:161"`
  - Charlists: `'2001:db8::1'`, `'[2001:db8::1]:161'`
  - Compressed: `"::1"`, `"[::1]:161"`

  ### Mixed Formats
  - Maps: `%{host: "192.168.1.1", port: 161}`
  - Keyword lists: `[host: "192.168.1.1", port: 161]`

  ## Returns

  `{:ok, {ip_tuple, port}}` where:
  - `ip_tuple` is a 4-tuple for IPv4 or 8-tuple for IPv6
  - `port` is an integer between 1-65535

  `{:error, reason}` for invalid input
  """

  require Logger

  @type ip4_tuple :: {0..255, 0..255, 0..255, 0..255}
  @type ip6_tuple ::
          {0..65535, 0..65535, 0..65535, 0..65535, 0..65535, 0..65535, 0..65535, 0..65535}
  @type ip_tuple :: ip4_tuple() | ip6_tuple()
  @type port_number :: 1..65535
  @type parse_result :: {:ok, {ip_tuple(), port_number()}} | {:error, atom()}

  @default_port 161

  @doc """
  Parse host and port from any input format.

  ## Examples

      # IPv4 tuples
      iex> SnmpKit.SnmpLib.HostParser.parse({192, 168, 1, 1})
      {:ok, {{192, 168, 1, 1}, 161}}

      iex> SnmpKit.SnmpLib.HostParser.parse({{192, 168, 1, 1}, 8161})
      {:ok, {{192, 168, 1, 1}, 8161}}

      # IPv4 strings
      iex> SnmpKit.SnmpLib.HostParser.parse("192.168.1.1")
      {:ok, {{192, 168, 1, 1}, 161}}

      iex> SnmpKit.SnmpLib.HostParser.parse("192.168.1.1:8161")
      {:ok, {{192, 168, 1, 1}, 8161}}

      # IPv4 charlists
      iex> SnmpKit.SnmpLib.HostParser.parse('192.168.1.1')
      {:ok, {{192, 168, 1, 1}, 161}}

      iex> SnmpKit.SnmpLib.HostParser.parse('192.168.1.1:8161')
      {:ok, {{192, 168, 1, 1}, 8161}}

      # IPv6 strings
      iex> SnmpKit.SnmpLib.HostParser.parse("::1")
      {:ok, {{0, 0, 0, 0, 0, 0, 0, 1}, 161}}

      iex> SnmpKit.SnmpLib.HostParser.parse("[::1]:8161")
      {:ok, {{0, 0, 0, 0, 0, 0, 0, 1}, 8161}}

      # Error cases
      iex> SnmpKit.SnmpLib.HostParser.parse("invalid")
      {:error, :invalid_host}

      iex> SnmpKit.SnmpLib.HostParser.parse("192.168.1.1:99999")
      {:error, :invalid_port}
  """
  @spec parse(any()) :: parse_result()
  def parse(input, default_port \\ @default_port)

  # IPv4/IPv6 tuple without port
  def parse({a, b, c, d} = ip_tuple, default_port)
      when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) do
    case validate_ipv4_tuple(ip_tuple) do
      :ok -> {:ok, {ip_tuple, default_port}}
      error -> error
    end
  end

  # IPv6 tuple without port
  def parse({a, b, c, d, e, f, g, h} = ip_tuple, default_port)
      when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) and
             is_integer(e) and is_integer(f) and is_integer(g) and is_integer(h) do
    case validate_ipv6_tuple(ip_tuple) do
      :ok -> {:ok, {ip_tuple, default_port}}
      error -> error
    end
  end

  # Tuple with port: {ip_tuple, port}
  def parse({{a, b, c, d} = ip_tuple, port}, _default_port)
      when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) and
             is_integer(port) do
    with :ok <- validate_ipv4_tuple(ip_tuple),
         :ok <- validate_port(port) do
      {:ok, {ip_tuple, port}}
    end
  end

  # IPv6 tuple with port: {{ip6_tuple}, port}
  def parse({{a, b, c, d, e, f, g, h} = ip_tuple, port}, _default_port)
      when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) and
             is_integer(e) and is_integer(f) and is_integer(g) and is_integer(h) and
             is_integer(port) do
    with :ok <- validate_ipv6_tuple(ip_tuple),
         :ok <- validate_port(port) do
      {:ok, {ip_tuple, port}}
    end
  end

  # String input
  def parse(input, default_port) when is_binary(input) do
    parse_string(input, default_port)
  end

  # Charlist input
  def parse(input, default_port) when is_list(input) do
    # Validate charlist contains only valid ASCII/UTF-8 characters
    if valid_charlist?(input) do
      try do
        string_input = List.to_string(input)
        parse_string(string_input, default_port)
      rescue
        # Not a valid charlist
        _ -> {:error, :invalid_charlist}
      end
    else
      {:error, :invalid_charlist}
    end
  end

  # Map input: %{host: ..., port: ...}
  def parse(%{host: host} = map, default_port) do
    port = Map.get(map, :port, default_port)

    with {:ok, {ip_tuple, _}} <- parse(host, default_port),
         :ok <- validate_port(port) do
      {:ok, {ip_tuple, port}}
    end
  end

  # Keyword list input: [host: ..., port: ...]
  def parse(input, default_port) when is_list(input) and length(input) > 0 do
    case Keyword.keyword?(input) do
      true ->
        host = Keyword.get(input, :host)
        port = Keyword.get(input, :port, default_port)

        if host do
          with {:ok, {ip_tuple, _}} <- parse(host, default_port),
               :ok <- validate_port(port) do
            {:ok, {ip_tuple, port}}
          end
        else
          {:error, :missing_host}
        end

      false ->
        # Try as charlist
        parse_charlist(input, default_port)
    end
  end

  # Atom input (for hostnames like :localhost)
  def parse(input, default_port) when is_atom(input) do
    parse_string(Atom.to_string(input), default_port)
  end

  # Invalid input
  def parse(_input, _default_port) do
    {:error, :unsupported_format}
  end

  # Private helper functions

  defp parse_string(input, default_port) do
    input = String.trim(input)

    cond do
      # IPv6 with port: [::1]:8161
      String.starts_with?(input, "[") and String.contains?(input, "]:") ->
        parse_ipv6_with_port(input)

      # IPv4 with port: 192.168.1.1:8161
      String.contains?(input, ":") and not String.contains?(input, "::") ->
        parse_ipv4_with_port(input, default_port)

      # IPv6 without port or IPv4 without port
      true ->
        parse_ip_without_port(input, default_port)
    end
  end

  defp parse_charlist(input, default_port) do
    try do
      string_input = List.to_string(input)
      parse_string(string_input, default_port)
    rescue
      _ -> {:error, :invalid_charlist}
    end
  end

  defp parse_ipv6_with_port(input) do
    # Format: [2001:db8::1]:8161
    case Regex.run(~r/^\[([^\]]+)\]:(\d+)$/, input) do
      [_full, ipv6_str, port_str] ->
        with {:ok, ip_tuple} <- parse_ipv6_address(ipv6_str),
             {port, ""} <- Integer.parse(port_str),
             :ok <- validate_port(port) do
          {:ok, {ip_tuple, port}}
        else
          _ -> {:error, :invalid_ipv6_with_port}
        end

      nil ->
        {:error, :invalid_ipv6_with_port}
    end
  end

  defp parse_ipv4_with_port(input, default_port) do
    # Handle multiple colons (might be IPv6)
    parts = String.split(input, ":")

    cond do
      length(parts) == 2 ->
        # Likely IPv4:port
        [host_part, port_part] = parts

        case Integer.parse(port_part) do
          {port, ""} ->
            with {:ok, ip_tuple} <- parse_ipv4_address(host_part),
                 :ok <- validate_port(port) do
              {:ok, {ip_tuple, port}}
            end

          _ ->
            # Port part is not a number, might be IPv6
            parse_ip_without_port(input, default_port)
        end

      length(parts) > 2 ->
        # Definitely IPv6
        parse_ip_without_port(input, default_port)

      true ->
        {:error, :invalid_format}
    end
  end

  defp parse_ip_without_port(input, default_port) do
    cond do
      # Try IPv4 first
      String.contains?(input, ".") ->
        case parse_ipv4_address(input) do
          {:ok, ip_tuple} -> {:ok, {ip_tuple, default_port}}
          error -> error
        end

      # Try IPv6
      String.contains?(input, ":") ->
        case parse_ipv6_address(input) do
          {:ok, ip_tuple} -> {:ok, {ip_tuple, default_port}}
          error -> error
        end

      # Try hostname resolution
      true ->
        case resolve_hostname(input) do
          {:ok, ip_tuple} -> {:ok, {ip_tuple, default_port}}
          error -> error
        end
    end
  end

  defp parse_ipv4_address(input) do
    charlist_input = String.to_charlist(input)

    case :inet.parse_address(charlist_input) do
      {:ok, ip_tuple} ->
        case validate_ipv4_tuple(ip_tuple) do
          :ok -> {:ok, ip_tuple}
          error -> error
        end

      {:error, _} ->
        {:error, :invalid_ipv4}
    end
  end

  defp parse_ipv6_address(input) do
    charlist_input = String.to_charlist(input)

    case :inet.parse_address(charlist_input) do
      {:ok, ip_tuple} ->
        case validate_ipv6_tuple(ip_tuple) do
          :ok -> {:ok, ip_tuple}
          error -> error
        end

      {:error, _} ->
        {:error, :invalid_ipv6}
    end
  end

  defp resolve_hostname(hostname) do
    charlist_hostname = String.to_charlist(hostname)

    case :inet.gethostbyname(charlist_hostname) do
      {:ok, {:hostent, _name, _aliases, :inet, 4, [ip_tuple | _]}} ->
        {:ok, ip_tuple}

      {:ok, {:hostent, _name, _aliases, :inet6, 16, [ip_tuple | _]}} ->
        {:ok, ip_tuple}

      {:error, _reason} ->
        {:error, :hostname_resolution_failed}
    end
  end

  defp validate_ipv4_tuple({a, b, c, d})
       when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) and
              a >= 0 and a <= 255 and b >= 0 and b <= 255 and
              c >= 0 and c <= 255 and d >= 0 and d <= 255 do
    :ok
  end

  defp validate_ipv4_tuple(_), do: {:error, :invalid_ipv4_tuple}

  defp validate_ipv6_tuple({a, b, c, d, e, f, g, h})
       when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d) and
              is_integer(e) and is_integer(f) and is_integer(g) and is_integer(h) and
              a >= 0 and a <= 65535 and b >= 0 and b <= 65535 and
              c >= 0 and c <= 65535 and d >= 0 and d <= 65535 and
              e >= 0 and e <= 65535 and f >= 0 and f <= 65535 and
              g >= 0 and g <= 65535 and h >= 0 and h <= 65535 do
    :ok
  end

  defp validate_ipv6_tuple(_), do: {:error, :invalid_ipv6_tuple}

  defp validate_port(port) when is_integer(port) and port >= 1 and port <= 65535, do: :ok
  defp validate_port(_), do: {:error, :invalid_port}

  # Validate that a charlist contains only valid characters (0-255 for bytes, but more restrictively for reasonable text)
  defp valid_charlist?(charlist) do
    Enum.all?(charlist, fn char ->
      is_integer(char) and char >= 0 and char <= 255
    end) and
    # Additional check: ensure it would create valid UTF-8 when converted to string
    try do
      _string = List.to_string(charlist)
      true
    rescue
      _ -> false
    end
  end

  @doc """
  Quick validation function to check if input can be parsed.

  ## Examples

      iex> SnmpKit.SnmpLib.HostParser.valid?("192.168.1.1")
      true

      iex> SnmpKit.SnmpLib.HostParser.valid?("invalid")
      false
  """
  @spec valid?(any()) :: boolean()
  def valid?(input) do
    case parse(input) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Parse and return only the IP tuple, using default port.

  ## Examples

      iex> SnmpKit.SnmpLib.HostParser.parse_ip("192.168.1.1")
      {:ok, {192, 168, 1, 1}}
  """
  @spec parse_ip(any()) :: {:ok, ip_tuple()} | {:error, atom()}
  def parse_ip(input) do
    case parse(input) do
      {:ok, {ip_tuple, _port}} -> {:ok, ip_tuple}
      error -> error
    end
  end

  @doc """
  Parse and return only the port, using 161 as default.

  ## Examples

      iex> SnmpKit.SnmpLib.HostParser.parse_port("192.168.1.1:8161")
      {:ok, 8161}

      iex> SnmpKit.SnmpLib.HostParser.parse_port("192.168.1.1")
      {:ok, 161}
  """
  @spec parse_port(any()) :: {:ok, port_number()} | {:error, atom()}
  def parse_port(input) do
    case parse(input) do
      {:ok, {_ip_tuple, port}} -> {:ok, port}
      error -> error
    end
  end

  @doc """
  Format an IP tuple and port back to string representation.

  ## Examples

      iex> SnmpKit.SnmpLib.HostParser.format({{192, 168, 1, 1}, 161})
      "192.168.1.1:161"

      iex> SnmpKit.SnmpLib.HostParser.format({{0, 0, 0, 0, 0, 0, 0, 1}, 161})
      "[::1]:161"
  """
  @spec format({ip_tuple(), port_number()}) :: String.t()
  def format({{a, b, c, d}, port}) do
    "#{a}.#{b}.#{c}.#{d}:#{port}"
  end

  def format({{a, b, c, d, e, f, g, h}, port}) do
    ip_str = :inet.ntoa({a, b, c, d, e, f, g, h}) |> List.to_string()
    "[#{ip_str}]:#{port}"
  end
end
