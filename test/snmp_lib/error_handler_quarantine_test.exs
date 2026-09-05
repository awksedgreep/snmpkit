defmodule SnmpKit.SnmpLib.ErrorHandlerQuarantineTest do
  use ExUnit.Case, async: false

  alias SnmpKit.SnmpLib.ErrorHandler

  test "quarantine_device/2 blocks a device until the duration elapses" do
    device = "quarantine-test-#{System.unique_integer([:positive])}"

    refute ErrorHandler.quarantined?(device)
    assert :ok = ErrorHandler.quarantine_device(device, 200)
    assert ErrorHandler.quarantined?(device)

    Process.sleep(250)
    refute ErrorHandler.quarantined?(device)
  end
end
