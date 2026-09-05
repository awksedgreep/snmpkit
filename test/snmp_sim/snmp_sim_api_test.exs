defmodule SnmpKit.SnmpSimTest do
  @moduledoc "Top-level simulator API: config-driven start-up, inspection, shutdown."
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpSim.TestHelpers.PortHelper

  setup do
    SnmpKit.SnmpSim.stop()
    on_exit(fn -> SnmpKit.SnmpSim.stop() end)
    :ok
  end

  defp config(ports, extra \\ %{}) do
    %{
      device_groups: [
        Map.merge(
          %{
            name: "api_test",
            device_type: "cable_modem",
            count: length(ports),
            port_range: %{start: List.first(ports), end: List.last(ports)},
            community: "public",
            walk_file: "priv/walks/cable_modem.walk"
          },
          extra
        )
      ]
    }
  end

  defp get_when_ready(port, oid, attempts \\ 20) do
    case SnmpKit.SNMP.get("127.0.0.1", oid, port: port, timeout: 500, retries: 0) do
      {:ok, _} = ok -> ok
      _ when attempts > 0 -> get_when_ready(port, oid, attempts - 1)
      other -> other
    end
  end

  defp free_ports(n) do
    # Device groups use consecutive ports starting at port_range.start
    start = PortHelper.get_port()
    Enum.to_list(start..(start + n - 1))
  end

  test "starts device groups from a bare or wrapped config and serves SNMP" do
    ports = free_ports(2)
    assert {:ok, sup} = SnmpKit.SnmpSim.start(config(ports))
    assert is_pid(sup)
    assert SnmpKit.SnmpSim.device_count() == 2

    devices = SnmpKit.SnmpSim.list_devices()
    assert Enum.map(devices, & &1.port) == ports
    assert Enum.all?(devices, &(&1.device_type == :cable_modem))

    # The walk file from the group is loaded into the devices (the UDP server
    # comes up asynchronously, so poll briefly like the other simulator tests)
    assert {:ok, %{value: descr}} = get_when_ready(hd(ports), "1.3.6.1.2.1.1.1.0")
    assert is_binary(descr) and descr != ""

    # Wrapped form works the same
    SnmpKit.SnmpSim.stop()
    assert SnmpKit.SnmpSim.device_count() == 0
    assert {:ok, _} = SnmpKit.SnmpSim.start_link(%{snmp_sim: config(ports)})
    assert SnmpKit.SnmpSim.device_count() == 2
  end

  test "stop_device by port and stop all" do
    ports = free_ports(2)
    {:ok, _} = SnmpKit.SnmpSim.start(config(ports))

    assert :ok = SnmpKit.SnmpSim.stop_device(hd(ports))
    assert [%{port: port}] = SnmpKit.SnmpSim.list_devices()
    assert port == List.last(ports)
    assert {:error, :not_found} = SnmpKit.SnmpSim.stop_device(hd(ports))

    assert :ok = SnmpKit.SnmpSim.stop()
    assert SnmpKit.SnmpSim.list_devices() == []
  end

  @tag :tmp_dir
  test "loads and validates JSON configuration files", %{tmp_dir: dir} do
    ports = free_ports(1)
    path = Path.join(dir, "sim.json")
    File.write!(path, Jason.encode!(%{snmp_sim: config(ports)}))

    assert {:ok, %{snmp_sim: %{device_groups: [group]}}} = SnmpKit.SnmpSim.load_config(path)
    assert group.port_range.start == hd(ports)
    assert :ok = SnmpKit.SnmpSim.validate_config(config(ports))

    assert {:ok, _} = SnmpKit.SnmpSim.start(path)
    assert SnmpKit.SnmpSim.device_count() == 1

    assert {:error, {:unsupported_config_format, ".toml"}} =
             SnmpKit.SnmpSim.load_config(Path.join(dir, "sim.toml"))

    assert {:error, _} = SnmpKit.SnmpSim.start(%{device_groups: [%{name: "bad"}]})
  end

  test "sample_config validates" do
    assert :ok = SnmpKit.SnmpSim.validate_config(SnmpKit.SnmpSim.sample_config())
  end
end
