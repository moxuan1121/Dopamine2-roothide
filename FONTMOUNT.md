# Dopamine GenericMount

This branch is based on the official `roothide/Dopamine2-roothide` `2.x`
branch. It adds only configurable bind mounts; it does not include the zqbb
whitelist, injection, jetsam, or UI modifications.

During jailbreak finalization it:

1. Reads paths from `JBROOT/var/mobile/Library/RootHide/com.moxuan1121.genericmount.plist`.
2. Creates one-time snapshots below `JBROOT/mnt` when no non-empty snapshot exists.
3. Read-only bind mounts each snapshot over its corresponding system path.
3. Continues the normal RootHide userspace reboot, so no second userspace reboot
   is required just for the font mount.

The initial configuration contains `/System/Library/Fonts`. The modified
`jbctl` also exposes these internal recovery commands:

- `jbctl internal font_mount`
- `jbctl internal font_unmount`
- `jbctl internal mount /absolute/directory`
- `jbctl internal unmount /absolute/directory`

Deleting the snapshot is intentionally not automatic. Unmount first and verify
the target before removing any snapshot data.
