defmodule SnmpKit.SnmpKit.SnmpLib.MIB.ComprehensiveMibTest do
  use ExUnit.Case, async: true

  @moduledoc """
  Comprehensive test suite for all MIB fixtures to ensure 100% compatibility
  across working, broken, and DOCSIS MIB categories.
  """

  @test_dirs [
    {"working", "test/fixtures/mibs/working"},
    {"broken", "test/fixtures/mibs/broken"},
    {"docsis", "test/fixtures/mibs/docsis"}
  ]

  describe "MIB compatibility tests" do
    for {dir_name, dir_path} <- @test_dirs do
      test "#{dir_name} MIBs parse successfully" do
        dir_path = Path.join(File.cwd!(), unquote(dir_path))

        case File.ls(dir_path) do
          {:ok, files} ->
            mib_files = filter_mib_files(files)

            assert length(mib_files) > 0, "No MIB files found in #{unquote(dir_name)} directory"

            results = test_mib_files(dir_path, mib_files)

            successful = Enum.count(results, fn {status, _} -> status == :ok end)
            failed = Enum.filter(results, fn {status, _} -> status == :error end)

            # Log results for visibility
            IO.puts(
              "\n#{String.upcase(unquote(dir_name))} MIBs: #{successful}/#{length(mib_files)} successful"
            )

            if length(failed) > 0 do
              IO.puts("Failed files:")

              for {:error, {file, reason}} <- failed do
                reason_str =
                  case reason do
                    {line, module, message} when is_integer(line) and is_atom(module) ->
                      "Line #{line}: #{message}"

                    reason when is_binary(reason) ->
                      reason

                    _ ->
                      inspect(reason)
                  end

                IO.puts("  - #{file}: #{reason_str}")
              end
            end

            # All files should tokenize successfully
            assert successful == length(mib_files),
                   "#{length(failed)} files failed to tokenize in #{unquote(dir_name)} directory"

          {:error, reason} ->
            flunk("Could not read #{unquote(dir_name)} directory: #{reason}")
        end
      end
    end
  end

  describe "performance benchmarks" do
    test "lexer performance meets minimum thresholds" do
      # Test with a sample from each directory type (use files that actually parse)
      test_cases = [
        # 500 definitions/sec minimum
        {"working", "test/fixtures/mibs/working/IF-MIB.mib", 500},
        {"working", "test/fixtures/mibs/working/HOST-RESOURCES-MIB.mib", 500},
        {"docsis", "test/fixtures/mibs/docsis/DOCS-CABLE-DEVICE-MIB", 500}
      ]

      for {type, file_path, min_rate} <- test_cases do
        full_path = Path.join(File.cwd!(), file_path)

        if File.exists?(full_path) do
          content = File.read!(full_path)

          # Warm up and verify file parses successfully
          case SnmpKit.SnmpLib.MIB.Parser.parse(content) do
            {:ok, _} ->
              # Performance test
              {time_us, {:ok, mib}} =
                :timer.tc(fn ->
                  SnmpKit.SnmpLib.MIB.Parser.parse(content)
                end)

              # Calculate a rate based on definitions instead of tokens
              definitions_count =
                case mib do
                  %{definitions: defs} when is_list(defs) -> length(defs)
                  _ -> 1
                end

              rate = definitions_count / time_us * 1_000_000

              assert rate >= min_rate,
                     "#{type} MIB performance too slow: #{Float.round(rate)} definitions/sec < #{min_rate}"

            {:error, _reason} ->
              # Skip performance test for files that don't parse
              IO.puts("Skipping performance test for #{file_path} - parsing failed")
          end
        end
      end
    end
  end

  describe "memory efficiency tests" do
    @tag :memory
    test "tokenization does not leak memory" do
      # Test with a medium-sized file repeatedly
      file_path = Path.join(File.cwd!(), "test/fixtures/mibs/working/IF-MIB.mib")

      if File.exists?(file_path) do
        content = File.read!(file_path)

        # Get baseline memory
        :erlang.garbage_collect()
        initial_memory = :erlang.memory(:total)

        # Run parsing multiple times
        for _ <- 1..100 do
          {:ok, _mib} = SnmpKit.SnmpLib.MIB.Parser.parse(content)
        end

        # Force garbage collection and check memory
        :erlang.garbage_collect()
        final_memory = :erlang.memory(:total)

        memory_increase = final_memory - initial_memory
        memory_increase_mb = memory_increase / 1_024 / 1_024

        # Should not leak significant memory (allow 10MB tolerance)
        assert memory_increase_mb < 10,
               "Memory leak detected: #{Float.round(memory_increase_mb, 2)}MB increase"
      end
    end
  end

  # Helper functions

  defp filter_mib_files(files) do
    files
    |> Enum.filter(fn file ->
      String.ends_with?(file, [".mib", ".MIB"]) or
        (not String.contains?(file, ".") and not String.starts_with?(file, "download"))
    end)
    |> Enum.sort()
  end

  defp test_mib_files(dir_path, mib_files) do
    Enum.map(mib_files, fn file ->
      file_path = Path.join(dir_path, file)
      test_single_mib_file(file_path, file)
    end)
  end

  defp test_single_mib_file(file_path, file_name) do
    case File.read(file_path) do
      {:ok, content} ->
        case SnmpKit.SnmpLib.MIB.Parser.parse(content) do
          {:ok, mib} when is_map(mib) ->
            definitions_count =
              case mib do
                %{definitions: defs} when is_list(defs) -> length(defs)
                _ -> 1
              end

            {:ok, {file_name, definitions_count}}

          {:error, reason} ->
            {:error, {file_name, reason}}
        end

      {:error, reason} ->
        {:error, {file_name, "File read error: #{reason}"}}
    end
  end
end
