defmodule SnmpKit.MIB.TableIndexTest do
  use ExUnit.Case, async: true

  alias SnmpKit.MIB.TableIndex

  doctest TableIndex

  test "single integer index" do
    assert {:ok, %{"ifIndex" => 3}} = TableIndex.decode([3], [%{name: "ifIndex", base: :integer}])
  end

  test "IpAddress index" do
    assert {:ok, %{"ipAdEntAddr" => {192, 168, 1, 1}}} =
             TableIndex.decode([192, 168, 1, 1], [%{name: "ipAdEntAddr", base: :ip_address}])
  end

  test "fixed-size octet string index (MacAddress)" do
    assert {:ok, %{"dot1dTpFdbAddress" => <<0, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E>>}} =
             TableIndex.decode([0, 0x1A, 0x2B, 0x3C, 0x4D, 0x5E], [
               %{name: "dot1dTpFdbAddress", base: :octet_string, size: {6, 6}}
             ])
  end

  test "length-prefixed and implied variable-length strings" do
    specs = [%{name: "port", base: :integer}, %{name: "user", base: :octet_string}]
    assert {:ok, %{"port" => 7, "user" => "bob"}} = TableIndex.decode([7, 3, ?b, ?o, ?b], specs)

    implied = [
      %{name: "port", base: :integer},
      %{name: "user", base: :octet_string, implied: true}
    ]

    assert {:ok, %{"port" => 7, "user" => "bob"}} = TableIndex.decode([7, ?b, ?o, ?b], implied)
  end

  test "object identifier index" do
    specs = [%{name: "slot", base: :integer}, %{name: "ref", base: :object_identifier}]
    assert {:ok, %{"slot" => 1, "ref" => [1, 3, 6]}} = TableIndex.decode([1, 3, 1, 3, 6], specs)
  end

  test "mismatches are errors" do
    assert {:error, :trailing_sub_identifiers} =
             TableIndex.decode([1, 2], [%{name: "a", base: :integer}])

    assert {:error, :missing_sub_identifiers} =
             TableIndex.decode([1], [%{name: "a", base: :integer}, %{name: "b", base: :integer}])

    assert {:error, :missing_sub_identifiers} =
             TableIndex.decode([10, 0], [%{name: "ip", base: :ip_address}])
  end
end
