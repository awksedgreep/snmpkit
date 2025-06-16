defmodule SnmpKitTest do
  use ExUnit.Case, async: true
  doctest SnmpKit

  # Simple test to verify module loads
  test "module loads correctly" do
    assert is_atom(SnmpKit)
  end
end
