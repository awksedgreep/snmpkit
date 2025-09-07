defmodule SnmpKit.ApiStandardizationTest do
  use ExUnit.Case, async: true

  alias SnmpKit.SnmpMgr.Format

  test "enrich_varbind includes type and oid; name and formatted toggles" do
    v = {"1.3.6.1.2.1.1.3.0", :timeticks, 12345}

    # Defaults: include_names true, include_formatted true
    enriched_default = Format.enrich_varbind(v)
    assert %{oid: _, type: :timeticks, value: 12345} = enriched_default
    assert Map.has_key?(enriched_default, :name)
    assert Map.has_key?(enriched_default, :formatted)

    # Turn off names and formatted
    enriched_min = Format.enrich_varbind(v, include_names: false, include_formatted: false)
    assert %{oid: _, type: :timeticks, value: 12345} = enriched_min
    refute Map.has_key?(enriched_min, :name)
    refute Map.has_key?(enriched_min, :formatted)
  end

  test "enrich_varbinds maps list of tuples to list of maps" do
    list = [
      {"1.3.6.1.2.1.1.1.0", :octet_string, "desc"},
      {"1.3.6.1.2.1.1.3.0", :timeticks, 100}
    ]

    enriched = Format.enrich_varbinds(list, include_names: false, include_formatted: false)
    assert is_list(enriched)
    assert Enum.all?(enriched, fn m -> is_map(m) and Map.has_key?(m, :oid) and Map.has_key?(m, :type) end)
  end
end

