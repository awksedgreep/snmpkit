# Concurrent Multi (High-Throughput Multi-Target)

Overview
- Concurrent Multi is the high-performance approach for executing SNMP operations across many targets concurrently.
- Formerly referred to informally as “Multi v2,” this naming clarifies the behavior rather than a version.
- It uses a shared-socket architecture with non-blocking correlation to minimize overhead and maximize throughput.

Return formats
- :list (default) — results in the same order as requests
- :with_targets — [{target, oid, result}, ...]
- :map — %{{target, oid} => result, ...}

Typical usage
- Use existing multi-target functions (e.g., get_multi, get_bulk_multi) with the return_format that best fits your processing.
- Prefer bulk operations where appropriate for large tables.

Examples (conceptual)
- Query multiple devices and keep association with :map or :with_targets for clarity.
- Keep timeouts reasonable and consider batching to control load.

Defaults
- SNMP version: :v2c unless overridden
- return_format: :list (use :with_targets or :map as needed)
- max_concurrent: 10 unless overridden

Operational notes
- No manual setup should be required for common use cases; examples that show explicit engine starts are intended for advanced demonstrations and benchmarking.
- A future auto-ensure flow removes the need to start architecture components manually; for now, existing APIs work without additional setup in most applications.

Migration (from “Multi v2” wording)
- Replace references to “Multi v2” with “Concurrent Multi” in your docs and internal references.
- The API functions you already use remain the same; this is primarily a naming/doc improvement.

Best practices
- Choose return_format based on how you consume results (lookup vs. iteration).
- Use bulk operations and batching for scale.
- Avoid unnecessary formatting or name resolution in hot paths (include_formatted: false, include_names: false when needed).

