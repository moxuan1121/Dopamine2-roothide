# Dopamine FontMount

This branch is based on the official `roothide/Dopamine2-roothide` `2.x`
branch. It adds only the system font bind mount; it does not include the zqbb
whitelist, injection, jetsam, or UI modifications.

During jailbreak finalization it:

1. Creates a one-time snapshot of the real `/System/Library/Fonts` directory at
   `JBROOT/mnt/System/Library/Fonts` when no non-empty snapshot exists.
2. Read-only bind mounts that snapshot over `/System/Library/Fonts`.
3. Continues the normal RootHide userspace reboot, so no second userspace reboot
   is required just for the font mount.

The modified `jbctl` also exposes these internal recovery commands:

- `jbctl internal font_mount`
- `jbctl internal font_unmount`

Deleting the snapshot is intentionally not automatic. Unmount first and verify
the target before removing any snapshot data.
