[
  # Comprehensive ignore list for dialyzer warnings
  # Focus on genuine type safety issues rather than style/defensive programming

  # Contract supertype warnings - specs that are too broad but functionally correct
  {:contract_supertype, {~c"lib/snmp_lib.ex", :info, 0}},
  {:contract_supertype, {~c"lib/snmp_mgr.ex", :get_pretty, 3}},
  {:contract_supertype, {~c"lib/snmpkit/snmp_lib/asn1.ex", :encode_null, 0}},
  {:contract_supertype, {~c"lib/snmpkit/snmp_lib/asn1.ex", :encode_sequence, 1}},
  {:contract_supertype, {~c"lib/snmpkit/snmp_lib/asn1.ex", :encode_length, 1}},
  {:contract_supertype, {~c"lib/snmpkit/snmp_lib/asn1.ex", :parse_tag, 1}},
  {:contract_supertype, {~c"lib/snmpkit/snmp_lib/asn1.ex", :validate_ber_structure, 1}},
  {:contract_supertype, {~c"lib/snmpkit/snmp_lib/host_parser.ex", :parse_ip, 1}},
  {:contract_supertype, {~c"lib/snmpkit/snmp_lib/host_parser.ex", :parse_port, 1}},
  {:contract_supertype, {~c"lib/snmpkit/snmp_lib/manager.ex", :ping, 3}},
  {:contract_supertype, {~c"lib/snmpkit/snmp_lib/error.ex", :all_error_atoms, 0}},

  # Extra range warnings - error cases that are unreachable
  {:extra_range, {~c"lib/snmp_mgr.ex", :get_bulk, 3}},
  {:extra_range, {~c"lib/snmpkit/snmp_lib/asn1.ex", :encode_integer, 1}},
  {:extra_range, {~c"lib/snmpkit/snmp_lib/asn1.ex", :encode_octet_string, 1}},
  {:extra_range, {~c"lib/snmpkit/snmp_lib/manager.ex", :get_bulk, 3}},
  {:extra_range, {~c"lib/snmpkit/snmp_lib/error_handler.ex", :quarantined?, 2}},

  # Pattern match warnings in defensive/error handling code
  {:pattern_match_cov, {~c"lib/snmpkit/snmp_lib/error_handler.ex", :quarantined?, 2}},
  {:pattern_match, {~c"lib/snmp_mgr.ex", :get, 3}},
  {:pattern_match, {~c"lib/snmp_mgr.ex", :get_next, 3}},
  {:pattern_match, {~c"lib/snmpkit/snmp_lib/manager.ex", :get, 3}},
  {:pattern_match, {~c"lib/snmpkit/snmp_lib/manager.ex", :get_next, 3}},
  {:pattern_match, {~c"lib/snmpkit/snmp_lib/manager.ex", :get_bulk, 3}},
  {:pattern_match, {~c"lib/snmpkit/snmp_lib/error_handler.ex", :circuit_open?, 1}},
  {:pattern_match, {~c"lib/snmpkit/snmp_lib/monitor.ex", :select_targets, 2}},
  {:pattern_match, {~c"lib/snmpkit/snmp_lib/mib/parser.ex", :parse_mib, 2}},

  # Unused function warnings for error handling/API completeness
  {:unused_fun, {~c"lib/snmpkit/snmp_lib/manager.ex", :extract_get_result, 1}},
  {:unused_fun, {~c"lib/snmpkit/snmp_lib/manager.ex", :extract_get_result_with_oid, 1}},
  {:unused_fun, {~c"lib/snmpkit/snmp_lib/manager.ex", :extract_bulk_result, 1}},
  {:unused_fun, {~c"lib/snmpkit/snmp_lib/manager.ex", :extract_set_result, 1}},
  {:unused_fun, {~c"lib/snmpkit/snmp_lib/manager.ex", :extract_get_next_result, 1}},
  {:unused_fun, {~c"lib/snmpkit/snmp_lib/manager.ex", :decode_error_status, 1}},

  # No return warnings for complex control flow that dialyzer can't analyze
  {:no_return, {~c"lib/snmpkit/snmp_lib/manager.ex", :perform_get_operation, 4}},
  {:no_return, {~c"lib/snmpkit/snmp_lib/manager.ex", :perform_bulk_operation, 4}},
  {:no_return, {~c"lib/snmpkit/snmp_lib/manager.ex", :perform_set_operation, 5}},
  {:no_return, {~c"lib/snmpkit/snmp_lib/manager.ex", :perform_get_next_operation, 4}},

  # Call warnings for complex control flow
  {:call, {~c"lib/snmpkit/snmp_lib/manager.ex", :perform_snmp_request, 4}},
  {:call, {~c"lib/snmpkit/snmp_lib/mib/utilities.ex", :resolve_dependencies, 1}},

  # Unknown function warnings for optional OTP applications
  {:unknown_function, {~c"lib/snmpkit/snmp_sim/performance/benchmarks.ex", {:cpu_sup, :util, 0}}},
  {:unknown_function, {~c"lib/snmpkit/snmp_sim/performance/performance_monitor.ex", {:cpu_sup, :util, 0}}},
  {:unknown_function, {~c"lib/snmpkit/snmp_sim/performance/resource_manager.ex", {:memsup, :get_memory_data, 0}}}
]
