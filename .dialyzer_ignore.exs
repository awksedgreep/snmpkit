# Dialyzer baseline, regenerated 2026-09-05 after the PLT was rebuilt for the
# installed OTP (the previous list used a format dialyxir no longer matches, so
# none of these were being checked). Every entry is a pre-existing spec or
# pattern inaccuracy, listed as {file, warning_type} so line shifts do not
# invalidate it. Remove entries as the underlying specs are fixed; dialyxir
# reports "Unnecessary Skips" when an entry no longer matches anything.
#
# 109 warnings across the file/type pairs below.
[
  {"lib/snmp_lib.ex", :contract_supertype},
  {"lib/snmpkit.ex", :contract_supertype},
  {"lib/snmpkit/snmp_lib/asn1.ex", :contract_supertype},
  {"lib/snmpkit/snmp_lib/error.ex", :contract_supertype},
  {"lib/snmpkit/snmp_lib/error_handler.ex", :extra_range},
  {"lib/snmpkit/snmp_lib/error_handler.ex", :pattern_match},
  {"lib/snmpkit/snmp_lib/error_handler.ex", :pattern_match_cov},
  {"lib/snmpkit/snmp_lib/host_parser.ex", :contract_supertype},
  {"lib/snmpkit/snmp_lib/manager.ex", :contract_supertype},
  {"lib/snmpkit/snmp_lib/manager.ex", :pattern_match},
  {"lib/snmpkit/snmp_lib/mib/ast.ex", :contract_supertype},
  {"lib/snmpkit/snmp_lib/mib/compiler.ex", :call},
  {"lib/snmpkit/snmp_lib/mib/utilities.ex", :contract_supertype},
  {"lib/snmpkit/snmp_lib/mib/utilities.ex", :pattern_match_cov},
  {"lib/snmpkit/snmp_lib/monitor.ex", :pattern_match},
  {"lib/snmpkit/snmp_lib/oid.ex", :contract_supertype},
  {"lib/snmpkit/snmp_lib/pdu.ex", :contract_supertype},
  {"lib/snmpkit/snmp_lib/pdu/constants.ex", :contract_supertype},
  {"lib/snmpkit/snmp_lib/pdu/decoder.ex", :pattern_match_cov},
  {"lib/snmpkit/snmp_lib/pdu/encoder.ex", :pattern_match_cov},
  {"lib/snmpkit/snmp_lib/pool.ex", :contract_supertype},
  {"lib/snmpkit/snmp_lib/security.ex", :contract_supertype},
  {"lib/snmpkit/snmp_lib/security/keys.ex", :contract_supertype},
  {"lib/snmpkit/snmp_lib/security/priv.ex", :contract_supertype},
  {"lib/snmpkit/snmp_lib/transport.ex", :contract_supertype},
  {"lib/snmpkit/snmp_lib/types.ex", :contract_supertype},
  {"lib/snmpkit/snmp_mgr/core.ex", :contract_supertype},
  {"lib/snmpkit/snmp_mgr/core.ex", :pattern_match},
  {"lib/snmpkit/snmp_mgr/core.ex", :pattern_match_cov},
  {"lib/snmpkit/snmp_mgr/mib.ex", :contract_supertype},
  {"lib/snmpkit/snmp_mgr/mib.ex", :pattern_match},
  {"lib/snmpkit/snmp_mgr/table.ex", :pattern_match_cov},
  {"lib/snmpkit/snmp_mgr/walk.ex", :pattern_match},
  {"lib/snmpkit/snmp_sim.ex", :pattern_match_cov},
  {"lib/snmpkit/snmp_sim/device.ex", :pattern_match},
  {"lib/snmpkit/snmp_sim/device/modem_upgrade.ex", :invalid_contract},
  {"lib/snmpkit/snmp_sim/device/oid_handler.ex", :pattern_match},
  {"lib/snmpkit/snmp_sim/device/pdu_processor.ex", :pattern_match_cov},
  {"lib/snmpkit/snmp_sim/device/walk_pdu_processor.ex", :pattern_match},
  {"lib/snmpkit/snmp_sim/device/walk_pdu_processor.ex", :pattern_match_cov},
  {"lib/snmpkit/snmp_sim/device_distribution.ex", :contract_supertype},
  {"lib/snmpkit/snmp_sim/mib/compiler.ex", :pattern_match_cov},
  {"lib/snmpkit/snmp_sim/performance/benchmarks.ex", :unknown_function},
  {"lib/snmpkit/snmp_sim/performance/performance_monitor.ex", :unknown_function},
  {"lib/snmpkit/snmp_sim/performance/resource_manager.ex", :unknown_function},
  {"lib/snmpkit/snmp_sim/value_simulator.ex", :pattern_match_cov}
]
