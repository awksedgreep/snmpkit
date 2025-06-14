defmodule SnmpMgr.PerformanceTest do
  @moduledoc """
  Temporary performance test to compare Erlang vs pure Elixir PDU encoding.

  This module will be removed after collecting performance data.
  """

  @doc """
  Runs a performance comparison between Erlang and pure Elixir PDU encoding.

  Encodes a simple GET request PDU 10,000 times with both implementations.
  """
  def run_comparison() do
    # Simple test PDU that we know works
    test_pdu = %{
      type: :get_request,
      request_id: 123,
      error_status: 0,
      error_index: 0,
      varbinds: [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :null, :null}]
    }

    community = "public"
    version = :v1
    iterations = 10_000

    IO.puts("Performance Test: Encoding #{iterations} SNMP PDUs")
    IO.puts("PDU: #{inspect(test_pdu)}")
    IO.puts("")

    # Test pure Elixir implementation
    {elixir_time, elixir_results} =
      :timer.tc(fn ->
        run_elixir_encoding_test(test_pdu, community, version, iterations)
      end)

    # Test Erlang implementation (if available)
    {erlang_time, erlang_results} =
      :timer.tc(fn ->
        run_erlang_encoding_test(test_pdu, community, version, iterations)
      end)

    # Display results
    display_results("Pure Elixir", elixir_time, elixir_results, iterations)
    display_results("Erlang SNMP", erlang_time, erlang_results, iterations)

    # Calculate performance comparison
    if erlang_results.successful > 0 and elixir_results.successful > 0 do
      ratio = elixir_time / erlang_time
      IO.puts("")
      IO.puts("Performance Comparison:")

      if ratio < 1.0 do
        IO.puts("✓ Pure Elixir is #{Float.round(1.0 / ratio, 2)}x FASTER than Erlang")
      else
        IO.puts("⚠ Pure Elixir is #{Float.round(ratio, 2)}x slower than Erlang")
      end
    else
      IO.puts("")
      IO.puts("Cannot compare - one implementation failed")
    end

    {elixir_time, erlang_time, elixir_results, erlang_results}
  end

  defp run_elixir_encoding_test(pdu, community, version, iterations) do
    results = %{successful: 0, failed: 0, errors: []}

    Enum.reduce(1..iterations, results, fn _i, acc ->
      try do
        message = SnmpKit.SnmpLib.PDU.build_message(pdu, community, version)

        case SnmpKit.SnmpLib.PDU.encode_message(message) do
          {:ok, _encoded} ->
            %{acc | successful: acc.successful + 1}

          {:error, reason} ->
            %{acc | failed: acc.failed + 1, errors: [reason | acc.errors]}
        end
      rescue
        error ->
          %{acc | failed: acc.failed + 1, errors: [error | acc.errors]}
      end
    end)
  end

  defp run_erlang_encoding_test(pdu, _community, _version, iterations) do
    results = %{successful: 0, failed: 0, errors: []}

    # Check if Erlang SNMP modules are available
    case Code.ensure_loaded(:snmp_pdus) do
      {:module, :snmp_pdus} ->
        # Try to encode using Erlang SNMP
        Enum.reduce(1..iterations, results, fn _i, acc ->
          try do
            # Convert our PDU format to Erlang record format (using enc_pdu directly)
            erlang_pdu = convert_to_simple_erlang_pdu(pdu)

            # Try to encode with Erlang SNMP using enc_pdu (not enc_message)
            case :snmp_pdus.enc_pdu(erlang_pdu) do
              encoded when is_list(encoded) ->
                %{acc | successful: acc.successful + 1}

              {:error, reason} ->
                %{acc | failed: acc.failed + 1, errors: [reason | acc.errors]}

              _other ->
                %{acc | failed: acc.failed + 1, errors: [:unexpected_result | acc.errors]}
            end
          catch
            _type, reason ->
              %{acc | failed: acc.failed + 1, errors: [reason | acc.errors]}
          end
        end)

      {:error, _} ->
        # Erlang SNMP not available
        %{results | failed: iterations, errors: [:snmp_modules_not_available]}
    end
  end

  defp convert_to_simple_erlang_pdu(pdu) do
    # Convert to simple Erlang PDU record format for enc_pdu
    request_id = Map.get(pdu, :request_id, 1)
    # Use atom instead of numeric
    error_status = :noError
    error_index = Map.get(pdu, :error_index, 0)
    varbinds = Map.get(pdu, :varbinds, [])

    # PDU type
    pdu_type =
      case Map.get(pdu, :type) do
        :get_request -> :"get-request"
        :get_next_request -> :"get-next-request"
        :get_response -> :"get-response"
        :set_request -> :"set-request"
        _ -> :"get-request"
      end

    # Convert varbinds - use lists for OIDs
    erlang_varbinds =
      Enum.with_index(varbinds, 0)
      |> Enum.map(fn {{oid, type, value}, index} ->
        erlang_type =
          case type do
            :null -> :NULL
            :integer -> :INTEGER
            :string -> :"OCTET STRING"
            :oid -> :"OBJECT IDENTIFIER"
            _ -> :NULL
          end

        erlang_value =
          case {type, value} do
            {:null, :null} -> :null
            {_, val} -> val
          end

        # Ensure OID is a list
        oid_list =
          case oid do
            oid when is_list(oid) -> oid
            # fallback
            _ -> [1, 3, 6, 1, 2, 1, 1, 1, 0]
          end

        {:varbind, oid_list, erlang_type, erlang_value, index}
      end)

    # Create PDU record
    {:pdu, pdu_type, request_id, error_status, error_index, erlang_varbinds}
  end

  defp display_results(implementation, time_microseconds, results, iterations) do
    time_ms = time_microseconds / 1000
    time_per_op = time_microseconds / iterations

    IO.puts("#{implementation} Results:")
    IO.puts("  Total time: #{Float.round(time_ms, 2)} ms")
    IO.puts("  Time per operation: #{Float.round(time_per_op, 2)} μs")
    IO.puts("  Successful: #{results.successful}/#{iterations}")
    IO.puts("  Failed: #{results.failed}/#{iterations}")

    if results.failed > 0 do
      unique_errors = Enum.uniq(results.errors) |> Enum.take(3)
      IO.puts("  Sample errors: #{inspect(unique_errors)}")
    end

    if results.successful > 0 do
      ops_per_second = 1_000_000 / time_per_op
      IO.puts("  Operations per second: #{Float.round(ops_per_second, 0)}")
    end

    IO.puts("")
  end

  @doc """
  Quick test to verify both implementations work.
  """
  def verify_implementations() do
    # Simple test PDU
    test_pdu = %{
      type: :get_request,
      request_id: 456,
      error_status: 0,
      error_index: 0,
      varbinds: [{[1, 3, 6, 1, 2, 1, 1, 1, 0], :null, :null}]
    }

    community = "public"
    version = :v1

    IO.puts("Verification Test:")
    IO.puts("PDU: #{inspect(test_pdu)}")
    IO.puts("")

    # Test pure Elixir
    IO.puts("Pure Elixir Implementation:")

    try do
      message = SnmpKit.SnmpLib.PDU.build_message(test_pdu, community, version)
      IO.puts("  Message built: #{inspect(message)}")

      case SnmpKit.SnmpLib.PDU.encode_message(message) do
        {:ok, encoded} ->
          IO.puts("  Encoded successfully: #{byte_size(encoded)} bytes")

          IO.puts(
            "  First 20 bytes: #{inspect(binary_part(encoded, 0, min(20, byte_size(encoded))))}"
          )

        {:error, reason} ->
          IO.puts("  Encoding failed: #{inspect(reason)}")
      end
    rescue
      error ->
        IO.puts("  Message build failed: #{inspect(error)}")
    end

    IO.puts("")

    # Test Erlang (if available)
    IO.puts("Erlang SNMP Implementation:")

    case Code.ensure_loaded(:snmp_pdus) do
      {:module, :snmp_pdus} ->
        try do
          erlang_pdu = convert_to_simple_erlang_pdu(test_pdu)

          IO.puts("  Erlang PDU: #{inspect(erlang_pdu)}")

          case :snmp_pdus.enc_pdu(erlang_pdu) do
            encoded when is_list(encoded) ->
              encoded_binary = :erlang.list_to_binary(encoded)
              IO.puts("  Encoded successfully: #{byte_size(encoded_binary)} bytes")

              IO.puts(
                "  First 20 bytes: #{inspect(binary_part(encoded_binary, 0, min(20, byte_size(encoded_binary))))}"
              )

            {:error, reason} ->
              IO.puts("  Encoding failed: #{inspect(reason)}")

            other ->
              IO.puts("  Unexpected result: #{inspect(other)}")
          end
        catch
          type, reason ->
            IO.puts("  Exception: #{type} - #{inspect(reason)}")
        end

      {:error, _} ->
        IO.puts("  Erlang SNMP modules not available")
    end
  end
end
