defmodule SnmpKit.SnmpMgr.PortHandlingTest do
  use ExUnit.Case, async: true

  alias SnmpKit.SnmpMgr.Target

  @moduletag :unit

  describe "Port option handling in Core functions" do
    test "hostname without port should preserve user's port option" do
      target = "192.168.1.1"
      user_opts = [port: 8161, community: "public", timeout: 1000]

      # Test the target parsing logic that Core.send_get_request uses
      {host, final_opts} =
        case Target.parse(target) do
          {:ok, %{host: host, port: port}} ->
            # Simulate the logic from Core.send_get_request
            if target_contains_port?(target) do
              opts_with_port = Keyword.put(user_opts, :port, port)
              {host, opts_with_port}
            else
              {host, user_opts}
            end

          {:error, _reason} ->
            {target, user_opts}
        end

      # Verify that user's port option was preserved
      assert Keyword.get(final_opts, :port) == 8161
      assert host == {192, 168, 1, 1}
    end

    test "hostname with embedded port should use embedded port over option" do
      target = "192.168.1.1:9161"
      # Different port
      user_opts = [port: 8161, community: "public", timeout: 1000]

      # Test the target parsing logic
      {host, final_opts} =
        case Target.parse(target) do
          {:ok, %{host: host, port: port}} ->
            if target_contains_port?(target) do
              opts_with_port = Keyword.put(user_opts, :port, port)
              {host, opts_with_port}
            else
              {host, user_opts}
            end

          {:error, _reason} ->
            {target, user_opts}
        end

      # Verify that embedded port took precedence
      assert Keyword.get(final_opts, :port) == 9161
      assert host == {192, 168, 1, 1}
    end

    test "hostname with different port formats" do
      # Test various valid formats that Target.parse can handle
      test_cases = [
        {"device.local", 8161, "hostname without port should preserve option"},
        {"device.local:9161", 8161, "hostname with port should use embedded port"}
      ]

      for {target, user_port, description} <- test_cases do
        user_opts = [port: user_port, community: "public", timeout: 1000]

        {_host, final_opts} =
          case Target.parse(target) do
            {:ok, %{host: host, port: port}} ->
              if target_contains_port?(target) do
                opts_with_port = Keyword.put(user_opts, :port, port)
                {host, opts_with_port}
              else
                {host, user_opts}
              end

            {:error, _reason} ->
              {target, user_opts}
          end

        expected_port =
          if target_contains_port?(target) do
            # Should use the embedded port
            case String.split(target, ":") do
              [_host, port_str] ->
                case Integer.parse(port_str) do
                  {port, ""} -> port
                  _ -> user_port
                end

              _ ->
                user_port
            end
          else
            user_port
          end

        assert Keyword.get(final_opts, :port) == expected_port, description
      end
    end

    test "hostname without port and no port option should use default" do
      target = "device.local"
      # No port option
      user_opts = [community: "public", timeout: 1000]

      # Test with default options merging (simulating what happens in real usage)
      default_opts = [port: 161, version: :v2c, retries: 3]
      merged_opts = Keyword.merge(default_opts, user_opts)

      {host, final_opts} =
        case Target.parse(target) do
          {:ok, %{host: host, port: port}} ->
            if target_contains_port?(target) do
              opts_with_port = Keyword.put(merged_opts, :port, port)
              {host, opts_with_port}
            else
              {host, merged_opts}
            end

          {:error, _reason} ->
            {target, merged_opts}
        end

      # Verify that default port was used
      assert Keyword.get(final_opts, :port) == 161
      assert host == "device.local"
    end
  end

  describe "Target contains port detection" do
    test "target_contains_port? logic validation" do
      # Test cases for different target formats
      test_cases = [
        # IPv4 cases
        {"192.168.1.1", false, "IPv4 without port"},
        {"192.168.1.1:8161", true, "IPv4 with valid port"},
        {"192.168.1.1:99999", false, "IPv4 with invalid port number"},
        {"192.168.1.1:0", false, "IPv4 with zero port"},
        {"192.168.1.1:abc", false, "IPv4 with non-numeric port"},

        # Hostname cases
        {"device.local", false, "hostname without port"},
        {"device.local:8161", true, "hostname with valid port"},
        {"device.local:99999", false, "hostname with invalid port number"},

        # IPv6 cases (limited support in current Target.parse implementation)
        {"::1", false, "IPv6 localhost without port"},
        # Note: Current Target.parse has limited IPv6 support

        # Edge cases
        {"", false, "empty string"},
        {":", false, "single colon"},
        {":::", false, "triple colon"},
        {"host:", false, "hostname with trailing colon"},
        {":8161", false, "port without host"},
        {"host:abc:def", false, "multiple colons with invalid port"}
      ]

      for {target, expected, description} <- test_cases do
        actual = target_contains_port?(target)

        assert actual == expected,
               "#{description}: expected target_contains_port?(#{inspect(target)}) to be #{expected}, got #{actual}"
      end
    end
  end

  describe "Port option precedence rules" do
    test "port precedence follows expected rules" do
      # Rule 1: Target with embedded port > port option > default port
      assert get_effective_port("host:8161", port: 9999) == 8161
      assert get_effective_port("host", port: 9999) == 9999
      assert get_effective_port("host", []) == 161

      # Rule 2: Complex hostname cases work correctly
      assert get_effective_port("device.example.com:8161", port: 9999) == 8161
      assert get_effective_port("device.example.com", port: 9999) == 9999

      # Rule 3: Invalid embedded ports fall back to option or default
      assert get_effective_port("host:99999", port: 8161) == 8161
      assert get_effective_port("host:abc", port: 8161) == 8161
      assert get_effective_port("host:0", port: 8161) == 8161
    end
  end

  # Helper functions to simulate the Core logic

  defp target_contains_port?(target) when is_binary(target) do
    cond do
      # RFC 3986 bracket notation: [IPv6]:port
      String.starts_with?(target, "[") and String.contains?(target, "]:") ->
        case String.split(target, "]:", parts: 2) do
          [_ipv6_part, port_part] ->
            case Integer.parse(port_part) do
              {port, ""} when port > 0 and port <= 65535 -> true
              _ -> false
            end

          _ ->
            false
        end

      # Plain IPv6 addresses (contain :: or multiple colons) - no port embedded
      String.contains?(target, "::") ->
        false

      target |> String.graphemes() |> Enum.count(&(&1 == ":")) > 1 ->
        false

      # IPv4 or simple hostname with port
      String.contains?(target, ":") ->
        case String.split(target, ":", parts: 2) do
          [host_part, port_part] when host_part != "" ->
            case Integer.parse(port_part) do
              {port, ""} when port > 0 and port <= 65535 -> true
              _ -> false
            end

          _ ->
            false
        end

      # No colon at all
      true ->
        false
    end
  end

  defp target_contains_port?(_), do: false

  defp get_effective_port(target, opts) do
    default_port = 161
    user_port = Keyword.get(opts, :port, default_port)

    case Target.parse(target) do
      {:ok, %{host: _host, port: parsed_port}} ->
        if target_contains_port?(target) do
          parsed_port
        else
          user_port
        end

      {:error, _} ->
        user_port
    end
  end
end
