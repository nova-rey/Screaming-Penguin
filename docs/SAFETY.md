# Screaming Penguin — Safety Guide (v1.0.0)

Screaming Penguin is intentionally simple and deterministic. It performs a full
disk wipe and installation based strictly on the supplied configuration file.

---

## Disk Wipe Behavior

- Entire target disk is erased.
- No interactive prompts except optional `ERASE` word.
- No multi-boot or partial installs.

---

## Installer Abort Conditions

Installer aborts when:

- Target disk not found  
- Target disk matches installer USB  
- Rootfs missing  
- SSH disabled and no password_hash provided  
- Invalid YAML  
- Unsupported filesystem/layout  

---

## Testing Recommendations

- Test all configs in QEMU first.
- Validate target disk names manually.
- Always examine logs after failed installs.

---

## Log Retention

Installer writes:

/config/logs/installer-*.log

Logs persist even on failure.

---

## Strongly Recommended

Enable:

safety:
require_erase_word: true

for real hardware.
