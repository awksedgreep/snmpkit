defmodule SnmpKit.MIB.DisplayHintTest do
  use ExUnit.Case, async: true

  alias SnmpKit.MIB.DisplayHint

  doctest DisplayHint

  test "1x: formats raw octets and leaves already-printed hex text alone" do
    assert DisplayHint.format("1x:", <<0, 0x1F, 0x2E, 0x3D, 0x4C, 0x5B>>) == "00:1f:2e:3d:4c:5b"
    # A walk file carries the MAC as text; hex-formatting it again would give
    # the character codes ("30:30:3a:...").
    assert DisplayHint.format("1x:", "00:1f:2e:3d:4c:5b") == "00:1f:2e:3d:4c:5b"
    assert DisplayHint.format("1x-", "00-1F-2E-3D-4C-5B") == "00-1F-2E-3D-4C-5B"
    # Six printable bytes that are not hex text are still formatted.
    assert DisplayHint.format("1x:", "abcdef") == "61:62:63:64:65:66"
  end
end
