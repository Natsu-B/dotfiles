# Mac archive / NixOS working copies

The Mac is the **archive** at `~/data`. NixOS keeps **only selected working copies** under `~/work`. Run the interactive dashboard on NixOS to select Mac files, synchronize edits back to the Mac, pause, resume, inspect errors, and safely free Linux disk space.

```text
Mac ~/data/                        NixOS ~/work/
├── project-a/   <=============>   ├── project-a/       selected
├── project-b/                    │                     not selected
├── documents/                    └── documents/
│   ├── report.pdf <===========>     └── report.pdf      selected
│   └── notes/                                           not selected
└── datasets/                                           not selected
```

Mutagen `two-way-safe` is **bidirectional**. Editing or deleting a synchronized file on Linux may propagate that change to the Mac. The dashboard's explicit **Release Linux copy** command is different from a normal `rm`: it first verifies synchronization and checks the complete Linux tree against the Mac archive. Back up the Mac separately with Time Machine or equivalent.

## Prerequisites

1. Join both devices to the same Tailscale network.
2. On macOS, enable **System Settings > General > Sharing > Remote Login**. Limit access to the intended user.
3. Put the NixOS user's **public** SSH key into the Mac user's `~/.ssh/authorized_keys` (never copy the private key).
4. On macOS, create `~/data` and store the archive there.

On NixOS, display the public key (generate one with `ssh-keygen -t ed25519` if absent):

```sh
cat ~/.ssh/id_ed25519.pub
```

On the Mac, prepare `~/.ssh/authorized_keys` and append the displayed key:

```sh
mkdir -p ~/.ssh ~/data
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```

On NixOS, create a matching `~/.ssh/config` entry. Replace the placeholder IP/user with the Mac's Tailscale IP and login.

```sshconfig
Host mac
    HostName 100.x.y.z
    User <macOS-user>
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    BatchMode yes
```

Verify the Mac host key on first connection.

```sh
ssh mac 'ls ~/data'
sudo nixos-rebuild switch --flake .#nixos
systemctl --user status mutagen.service
```

The NixOS dotfiles install Mutagen, fzf, jq, lsof, the dashboard, and a Mutagen user service. User lingering keeps the service running after logout. The synchronization connection is **NixOS -> Mac**, so NixOS does not need an additional SSH server for this feature.

## Interactive dashboard

Launch on NixOS:

```sh
mac-data-sync
# Or explicitly:
mac-data-sync menu
```

The dashboard is in English and offers:

| Menu | Purpose |
| --- | --- |
| **Browse Mac and add** | Search Mac `~/data` with fzf and select which files/folders to sync |
| **Working copies** | View Linux usage and synchronization state, select one or multiple copies, and run actions |
| **Storage cleanup** | Sort work copies by Linux disk use and safely release chosen copies |
| **Conflicts and errors** | Show disconnected, conflicted, or unhealthy sessions and inspect their Mutagen details |

In selection lists: type to search, use **Tab** for multi-select, **Enter** for actions, and **Esc** to go back. **Selecting a directory copies its entire subtree automatically**, including nested subdirectories at any depth, hidden files, and `.git` metadata. There is no need to select its children separately. If a parent and its child are both selected, the child is automatically folded into the parent selection. The picker shows only 4 levels by default; this is a **listing limit, not a copying limit**. Use `MAC_DATA_DEPTH=8 mac-data-sync pick` to browse deeper (maximum: 99), but even a folder nested 100 levels down will be copied when its parent is selected.

The actions available for working copies are **Sync now**, **Pause sync**, **Resume sync**, **Inspect**, **End sync (keep copies)**, and **Release Linux copy**. Pausing, resuming, and ending a session do not remove either copy.

## Direct CLI shortcuts

```sh
mac-data-sync ls                       # List Mac archive files
mac-data-sync pick                     # Select files and folders
mac-data-sync start project-a          # Sync Mac ~/data/project-a to Linux ~/work/project-a
mac-data-sync start documents/file.md  # Sync an individual file
mac-data-sync list                     # List Mutagen sessions
mac-data-sync status project-a         # Detailed status
mac-data-sync flush project-a          # Force a sync cycle
mac-data-sync pause project-a
mac-data-sync resume project-a
mac-data-sync terminate project-a      # End synchronization but keep both copies
mac-data-sync release project-a        # Safely delete ONLY the Linux work copy
```

**Initial copy waits** for Mutagen's first complete synchronization cycle and checks that both endpoints are connected, scanned, and free from reported errors and conflicts before printing `Ready`. If the initial copy is interrupted or cannot be verified, the session and any copied data remain, and syncing continues automatically after reconnection. Inspect with `mac-data-sync status <path>`.

Sync sessions resume automatically whenever the NixOS daemon and Mac SSH/Tailscale are reachable. Editing existing Linux files while disconnected remains possible. **Completion of synchronization never deletes Linux files on its own.**

## Safely release a Linux working copy

Only choose **Release Linux copy** after closing editors and builds that use the work copy. The command:

1. Requires explicit confirmation by typing `RELEASE <relative-path>`.
2. Flushes Mutagen, checks that the specific session and endpoints match, both endpoints are connected, a successful cycle occurred, no conflicts/problems remain, and the session is watching for changes.
3. Pauses the session; temporarily renames the Linux copy inside `~/work` to reduce write races; refuses open files when detected by lsof.
4. Compares all file names, types, directory layout, SHA-256 content hashes, and symlink targets against the Mac, **including hidden files, `.git`, and deeply nested subdirectories**. Extra Linux-only files block deletion.
5. If everything matches, terminates the session and deletes **only** the quarantined Linux working copy. Any error before termination attempts to restore the original directory and resume synchronization.

If verification fails, no Linux working data is intentionally deleted. A failed restoration or a cleanup failure may leave a `.mac-data-release.*` directory beside the work copy; recover it manually before trying again.

Checksumming large trees can be slow and is not a substitute for a backup. `lsof` is a best-effort check, not a guarantee against concurrent processes. Avoid editing the selected files during release.

If you need to retain Linux-only Git history or build products, **End sync (keep copies)** instead of releasing, archive the extra data first, and then retry the verified release.

## Limits and caveats

- Manual `rm` **inside an active two-way sync** may propagate deletion to the Mac. Use **Release Linux copy**, not `rm -r`, to reclaim space safely.
- A copy with errors, conflicts, missing SSH access, or different content is **not** eligible for release.
- Neither disk-pressure eviction nor automatic work-copy deletion is implemented.
- The picker hides `.git`, `.svn`, and `.hg` for navigability, but selecting their **parent directory still copies all VCS contents**. Mutagen is invoked with `--no-global-configuration --no-ignore-vcs` so its global ignore rules and VCS exclusion do not silently omit files. This can consume significant Linux disk space and syncing Git metadata while both Macs and Linux run Git operations concurrently may cause conflicts. Avoid concurrent Git writes.
- Nested/overlapping sessions (e.g. `project-a` and `project-a/src`) are blocked by the CLI.
- SSH paths containing `:`, tabs, newlines, or traversal components `..` cannot be chosen. Unicode and spaces are supported.
- Connection over Tailscale is not restricted to Wi-Fi specifically: any permitted network connection works.
- The UI manages sessions created by `mac-data-sync`, not arbitrary Mutagen sessions.

Upstream references: [Mutagen synchronization](https://mutagen.io/documentation/synchronization/), [Mutagen SSH transport](https://mutagen.io/documentation/transports/ssh/), [macOS Remote Login](https://support.apple.com/guide/mac-help/mchlp1066/mac).
