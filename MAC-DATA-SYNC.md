# Mac archive / NixOS and Windows working copies

The Mac is the **archive** at `~/data`. NixOS keeps **only selected working copies** under `~/work`. **Windows 10/11 is supported as another working client through WSL2.** See [WINDOWS-MAC-DATA-SYNC.md](WINDOWS-MAC-DATA-SYNC.md) for setup and the same English interface. Run the interactive dashboard on NixOS to select Mac files, synchronize edits back to the Mac, pause, resume, inspect errors, and safely free Linux disk space.

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
| **Browse Mac and add** | `ls`-like directory browser: list only the current Mac folder; open subfolders or sync individual files/entire directories |
| **Browse Linux and sync** | Navigate local `~/work` and publish an existing file or folder to Mac even when `~/data/<path>` has not been created |
| **Working copies** | View Linux usage and synchronization state, select one or multiple copies, and run actions |
| **Storage cleanup** | Sort work copies by Linux disk use and safely release chosen copies |
| **Conflicts and errors** | Show disconnected, conflicted, or unhealthy sessions and inspect their Mutagen details |

**Browse Mac and add** opens at `~/data`, like a normal file manager. Each screen lists **only the immediate children** of the current folder using a single shallow SSH listing; it does not walk the archive tree or precompute sizes/hashes. Select an **OPEN** row to enter a directory, **UP** to go to its parent, or a **SYNC** row to start copying. Use **Tab** to select several SYNC rows and **Enter** to proceed, then confirm. **SYNC this folder** copies the current directory (except for the root), and **SYNC folder/** copies the selected folder recursively, including all nested files, dotfiles and `.git`. **Esc** exits. Only the listing is shallow; a selected folder is fully synchronized. Unsupported names containing colons, tabs, or newlines are not listed.

**Browse Linux and sync** works the same way under `~/work`. Existing Linux content can be selected even if the matching Mac path does not exist. The CLI creates any missing Mac **parent directories** and lets Mutagen create the absent file or folder from the Linux copy. If neither side has that path, synchronization is refused. A mismatch between existing Mac and Linux file types is also refused.

The actions available for working copies are **Sync now**, **Pause sync**, **Resume sync**, **Inspect**, **End sync (keep copies)**, and **Release Linux copy**. Pausing, resuming, and ending a session do not remove either copy.

Selecting an already configured path shows its current status and any problem paths, without asking to create another synchronization. A selected subfolder already covered by a parent synchronization uses that existing entry. Only new paths appear in the start confirmation. A parent containing separately synchronized subfolders is blocked with a list of those entries; manage them from **Working copies**.

## Direct CLI shortcuts

```sh
mac-data-sync ls                       # List only the Mac ~/data root (no recursion)
mac-data-sync ls documents             # List only one Mac subdirectory
mac-data-sync pick                     # Navigate Mac folders and select SYNC entries
mac-data-sync browse-local             # Navigate Linux ~/work and publish local-only files
mac-data-sync start project-a          # Sync Mac ~/data/project-a to Linux ~/work/project-a
mac-data-sync start documents/file.md  # Sync an individual file
mac-data-sync check project-a          # Explain existing status or an overlapping setup
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

## Absolute symlinks and existing sessions

New sessions explicitly use Mutagen `--symlink-mode=posix-raw`, supported for the POSIX endpoints used here (macOS to NixOS or WSL2). This preserves absolute and otherwise non-portable symlink **targets as links**, not the files they point to. A link such as `/Users/name/tool` may be dangling or point somewhere unrelated on Linux; inspect it before following or editing through it. Symlinks do not make data outside the selected sync root part of the synchronized archive.

Existing Mutagen sessions retain the symlink mode they were created with. Updating the script alone does **not** repair a session already reporting `invalid symbolic link: target is absolute`.

### Re-create a session with Linux as the authoritative copy

If **preserving Linux content is the priority**, do **not** immediately terminate and re-create a two-way session with divergent Mac and Linux contents. In `two-way-safe`, neither endpoint has priority. Instead, perform a temporary **Linux → Mac** `one-way-replica` seeding pass, verify it, and only then return to two-way sync. The Mac copy, including Mac-only changes/deletions, can be overwritten or removed by this operation. Back up Mac separately if its contents matter.

Run on NixOS/WSL, replacing `project-a` with the exact registered relative path. **Stop any processes writing to either tree until migration is complete**:

```sh
relative=project-a
mac-data-sync status "$relative"
# Copy the Linux tree, including symlinks, outside the synchronized ~/work tree.
backup=$(mktemp -d "$HOME/mac-data-sync-linux-backup.XXXXXXXX")
cp -a -- "$HOME/work/$relative" "$backup/data"
printf 'Linux backup: %s/data\\n' "$backup"
```

Verify that the backup succeeded and contains the expected files; ensure enough free space. The backup is not part of the synchronization. **Do not proceed if it fails**.

```sh
# This ends the old sync session; it does not delete either directory.
mac-data-sync terminate "$relative"

# The Linux path is first (alpha, source); Mac is second (beta, replaceable).
seed="mac-data-reseed-$(printf '%s' "$relative" | sha256sum | cut -c1-20)"
mutagen sync create --name="$seed" --sync-mode=one-way-replica \\
  --no-global-configuration --no-ignore-vcs --symlink-mode=posix-raw \\
  "$HOME/work/$relative" "mac:~/data/$relative"
mutagen sync flush "$seed"
mutagen sync list --long "$seed"
```

**Stop here** unless the seed session is connected, fully scanned, watching, and has no errors/problems. Review the Mac mirror; do not delete the Linux backup. If seeding fails, inspect/fix the seed session rather than running the next commands. Once fully verified:

```sh
mutagen sync terminate "$seed"
mac-data-sync start "$relative"
mac-data-sync status "$relative"
```

The final session is again **bidirectional**. This procedure protects the Linux tree during seeding, but after re-enabling `two-way-safe`, subsequent Mac changes and deletions **can propagate to Linux**. If Linux must remain immutable to all Mac-side changes, do not start a two-way session; instead, retain a Linux-source `one-way-replica` session, accepting that Mac edits won't sync back. Linux backups remain necessary against local deletion, other processes, or mistakes.

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
- The browser displays hidden files and VCS directories only when visiting their immediate parent. Selecting any **parent directory still copies all VCS contents**. Mutagen is invoked with `--no-global-configuration --no-ignore-vcs` so its global ignore rules and VCS exclusion do not silently omit files. This can consume significant Linux disk space and syncing Git metadata while both Macs and Linux run Git operations concurrently may cause conflicts. Avoid concurrent Git writes.
- Starting an existing path or a covered subfolder reports its current status without creating another session. A new parent overlapping separately synchronized subfolders is blocked. Do not start competing sessions for the same subtree from different devices simultaneously.
- SSH paths containing `:`, tabs, newlines, or traversal components `..` cannot be chosen. Unicode and spaces are supported.
- Connection over Tailscale is not restricted to Wi-Fi specifically: any permitted network connection works.
- The UI manages sessions created by `mac-data-sync`, not arbitrary Mutagen sessions.

Upstream references: [Mutagen synchronization](https://mutagen.io/documentation/synchronization/), [Mutagen SSH transport](https://mutagen.io/documentation/transports/ssh/), [macOS Remote Login](https://support.apple.com/guide/mac-help/mchlp1066/mac).
