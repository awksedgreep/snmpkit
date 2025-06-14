defmodule SnmpMgr.Target do
  @moduledoc """
  Target parsing and validation for SNMP requests.
  
  Handles parsing of various target formats and resolves hostnames to IP addresses.
  """

  @default_port 161

  @doc """
  Parses a target string into a structured format.

  ## Examples

      iex> SnmpMgr.Target.parse("192.168.1.1:161")
      {:ok, %{host: {192, 168, 1, 1}, port: 161}}

      iex> SnmpMgr.Target.parse("device.local")
      {:ok, %{host: "device.local", port: 161}}

      iex> SnmpMgr.Target.parse("192.168.1.1")
      {:ok, %{host: {192, 168, 1, 1}, port: 161}}
  """
  def parse(target) when is_binary(target) do
    case String.split(target, ":") do
      [host] -> 
        parse_host_and_port(host, @default_port)
      [host, port_str] -> 
        case Integer.parse(port_str) do
          {port, ""} when port > 0 and port <= 65535 ->
            parse_host_and_port(host, port)
          _ ->
            {:error, {:invalid_port, port_str}}
        end
      _ ->
        {:error, {:invalid_target_format, target}}
    end
  end

  def parse(target) when is_tuple(target) and tuple_size(target) == 4 do
    # Already an IP tuple
    {:ok, %{host: target, port: @default_port}}
  end

  def parse(%{host: _host, port: _port} = target) do
    # Already parsed
    {:ok, target}
  end

  def parse(_target) do
    {:error, :invalid_target_format}
  end

  @doc """
  Resolves a hostname to an IP address if needed.
  
  If the host is already an IP tuple, returns it unchanged.
  """
  def resolve_hostname(%{host: host, port: _port} = target) when is_tuple(host) do
    {:ok, target}
  end

  def resolve_hostname(%{host: hostname, port: port}) when is_binary(hostname) do
    case parse_ip_address(hostname) do
      {:ok, ip_tuple} ->
        {:ok, %{host: ip_tuple, port: port}}
      :error ->
        case :inet.gethostbyname(String.to_charlist(hostname)) do
          {:ok, {:hostent, _name, _aliases, :inet, 4, [ip_tuple | _]}} ->
            {:ok, %{host: ip_tuple, port: port}}
          {:error, reason} ->
            {:error, {:hostname_resolution_failed, hostname, reason}}
        end
    end
  end

  @doc """
  Validates that a target is reachable (basic connectivity check).
  """
  def validate_connectivity(%{host: host, port: port}, timeout \\ 5000) do
    case :gen_tcp.connect(host, port, [], timeout) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok
      {:error, :econnrefused} ->
        # This is actually good - the port responded (even if it refused)
        :ok
      {:error, reason} ->
        {:error, {:connectivity_check_failed, reason}}
    end
  end

  # Private functions

  defp parse_host_and_port(host, port) do
    case parse_ip_address(host) do
      {:ok, ip_tuple} ->
        {:ok, %{host: ip_tuple, port: port}}
      :error ->
        # Assume it's a hostname
        {:ok, %{host: host, port: port}}
    end
  end

  defp parse_ip_address(ip_string) do
    case :inet.parse_address(String.to_charlist(ip_string)) do
      {:ok, ip_tuple} -> {:ok, ip_tuple}
      {:error, _} -> :error
    end
  end
end