# Windows support: Mac archive -> Windows working copies

**Supported layout:** macOS stays the archive at `~/data`, and **Windows is another working client**, independent from NixOS. You can browse the same Mac files from both devices.

Windows uses **WSL2 Ubuntu** to run the same English-language fzf interface, SSH client, and Mutagen engine as NixOS. Windows files are accessible from Explorer through the WSL network path. This avoids maintaining a separate, potentially divergent native PowerShell implementation of the synchronization and release safety checks.

```text
macOS: ~/data/project-a
   ├── NixOS:   /home/hotaru/work/project-a
   └── Windows: \\wsl.localhost\Ubuntu\home\<wsl-user>\work\project-a
```

The Windows copy lives inside WSL at `~/work`. It is not a direct `C:\work` folder, but Windows editors can open the UNC path. For Linux-based builds, keeping the files in the native WSL filesystem is much faster than `/mnt/c`. The Mac files remain the archive, and all selected directory descendants (including hidden files and `.git`) are synchronized.

## 1. Prerequisites

- Windows 10/11 with [WSL2](https://learn.microsoft.com/en-us/windows/wsl/install) and Ubuntu or Debian.
- Tailscale on the Windows machine and Mac, in the same tailnet. Verify that WSL can reach the Mac's Tailscale address before attempting a sync. WSL networking arrangements differ by Windows version.
- Mac Remote Login enabled for the intended Mac user (System Settings > General > Sharing > Remote Login).
- A separate WSL SSH key authorized on the Mac. **Do not copy your NixOS private key to Windows.**

In an administrator PowerShell terminal, install WSL if necessary:

```powershell
wsl --install -d Ubuntu
# Reboot if requested, and launch Ubuntu once to create your Linux account.
```

Clone the dotfiles repository **in Windows** and check out the PR branch until it has been merged:

```powershell
git clone https://github.com/Natsu-B/dotfiles.git
cd dotfiles
git fetch origin feat/mac-data-sync-over-tailscale
git switch feat/mac-data-sync-over-tailscale
```

After the PR is merged, just use the main branch.

## 2. Install once (PowerShell)

Use the Mac's Tailscale IP or resolvable MagicDNS name and the Mac account's **short user name**:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\windows\Install-MacDataSync.ps1 -Distribution Ubuntu -MacHost 100.x.y.z -MacUser YOUR_MAC_USER
```

The installer runs `windows/setup-wsl.sh` inside Ubuntu. It installs Ubuntu packages (`fzf`, `jq`, `lsof`, `openssh-client`), a pinned Mutagen v0.18.1 release (verified against its published SHA256SUMS), and the repository's English TUI/CLI. No Git files are installed into the Mac archive.

By default, it also creates a **Windows per-user Startup shortcut** named `Mac Data Sync (WSL)`, which launches a hidden WSL keeper at Windows login. That process keeps WSL running and retries the Mutagen daemon once a minute, so existing sessions can resume automatically when SSH/Tailscale becomes available. **This keeps the WSL virtual machine running while logged in**, consuming some memory and battery. Use `-SkipStartup` during setup if you prefer to sync only while WSL is open.

If you omit `-MacHost` and `-MacUser`, configure a `Host mac` entry manually inside Ubuntu's `~/.ssh/config`.

## 3. Authorize Windows on the Mac

In PowerShell, generate a dedicated key in Ubuntu if it doesn't exist:

```powershell
wsl -d Ubuntu --exec bash -lc 'test -f ~/.ssh/id_ed25519.pub || ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519'
wsl -d Ubuntu --exec bash -lc 'cat ~/.ssh/id_ed25519.pub'
```

Append the **public key** to the Mac user's `~/.ssh/authorized_keys` with the correct permissions. Never copy the private key. A passphrase-protected key requires an SSH agent/unlock arrangement for unattended background sync.

Then test the connection from WSL:

```powershell
wsl -d Ubuntu --exec bash -lc 'ssh mac "ls ~/data"'
```

Verify the Mac host key on the first connection. If the connection fails, check Tailscale reachability from **inside WSL**, SSH authorization on the Mac, and the configured `Host mac` alias. Do not disable host-key verification to fix a connection failure.

## 4. Use the English interface on Windows

From the checkout:

```powershell
.\windows\MacDataSync.ps1
.\windows\MacDataSync.ps1 start project-a
.\windows\MacDataSync.ps1 release project-a
.\windows\MacDataSync.ps1 -OpenWork
```

Or use the stable launcher installed into your user profile:

```powershell
& "$env:LOCALAPPDATA\MacDataSync\MacDataSync.ps1"
& "$env:LOCALAPPDATA\MacDataSync\MacDataSync.ps1" -OpenWork
```

The interface is unchanged between NixOS and Windows:

| Menu | Behavior |
| --- | --- |
| Browse Mac and add | Pick Mac files or entire folders recursively |
| Working copies | View status and usage; sync, pause, resume, inspect, terminate |
| Storage cleanup | Safely remove **only the WSL working copy** after verification |
| Conflicts and errors | Inspect unhealthy or disconnected sessions |

Windows File Explorer can open the WSL working copy with `-OpenWork`, or by navigating to:

```text
\\wsl.localhost\Ubuntu\home\<wsl-user>\work
```

The WSL distribution must be running for Explorer access. Do not edit WSL's hidden underlying virtual disk files directly through `AppData`.

## 5. Safety and platform notes

- **Do not edit the same files concurrently on NixOS and Windows.** Two independent Mutagen sessions target the same Mac archive and can conflict. Finish or pause work on one client before editing on the other; check for conflicts.
- Ordinary file deletion inside an active two-way sync may delete the corresponding file on the Mac. Use **Release Linux copy** on Windows when you want to reclaim WSL disk space. It checks both sides and requires explicit confirmation.
- Stopping synchronization does **not** remove either copy; no copies are automatically evicted.
- The Windows keeper runs at logon. It does not run while the PC is powered off, and manually shutting down WSL also terminates the keeper until the next logon or manual restart.
- **Without the Startup shortcut**, background sync is only available while the WSL instance stays running. A successful installation is not a guarantee that a sleeping or stopped WSL VM can sync.
- Native Windows filesystem semantics can differ from macOS/Linux (permissions, symlinks, case sensitivity). The default WSL ext4 storage avoids most of these issues. Files copied through Explorer or external applications should still be checked for conflicts.
- The installer supports WSL Ubuntu/Debian and x86_64/arm64. Other distributions or architectures may require manual installation.

Native PowerShell synchronization without WSL and using Windows as the **archive** rather than the working client are separate designs, not implemented by this PR.

## Links

- [Windows WSL basic commands](https://learn.microsoft.com/en-us/windows/wsl/basic-commands)
- [Access WSL working files from Explorer](https://learn.microsoft.com/en-us/windows/wsl/filesystems)
- [Mutagen SSH transport](https://mutagen.io/documentation/transports/ssh/)
- [Mac/NixOS and Windows CLI guide](MAC-DATA-SYNC.md)
