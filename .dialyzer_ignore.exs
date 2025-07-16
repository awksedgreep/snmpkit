[
  # Ignore unused functions that are part of the public API or test helpers
  {:warn_unused_function, :extract_get_result, 1},
  {:warn_unused_function, :extract_get_result_with_oid, 1},
  {:warn_unused_function, :extract_bulk_result, 1},
  {:warn_unused_function, :extract_set_result, 1},
  {:warn_unused_function, :extract_get_next_result, 1},
  {:warn_unused_function, :decode_error_status, 1},

  # Ignore pattern match warnings in error handling code - these are defensive patterns
  {:warn_pattern_match, ~c"lib/snmpkit/snmp_lib/error_handler.ex", :_},

  # Ignore no_return warnings for functions that have error handling paths
  {:warn_return_no_exit, ~c"lib/snmpkit/snmp_lib/manager.ex", :perform_get_operation},
  {:warn_return_no_exit, ~c"lib/snmpkit/snmp_lib/manager.ex", :perform_bulk_operation},
  {:warn_return_no_exit, ~c"lib/snmpkit/snmp_lib/manager.ex", :perform_set_operation},
  {:warn_return_no_exit, ~c"lib/snmpkit/snmp_lib/manager.ex", :perform_get_next_operation},

  # Ignore call warnings for functions that have complex control flow
  {:warn_failing_call, ~c"lib/snmpkit/snmp_lib/manager.ex", :_}
]
