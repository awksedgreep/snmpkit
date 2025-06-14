defmodule SnmpKit.SnmpSim.ConfigTest do
  use ExUnit.Case, async: true
  alias SnmpKit.SnmpSim.Config

  describe "configuration validation" do
    test "validates correct configuration" do
      config = %{
        snmp_sim: %{
          global_settings: %{
            max_devices: 1000,
            max_memory_mb: 512
          },
          device_groups: [
            %{
              name: "test_devices",
              count: 10,
              port_range: %{start: 30000, end: 30009}
            }
          ]
        }
      }

      assert Config.validate_config(config) == :ok
    end

    test "rejects configuration without snmp_sim key" do
      config = %{other_app: %{}}

      assert {:error, "Configuration must contain a 'snmp_sim' key"} =
               Config.validate_config(config)
    end

    test "validates device group port ranges" do
      config = %{
        snmp_sim: %{
          device_groups: [
            %{
              name: "test_devices",
              count: 10,
              # Invalid: start > end
              port_range: %{start: 30000, end: 29999}
            }
          ]
        }
      }

      assert {:error, "port_range start must be <= end"} =
               Config.validate_config(config)
    end

    test "requires essential fields in device groups" do
      config = %{
        snmp_sim: %{
          device_groups: [
            %{
              # Missing required fields: name, count, port_range
            }
          ]
        }
      }

      assert {:error, message} = Config.validate_config(config)
      assert String.contains?(message, "missing required field")
    end
  end

  describe "environment variable parsing" do
    test "loads configuration from environment variables" do
      # Set test environment variables
      System.put_env([
        {"SNMP_SIM_EX_MAX_DEVICES", "500"},
        {"SNMP_SIM_EX_MAX_MEMORY_MB", "256"},
        {"SNMP_SIM_EX_ENABLE_TELEMETRY", "true"},
        {"SNMP_SIM_EX_DEVICE_COUNT", "5"},
        {"SNMP_SIM_EX_PORT_RANGE_START", "40000"}
      ])

      {:ok, config} = Config.load_from_environment()

      # Verify configuration was loaded correctly
      assert config.snmp_sim.global_settings.max_devices == 500
      assert config.snmp_sim.global_settings.max_memory_mb == 256
      assert config.snmp_sim.global_settings.enable_telemetry == true

      # Verify device group was created from env vars
      device_groups = config.snmp_sim.device_groups
      assert length(device_groups) == 1

      device_group = List.first(device_groups)
      assert device_group.count == 5
      assert device_group.port_range.start == 40000

      # Cleanup environment variables
      System.delete_env("SNMP_SIM_EX_MAX_DEVICES")
      System.delete_env("SNMP_SIM_EX_MAX_MEMORY_MB")
      System.delete_env("SNMP_SIM_EX_ENABLE_TELEMETRY")
      System.delete_env("SNMP_SIM_EX_DEVICE_COUNT")
      System.delete_env("SNMP_SIM_EX_PORT_RANGE_START")
    end

    test "handles missing environment variables with defaults" do
      # Ensure no relevant env vars are set
      env_vars = [
        "SNMP_SIM_EX_MAX_DEVICES",
        "SNMP_SIM_EX_MAX_MEMORY_MB",
        "SNMP_SIM_EX_DEVICE_COUNT"
      ]

      Enum.each(env_vars, &System.delete_env/1)

      {:ok, config} = Config.load_from_environment()

      # Should use defaults
      assert config.snmp_sim.global_settings.max_devices == 1000
      assert config.snmp_sim.global_settings.max_memory_mb == 512

      # Should have empty device groups when count is 0 (default)
      assert config.snmp_sim.device_groups == []
    end
  end

  describe "JSON configuration" do
    test "loads valid JSON configuration" do
      json_content = """
      {
        "snmp_sim": {
          "global_settings": {
            "max_devices": 100,
            "max_memory_mb": 128
          },
          "device_groups": [
            {
              "name": "test_group",
              "count": 5,
              "port_range": {
                "start": 50000,
                "end": 50004
              },
              "community": "test"
            }
          ]
        }
      }
      """

      # Create temporary file
      file_path = "/tmp/test_config.json"
      File.write!(file_path, json_content)

      try do
        {:ok, config} = Config.load_from_file(file_path)

        assert config.snmp_sim.global_settings.max_devices == 100
        assert config.snmp_sim.global_settings.max_memory_mb == 128

        device_group = List.first(config.snmp_sim.device_groups)
        assert device_group.name == "test_group"
        assert device_group.count == 5
        assert device_group.community == "test"
      after
        File.rm(file_path)
      end
    end

    test "handles invalid JSON" do
      invalid_json = """
      {
        "snmp_sim": {
          "invalid": json
        }
      """

      file_path = "/tmp/invalid_config.json"
      File.write!(file_path, invalid_json)

      try do
        assert {:error, {:json_decode_error, _}} = Config.load_from_file(file_path)
      after
        File.rm(file_path)
      end
    end

    test "handles non-existent files" do
      assert {:error, {:file_read_error, _}} = Config.load_from_file("/non/existent/file.json")
    end
  end

  describe "sample configuration" do
    test "sample configuration is valid" do
      config = Config.sample_config()
      assert Config.validate_config(config) == :ok
    end

    test "can write sample configuration to JSON file" do
      file_path = "/tmp/sample_config.json"

      try do
        assert :ok = Config.write_sample_config(file_path, :json)
        assert File.exists?(file_path)

        # Verify the written file can be loaded back
        {:ok, loaded_config} = Config.load_from_file(file_path)
        assert Config.validate_config(loaded_config) == :ok
      after
        File.rm(file_path)
      end
    end
  end

  describe "YAML configuration" do
    # Only test YAML if the dependency is available
    if Code.ensure_loaded?(YamlElixir) do
      test "loads valid YAML configuration" do
        yaml_content = """
        snmp_sim:
          global_settings:
            max_devices: 200
            max_memory_mb: 256
          device_groups:
            - name: yaml_test_group
              count: 3
              port_range:
                start: 60000
                end: 60002
              community: yaml_test
        """

        file_path = "/tmp/test_config.yaml"
        File.write!(file_path, yaml_content)

        try do
          {:ok, config} = Config.load_yaml(file_path)

          assert config.snmp_sim.global_settings.max_devices == 200
          assert config.snmp_sim.global_settings.max_memory_mb == 256

          device_group = List.first(config.snmp_sim.device_groups)
          assert device_group.name == "yaml_test_group"
          assert device_group.count == 3
          assert device_group.community == "yaml_test"
        after
          File.rm(file_path)
        end
      end

      test "can write sample configuration to YAML file" do
        file_path = "/tmp/sample_config.yaml"

        try do
          assert :ok = Config.write_sample_config(file_path, :yaml)
          assert File.exists?(file_path)

          # Verify the written file can be loaded back
          {:ok, loaded_config} = Config.load_yaml(file_path)
          assert Config.validate_config(loaded_config) == :ok
        after
          File.rm(file_path)
        end
      end
    else
      test "handles missing YAML dependency gracefully" do
        file_path = "/tmp/test.yaml"
        File.write!(file_path, "test: content")

        try do
          assert {:error, {:missing_dependency, _message}} = Config.load_yaml(file_path)
        after
          File.rm(file_path)
        end
      end
    end
  end
end
