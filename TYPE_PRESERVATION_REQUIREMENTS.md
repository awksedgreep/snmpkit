# SNMP Type Preservation Requirements

## Overview

Type information in SNMP is **CRITICAL** and must **NEVER** be lost, inferred, or approximated. This document outlines the strict requirements for preserving SNMP type information throughout the entire library.

## Why Type Preservation is Critical

SNMP type information is not optional metadata - it's essential for correct data interpretation:

### 1. **Value Ambiguity Without Types**
```elixir
# Without type information, these are ambiguous:
123456  # Could be: Integer, TimeTicks, Counter32, Gauge32, or Unsigned32
"eth0"  # Could be: OctetString or DisplayString
"1.3.6.1.2.1.1.1"  # Could be: String or ObjectIdentifier
```

### 2. **Semantic Differences**
- **Counter32** vs **Gauge32**: Counter32 wraps at 2^32, Gauge32 does not
- **TimeTicks** vs **Integer**: TimeTicks represents time in centiseconds
- **OctetString** vs **DisplayString**: Different encoding requirements
- **ObjectIdentifier** vs **String**: OIDs have structural meaning

### 3. **Protocol Compliance**
SNMP RFCs require type information for:
- Proper PDU encoding/decoding
- SET operation validation
- MIB compliance checking
- Network management applications

## Mandatory Type Preservation Rules

### Rule 1: All Operations Return 3-Tuples

**REQUIRED FORMAT**: All SNMP operations must return `{oid, type, value}` tuples.

```elixir
# ✅ CORRECT - 3-tuple with type information
{:ok, {"1.3.6.1.2.1.1.1.0", :octet_string, "Cisco IOS"}}

# ❌ FORBIDDEN - 2-tuple loses type information
{:ok, {"1.3.6.1.2.1.1.1.0", "Cisco IOS"}}
```

### Rule 2: No Type Inference Allowed

Type information must come from actual SNMP responses, never from inference.

```elixir
# ❌ FORBIDDEN - Type inference
defp infer_type(value) when is_integer(value), do: :integer

# ✅ CORRECT - Type from SNMP response
case snmp_response do
  {:ok, {oid, :counter32, value}} -> {:ok, {oid, :counter32, value}}
  {:ok, {oid, value}} -> {:error, :type_information_lost}
end
```

### Rule 3: Reject Incomplete Responses

Operations that cannot preserve type information must fail with an error.

```elixir
# ❌ FORBIDDEN - Accepting incomplete response
{:ok, {oid, value}} -> {:ok, {oid, :unknown, value}}

# ✅ CORRECT - Rejecting incomplete response
{:ok, {oid, value}} -> {:error, {:type_information_lost, "Type required"}}
```

### Rule 4: Version-Consistent Types

Type information must be consistent across SNMP versions (v1, v2c, v3).

```elixir
# Both versions must return same type for same OID
v1_result = {:ok, {"1.3.6.1.2.1.1.3.0", :timeticks, 123456}}
v2c_result = {:ok, {"1.3.6.1.2.1.1.3.0", :timeticks, 123456}}
```

## Implementation Requirements

### 1. **Core Operations**

All core SNMP operations must preserve types:

```elixir
# GET operation
def get_with_type(target, oid, opts) do
  case perform_get(target, oid, opts) do
    {:ok, {type, value}} -> {:ok, {oid_string, type, value}}
    {:ok, value} -> {:error, {:type_information_lost, "GET must preserve type"}}
    error -> error
  end
end

# WALK operation
def walk(target, root_oid, opts) do
  case perform_walk(target, root_oid, opts) do
    {:ok, results} -> validate_all_have_types(results)
    error -> error
  end
end

defp validate_all_have_types(results) do
  case Enum.find(results, fn
    {_oid, _type, _value} -> false
    _ -> true
  end) do
    nil -> {:ok, results}
    invalid -> {:error, {:invalid_format, invalid}}
  end
end
```

### 2. **Bulk Operations**

Bulk operations must preserve types for all returned varbinds:

```elixir
def process_bulk_response(varbinds) do
  processed = Enum.map(varbinds, fn
    {oid, type, value} -> {format_oid(oid), type, value}
    {oid, value} -> 
      raise "Type information lost for OID #{inspect(oid)}"
  end)
  {:ok, processed}
end
```

### 3. **Error Handling**

Error conditions must not compromise type preservation:

```elixir
# Exception values still have types
case snmp_response do
  {:ok, {oid, :no_such_object, nil}} -> {:ok, {oid, :no_such_object, nil}}
  {:ok, {oid, :end_of_mib_view, nil}} -> {:ok, {oid, :end_of_mib_view, nil}}
end
```

## Valid SNMP Types

### Basic Types
- `:integer` - 32-bit signed integer
- `:octet_string` - Byte string
- `:null` - Null value
- `:object_identifier` - OID
- `:boolean` - True/false value

### Application Types
- `:counter32` - 32-bit counter (wraps at 2^32-1)
- `:counter64` - 64-bit counter
- `:gauge32` - 32-bit gauge (non-wrapping)
- `:unsigned32` - 32-bit unsigned integer
- `:timeticks` - Time in centiseconds
- `:ip_address` - IPv4 address
- `:opaque` - Opaque data

### Exception Types (SNMPv2c+)
- `:no_such_object` - Object doesn't exist
- `:no_such_instance` - Instance doesn't exist
- `:end_of_mib_view` - End of MIB reached

## Testing Requirements

### 1. **Type Validation Tests**

Every operation must be tested for type preservation:

```elixir
def test_get_preserves_type do
  {:ok, {oid, type, value}} = SNMP.get_with_type("device", "sysDescr.0")
  assert is_binary(oid)
  assert is_atom(type)
  assert type in @valid_snmp_types
end

def test_walk_preserves_all_types do
  {:ok, results} = SNMP.walk("device", "system")
  Enum.each(results, fn {oid, type, value} ->
    assert is_binary(oid)
    assert is_atom(type)
    assert type in @valid_snmp_types
  end)
end
```

### 2. **No 2-Tuple Tests**

Verify that 2-tuple responses are never returned:

```elixir
def test_no_2_tuple_responses do
  operations = [
    fn -> SNMP.get_with_type("device", "sysDescr.0") end,
    fn -> SNMP.walk("device", "system") end,
    fn -> SNMP.get_bulk("device", "interfaces") end
  ]
  
  Enum.each(operations, fn op ->
    case op.() do
      {:ok, results} when is_list(results) ->
        Enum.each(results, fn
          {_oid, _type, _value} -> :ok
          {oid, _value} -> flunk("2-tuple found for #{oid}")
        end)
      {:ok, {_oid, _type, _value}} -> :ok
      {:ok, {oid, _value}} -> flunk("2-tuple found for #{oid}")
      {:error, _} -> :ok
    end
  end)
end
```

### 3. **Version Consistency Tests**

Test that types are consistent across SNMP versions:

```elixir
def test_version_type_consistency do
  oid = "1.3.6.1.2.1.1.1.0"
  
  {:ok, {_, type_v1, value_v1}} = SNMP.get_with_type("device", oid, version: :v1)
  {:ok, {_, type_v2c, value_v2c}} = SNMP.get_with_type("device", oid, version: :v2c)
  
  assert type_v1 == type_v2c, "Type mismatch between versions"
end
```

## Common Violations to Avoid

### 1. **Type Inference**
```elixir
# ❌ DON'T DO THIS
defp guess_type(value) when is_integer(value), do: :integer
defp guess_type(value) when is_binary(value), do: :octet_string
```

### 2. **Fallback to 2-Tuples**
```elixir
# ❌ DON'T DO THIS
{:ok, {oid, value}} -> {:ok, {oid, :unknown, value}}
```

### 3. **Ignoring Type Validation**
```elixir
# ❌ DON'T DO THIS
def process_result({oid, type_or_value, maybe_value}) when is_atom(type_or_value) do
  # Assuming 3-tuple without validation
```

### 4. **Converting 3-Tuples to 2-Tuples**
```elixir
# ❌ DON'T DO THIS
{oid, _type, value} -> {oid, value}  # Strips type information
```

## Debugging Type Issues

### 1. **Enable Type Logging**
```elixir
Logger.debug("SNMP Response: OID=#{oid}, Type=#{type}, Value=#{inspect(value)}")
```

### 2. **Validate Response Format**
```elixir
defp validate_snmp_response({oid, type, value}) when is_atom(type) do
  if type in @valid_snmp_types do
    {:ok, {oid, type, value}}
  else
    {:error, {:invalid_type, type}}
  end
end

defp validate_snmp_response({oid, value}) do
  {:error, {:type_missing, oid}}
end
```

### 3. **Type Assertion Macros**
```elixir
defmacro assert_3_tuple({oid, type, value}) do
  quote do
    assert is_binary(unquote(oid)), "OID must be string"
    assert is_atom(unquote(type)), "Type must be atom"
    assert unquote(type) in @valid_snmp_types, "Invalid SNMP type"
  end
end
```

## Migration from Legacy Code

### 1. **Identify 2-Tuple Usage**
```bash
grep -r "{.*,.*}" lib/ | grep -v "{.*,.*,.*}"
```

### 2. **Update Function Signatures**
```elixir
# Old - 2-tuple
def process_result({oid, value}) do

# New - 3-tuple
def process_result({oid, type, value}) do
```

### 3. **Add Type Validation**
```elixir
# Add at function entry points
case snmp_operation() do
  {:ok, results} -> assert_all_3_tuples(results)
  error -> error
end
```

## Conclusion

Type preservation in SNMP is not negotiable. Every operation must maintain complete type information from the SNMP agent response through to the application layer. Any loss of type information represents a critical bug that must be fixed immediately.

**Remember**: It's better for an operation to fail with a clear error than to silently lose type information.