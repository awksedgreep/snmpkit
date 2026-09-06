defmodule SnmpKit.SNMPv3ParityTest do
  @moduledoc """
  Every manager operation must give the same answer whether it is asked over
  a community or over SNMPv3 at any security level. Each test runs one
  operation four ways against one simulated device and compares the results
  with the v2c baseline, so an operation that silently stays v2c-only (or
  breaks under v3) fails here.
  """
  use ExUnit.Case, async: false

  alias SnmpKit.SNMP

  @users [
    %{name: "guest"},
    %{name: "monitor", auth: :sha256, auth_password: "monitor-auth-secret"},
    %{
      name: "ops",
      auth: :sha256,
      auth_password: "ops-auth-secret",
      priv: :aes128,
      priv_password: "ops-priv-secret"
    }
  ]

  @principals [
    v2c: [community: "public"],
    no_auth_no_priv: [version: :v3, security_name: "guest"],
    auth_no_priv: [
      version: :v3,
      security_name: "monitor",
      auth_protocol: :sha256,
      auth_password: "monitor-auth-secret"
    ],
    auth_priv: [
      version: :v3,
      security_name: "ops",
      auth_protocol: :sha256,
      auth_password: "ops-auth-secret",
      priv_protocol: :aes128,
      priv_password: "ops-priv-secret"
    ]
  ]

  # values a simulated device changes between polls
  @dynamic_types [:timeticks, :counter32, :counter64, :gauge32]

  @operations ~w(
    get get_multiple_oids get_missing get_next get_bulk walk walk_interfaces bulk_walk
    adaptive_walk walk_table get_table get_table_named get_column walk_stream table_stream
    get_async get_bulk_async get_pretty walk_pretty set set_many
    get_multi get_bulk_multi walk_multi walk_table_multi execute_mixed
  )

  setup_all do
    {:ok, profile} = SnmpKit.SnmpSim.ProfileLoader.load_profile(:router)
    port = 29_000 + :rand.uniform(3_000)

    {:ok, device} =
      SnmpKit.Sim.start_device(profile,
        port: port,
        community: "public",
        v3_users: @users,
        device_id: "parity-router"
      )

    on_exit(fn -> if Process.alive?(device), do: GenServer.stop(device) end)
    SnmpKit.SnmpLib.Security.EngineCache.clear()
    %{target: "127.0.0.1:#{port}"}
  end

  for op <- @operations do
    test "#{op} answers the same over v2c and every SNMPv3 level", %{target: target} do
      op = unquote(op)
      baseline = normalize(run(op, target, opts(:v2c)))

      for {level, principal} <- @principals, level != :v2c do
        result = normalize(run(op, target, Keyword.merge(principal, timeout: 3_000)))

        assert result == baseline,
               "#{op} over #{level} differs from v2c:\n#{inspect(result, limit: 20)}\nvs\n#{inspect(baseline, limit: 20)}"
      end

      # SET is refused by simulated devices and a missing object is an error
      # by design; the parity of those errors is what is being checked
      unless op in ["set", "set_many", "get_missing"] do
        refute match?({:error, _}, baseline), "#{op} failed even over v2c: #{inspect(baseline)}"
      end
    end
  end

  defp opts(level), do: Keyword.merge(@principals[level], timeout: 3_000)

  ## one clause per operation

  defp run("get", t, o), do: SNMP.get(t, "sysDescr.0", o)

  defp run("get_multiple_oids", t, o),
    do: SNMP.get(t, ["sysDescr.0", "sysName.0", "ifNumber.0"], o)

  defp run("get_missing", t, o), do: SNMP.get(t, "1.3.6.1.2.1.1.99.0", o)
  defp run("get_next", t, o), do: SNMP.get_next(t, "sysDescr.0", o)
  defp run("get_bulk", t, o), do: SNMP.get_bulk(t, "system", Keyword.put(o, :max_repetitions, 5))
  defp run("walk", t, o), do: SNMP.walk(t, "system", o)
  defp run("walk_interfaces", t, o), do: SNMP.walk(t, "interfaces", o)
  defp run("bulk_walk", t, o), do: SNMP.bulk_walk(t, "interfaces", o)
  defp run("adaptive_walk", t, o), do: SNMP.adaptive_walk(t, "interfaces", o)
  defp run("walk_table", t, o), do: SNMP.walk_table(t, "ifTable", o)
  # tables carry no types, so keep only the columns that do not change between polls
  defp run("get_table", t, o),
    do: static_columns(SNMP.get_table(t, "ifTable", o), [1, 2, 3, 4, 5, 7, 8])

  defp run("get_table_named", t, o),
    do:
      static_columns(
        SNMP.get_table(t, "ifTable", Keyword.put(o, :named, true)),
        ~w(ifIndex ifDescr ifType ifMtu ifSpeed ifAdminStatus ifOperStatus)
      )

  defp run("get_column", t, o), do: SNMP.get_column(t, "ifTable", 2, o)
  defp run("walk_stream", t, o), do: {:ok, Enum.to_list(SNMP.walk_stream(t, "system", o))}
  defp run("table_stream", t, o), do: {:ok, Enum.to_list(SNMP.table_stream(t, "ifTable", o))}
  defp run("get_async", t, o), do: Task.await(SNMP.get_async(t, "sysDescr.0", o), 5_000)

  defp run("get_bulk_async", t, o),
    do: Task.await(SNMP.get_bulk_async(t, "system", Keyword.put(o, :max_repetitions, 4)), 5_000)

  defp run("get_pretty", t, o), do: SNMP.get_pretty(t, "sysDescr.0", o)
  defp run("walk_pretty", t, o), do: SNMP.walk_pretty(t, "ifDescr", o)
  defp run("set", t, o), do: SNMP.set(t, "sysContact.0", "parity", o)

  defp run("set_many", t, o),
    do: SNMP.set_many(t, [{"sysContact.0", "a"}, {"sysLocation.0", "b"}], o)

  defp run("get_multi", t, o),
    do: SNMP.get_multi([{t, "sysDescr.0", o}, {t, "sysName.0", o}], timeout: 3_000)

  defp run("get_bulk_multi", t, o),
    do: SNMP.get_bulk_multi([{t, "system", Keyword.put(o, :max_repetitions, 3)}], timeout: 3_000)

  defp run("walk_multi", t, o),
    do: SNMP.walk_multi([{t, "system", o}, {t, "ifDescr", o}], timeout: 5_000)

  defp run("walk_table_multi", t, o),
    do: SNMP.walk_table_multi([{t, "ifTable", o}], timeout: 5_000)

  defp run("execute_mixed", t, o) do
    SnmpKit.SnmpMgr.Multi.execute_mixed(
      [
        {:get, t, "sysName.0", o},
        {:get_bulk, t, "system", Keyword.put(o, :max_repetitions, 3)},
        {:walk, t, "ifDescr", o}
      ],
      timeout: 5_000
    )
  end

  defp static_columns({:ok, table}, columns),
    do: {:ok, Map.new(table, fn {index, row} -> {index, Map.take(row, columns)} end)}

  defp static_columns(other, _columns), do: other

  ## result normalisation: keep structure, OIDs and types; blank out values that change over time

  defp normalize(%{oid: _, type: type} = varbind) do
    varbind
    |> Map.take([:oid, :type, :value, :name])
    |> Map.update(:value, nil, &if(type in @dynamic_types, do: :dynamic, else: &1))
  end

  defp normalize({oid, type, value}) when is_atom(type),
    do: {oid, type, if(type in @dynamic_types, do: :dynamic, else: value)}

  defp normalize(%{} = map) when not is_struct(map),
    do: Map.new(map, fn {k, v} -> {k, normalize(v)} end)

  defp normalize(list) when is_list(list), do: Enum.map(list, &normalize/1)
  defp normalize({:ok, value}), do: {:ok, normalize(value)}
  defp normalize({:error, reason}), do: {:error, reason}
  defp normalize(string) when is_binary(string), do: string
  defp normalize(other), do: other
end
