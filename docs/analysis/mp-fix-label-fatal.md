# MP — Enforce fatal on unresolved config label

## Label discovery flow
- `sp_try_label_candidate` in `installer/runtime/lib/config_discovery.sh` probes `SP_CONFIG_LABEL_NAME` (default `SP_CONFIG`) with `sp_find_partition_by_fs_label`, which enumerates `/proc/partitions` + `blkid` and stores the matching node in `SP_CONFIG_LABEL_DEVICE` while keeping the candidate count in `SP_CONFIG_LABEL_PROBE_CANDIDATES`.
- Failure diagnostics already exist (structured `sp_log` entries for the resolver, device, and probe counts) but the function merely returns `1` when the label cannot be resolved.

## Rescue transition after label lookup
- `sp_discover_config` calls `sp_try_label_candidate`, then proceeds through removable and partition heuristics before calling `sp_enter_rescue_mode "missing-config"` when nothing yields a config (the block near the loop end in the same file).
- Because the label attempt happens before the heuristics, the code currently drops into rescue mode even when an explicit label was requested and no device could be resolved.

## Explicit label detection
- An explicit label request can be signaled by `SP_CONFIG_LABEL` or by setting `SP_CONFIG_LABEL_NAME` explicitly; when neither is provided the script should still try the default label but keep rescue as the fallback.
- The fatal path should only trigger when one of those variables is non-empty while `SP_CONFIG_LABEL_DEVICE` remains unset after the look-up.

## Earliest safe hard-fail
- The earliest point to abort is immediately after `sp_try_label_candidate` returns: at that moment we know whether a label was requested and whether `SP_CONFIG_LABEL_DEVICE` is populated.
- Logging a fatal marker (`sp_log_fatal_marker "config-label-not-found label=..."`) here and returning non-zero prevents the later heuristics and `sp_enter_rescue_mode` from running, keeping rescue mode reserved for when no explicit label was configured.

With the analysis documented, proceed to Block B implementation.
