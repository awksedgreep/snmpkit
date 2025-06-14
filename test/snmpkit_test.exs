defmodule SnmpkitTest do
  use ExUnit.Case
  doctest Snmpkit

  test "greets the world" do
    assert Snmpkit.hello() == :world
  end
end
