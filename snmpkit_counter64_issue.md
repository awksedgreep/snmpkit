# SnmpKit Bug Report: Counter64 Decoding Fails for Values < 8 Bytes

## Summary

Counter64 values that encode to fewer than 8 bytes are incorrectly decoded as `0`.

## Affected File

`lib/snmpkit/snmp_lib/pdu/decoder.ex`

## Root Cause

The `decode_counter64/1` function only handles exactly 8-byte values:

```elixir
defp decode_counter64(data) when byte_size(data) == 8 do
  :binary.decode_unsigned(data, :big)
end

defp decode_counter64(_), do: 0
```

ASN.1 BER encoding uses minimal bytes - a counter64 value like `898713201` only requires 4 bytes, not 8. The current implementation returns `0` for any counter64 that isn't exactly 8 bytes.

## Symptoms

- `snmpbulkwalk` shows: `Counter64: 898713201`
- SnmpKit returns: `%{type: :counter64, value: 0}`

## Fix

Change the guard from `== 8` to `<= 8`:

```elixir
defp decode_counter64(data) when byte_size(data) <= 8 and byte_size(data) > 0 do
  :binary.decode_unsigned(data, :big)
end

defp decode_counter64(_), do: 0
```

## Notes

- `decode_unsigned_integer/1` (used for counter32, gauge32) already handles variable-length correctly
- Counter64 is commonly used for interface traffic counters (ifHCInOctets, ifHCOutOctets) which are critical metrics
- Most counter64 values in the wild will be well under 8 bytes until counters wrap

## Test Case

```elixir
# Poll a MikroTik or any device with traffic counters
SnmpKit.SnmpMgr.MultiV2.walk_multi([
  {"192.168.89.197", "1.3.6.1.2.1.31.1.1.1.6", [community: "public"]}
])

# Before fix: value: 0
# After fix: value: 899011976
```

## Fix Applied ✅

**Date:** 2024-01-XX  
**Status:** FIXED  

The issue has been resolved by modifying the `decode_counter64/1` function in `lib/snmpkit/snmp_lib/pdu/decoder.ex`.

**Change Made:**
```elixir
# Before (line 558)
defp decode_counter64(data) when byte_size(data) == 8 do
  :binary.decode_unsigned(data, :big)
end

# After (line 558)  
defp decode_counter64(data) when byte_size(data) <= 8 and byte_size(data) > 0 do
  :binary.decode_unsigned(data, :big)
end
```

**Verification:**
- All existing tests continue to pass
- New comprehensive tests added to verify Counter64 values from 1-8 bytes decode correctly
- Manual testing confirms Counter64 values like 898713201 (4 bytes) now decode properly instead of returning 0

This fix ensures Counter64 values encoded with minimal bytes (as per ASN.1 BER encoding rules) are properly decoded, resolving the issue where interface traffic counters and other Counter64 values were incorrectly showing as 0.
