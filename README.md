# S.O.T — SpecOps Terminal

**Release:** v2.7 — Full Audit Release  
**Author:** 0v3r51ght  
**Platform:** Linux  
**Format:** Standalone Bash application  
**Release filename:** `sot.sh`  
**Mapped catalogue:** 93 tool entries, 205 actions, 10 categories

S.O.T is a menu-driven professional security terminal that organises installed Linux command-line tools into mapped actions. It includes workspaces, strict target scope, evidence logging, reports, encrypted notes, package verification, wireless monitor-mode workflows and a separate unrestricted S.O.T-themed Bash terminal.

> S.O.T does not bundle the third-party tools in the catalogue. It detects installed programs and can install mapped packages only through the supported signed repository paths described below.

## v2.7 release changes

- Lab Mode displays the final rendered command before every mapped `y/N`, `RUN` or `CHANGE` confirmation.
- Monitor Mode ON and OFF display the complete planned command sequence before `MONITOR` or `RESTORE` confirmation.
- The **S.O.T Custom Professional Terminal** is a genuine unrestricted interactive Bash shell, separate from mapped actions.
- The custom terminal retains S.O.T branding, starts inside the active workspace, loads the user's Bash configuration and supports aliases, functions, pipelines, redirection, interpreters and interactive tools.
- Monitor Mode OFF restores managed mode, brings the interface up, restarts recorded network services, unblocks Wi-Fi and verifies the restored interface.
- Passwords and tokens entered through mapped placeholders are hidden and redacted from mapped command previews, evidence logs and history.
- The internal audit validates all 93 entries and 205 mapped actions.

## Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Running S.O.T](#running-sot)
- [Recommended first-run workflow](#recommended-first-run-workflow)
- [Main menu](#main-menu)
- [Mapped commands and confirmations](#mapped-commands-and-confirmations)
- [S.O.T Custom Professional Terminal](#sot-custom-professional-terminal)
- [Wireless monitor mode](#wireless-monitor-mode)
- [Package-manager support](#package-manager-support)
- [Workspaces and stored data](#workspaces-and-stored-data)
- [Reports, evidence and encrypted notes](#reports-evidence-and-encrypted-notes)
- [Tool catalogue](#tool-catalogue)
- [Environment options](#environment-options)
- [Built-in validation](#built-in-validation)
- [Troubleshooting](#troubleshooting)
- [Updating](#updating)
- [Uninstalling](#uninstalling)
- [Release checksum](#release-checksum)

## Requirements

- Linux operating system.
- Bash 4.3 or newer.
- Required core commands: `awk`, `base64`, `cat`, `chmod`, `date`, `find`, `grep`, `mkdir`, `mktemp`, `mv`, `nl`, `rm`, `rmdir`, `sed`, `sleep`, `sort`, `stat`, `tee`, `touch` and `uname`.
- `sudo` or `doas` for mapped actions that require elevated privileges and for supported package installation.
- A normal interactive terminal.
- Individual third-party tools only when their mapped actions are used.

Check Bash:

```bash
bash --version
```

Run S.O.T as the normal user. Do **not** launch the entire toolkit using `sudo` or from a root shell. Mapped operations request privilege only when required.

## Installation

The v2.7 release file is named exactly:

```text
sot.sh
```

All commands below assume the terminal is open in the directory containing `sot.sh`.

### Portable use

```bash
chmod 700 sot.sh
./sot.sh --check
./sot.sh
```

### Install for the current user

```bash
chmod 700 sot.sh
mkdir -p "$HOME/.local/bin"
cp sot.sh "$HOME/.local/bin/sot"
chmod 700 "$HOME/.local/bin/sot"
```

Ensure `~/.local/bin` is in `PATH`:

```bash
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.bashrc" ;;
esac
source "$HOME/.bashrc"
```

Then validate and launch:

```bash
sot --check
sot --version
sot
```

### Install system-wide

```bash
chmod 700 sot.sh
sudo cp sot.sh /usr/local/bin/sot
sudo chmod 755 /usr/local/bin/sot
sot --check
sot
```

The `sudo` commands above only copy and permission the launcher. Run `sot` itself as a normal user.

## Running S.O.T

At startup, choose the profile matching the machine:

1. Kali Linux
2. Arch Linux
3. Parrot OS
4. Other Linux distribution with automatic package-manager detection

Kali, Arch and Parrot selections are accepted only when the running `/etc/os-release` matches. Choose **Other Linux** for MX Linux, Debian, Ubuntu, Fedora, openSUSE, Alpine, Void and other supported environments.

Run the portable file directly:

```bash
./sot.sh --version
./sot.sh --check
./sot.sh
```

After installing it as `sot`, use:

```bash
sot --version
sot --check
sot
```

Use `Q` to leave the main menu. The guide also accepts its displayed return options.

## Recommended first-run workflow

1. Open **Workspace / Projects** and create or select a project workspace.
2. Open **Scope Manager** and add every permitted domain, IP address, IPv4 CIDR or MAC address.
3. Open **Profiles / Modes** and choose Lab, CTF or Engagement.
4. Use **Status Report** to review available tools.
5. Use **Install / Verify Tools** for missing mapped packages.
6. Open **Tools by Category**, select a tool and choose a mapped action.
7. Review the exact command preview and confirmation prompt.
8. Review **Reports / Evidence** after execution.

Engagement Mode requires at least one scope entry and automatically enables strict scope. Lab and CTF disable strict scope unless changed manually.

## Main menu

| Option | Function |
|---|---|
| **Tools by Category** | Browse the complete mapped tool catalogue and select an action. |
| **Install / Verify Tools** | Install a mapped package, verify a tool or refresh supported package metadata. |
| **Workspace / Projects** | Create, list and switch isolated project workspaces. |
| **Scope Manager** | Add, remove and enforce allowed domains, IPs, CIDRs and MAC addresses. |
| **S.O.T Custom Professional Terminal** | Open a separate unrestricted S.O.T-themed interactive Bash shell. |
| **Reports / Evidence** | Review command history and logs, generate HTML, export JSON and manage encrypted notes. |
| **Profiles / Modes** | Choose Lab, CTF or Engagement behaviour. |
| **Status Report** | Check installed/found status across the complete catalogue. |
| **Change selected distro** | Return to distribution selection. |
| **How to use** | Open the detailed in-application guide and full mapped reference. |
| **Information** | Review package, execution, storage, privacy and session behaviour. |

## Mapped commands and confirmations

Mapped actions are generated from fixed templates. S.O.T validates requested placeholders such as targets, URLs, interfaces, ports and input files before rendering the command.

### Lab Mode preview

In Lab Mode, the exact final mapped command is printed **before** any confirmation. Sensitive placeholders such as passwords and tokens appear as redacted markers.

### Confirmation levels

| Action type | Required confirmation |
|---|---|
| Ordinary mapped action | `y/N` |
| Active or credential-testing action | Type `RUN` |
| Network or system-state change | Type `CHANGE` |
| Start monitor mode | Type `MONITOR` |
| Stop monitor mode and restore networking | Type `RESTORE` |

Mapped actions do not open the custom terminal. After confirmation, S.O.T runs the mapped command directly, displays the command's result stream and stores a private evidence record.

The mapped-action path blocks recognised catastrophic disk formatting, root-filesystem deletion, power-control and fork-bomb patterns. This protection applies to mapped actions, not the separate unrestricted terminal.

## S.O.T Custom Professional Terminal

The custom terminal is intended for professional users who want to type commands manually or operate installed tools without using the mapped buttons.

It provides:

- An unrestricted interactive Bash shell.
- S.O.T black-and-green branding and workspace prompt.
- Startup inside the active workspace.
- Loading of the user's readable `~/.bashrc`.
- Normal aliases and Bash functions.
- Pipelines, redirection, command chaining and shell expansion.
- Interactive applications, interpreters and manually operated tools.
- Manual `sudo` or `doas` use when installed.

S.O.T does not parse, block, rewrite, confirm or audit commands entered in this shell. Its temporary startup file is permission-restricted and securely removed after the shell exits. Shell history is disabled for the custom session by unsetting `HISTFILE`.

Return to the toolkit with:

```bash
exit
```

Pressing `Ctrl-D` also closes the custom shell.

## Wireless monitor mode

Monitor-mode functions require a compatible wireless adapter, chipset, driver, `airmon-ng`, `iw` and either `sudo` or `doas`.

Useful checks:

```bash
iw dev
ip link
rfkill list
lsusb
```

### Monitor Mode ON

1. S.O.T lists wireless interfaces.
2. Enter the managed interface, such as `wlan0`.
3. S.O.T verifies that the interface exists, is managed and has a wireless PHY.
4. It displays the planned monitor-mode commands.
5. Type `MONITOR`.
6. S.O.T records active network services, runs `airmon-ng check kill`, starts monitor mode and verifies that a monitor interface appeared on the same PHY.
7. If setup fails, S.O.T attempts to restore managed networking.

### Monitor Mode OFF

1. Select the mapped Monitor Mode OFF action.
2. Confirm the monitor interface, such as `wlan0mon`.
3. Confirm the managed interface to restore, such as `wlan0`.
4. Review the complete restoration command preview.
5. Type `RESTORE`.
6. S.O.T stops monitor mode, restores managed mode when needed, brings the interface up, restarts recorded network services, unblocks Wi-Fi, enables the Wi-Fi radio and verifies managed mode.

Physical monitor-mode operation cannot be guaranteed by the script because support depends on the adapter and driver.

## Package-manager support

| Platform | Automatic installation behaviour |
|---|---|
| **Kali Linux** | Uses an isolated official `kali-rolling` APT source for S.O.T package transactions. |
| **Parrot OS** | Uses isolated official Parrot stable/security/backports APT source definitions. |
| **Exact Arch Linux** | Uses `pacman` only with a separate locked configuration containing official signed `core`, `extra` and `multilib` repositories. It does not use AUR helpers, AUR packages, local builds or `pacman -U`. |
| **Other APT systems** | Uses the detected signed system APT configuration and mapped package names. |
| **DNF / Zypper / APK / XBPS** | Uses the detected signed binary-package manager with supported package candidates. |
| **Portage / Nix / unknown managers** | Installed tools can be used, but automatic installation is disabled. |
| **pacman-based non-Arch systems** | Automatic installation is disabled to prevent repository mixing. |

S.O.T does not disable signature verification, add random third-party repositories, pipe downloaded installers into a shell, perform local package builds or automatically remove packages.

## Workspaces and stored data

Default private data root:

```text
~/.sot-bash/
```

Workspace root:

```text
~/.sot-bash/workspaces/<workspace-name>/
```

| Path | Purpose |
|---|---|
| `evidence/` | Mapped command logs, redacted command metadata, output and exit status. |
| `reports/` | Generated HTML reports. |
| `exports/` | Structured JSON exports. |
| `notes/` | GPG-encrypted workspace notes. |
| `loot/` | Mapped output files and captures. |
| `tmp/` | Private temporary files. |
| `scope.txt` | Allowed target entries. |
| `history.tsv` | Mapped action history and evidence references. |

S.O.T rejects unsafe storage roots, path traversal and workspace redirection through symbolic links. Files are created under a restrictive `umask 077`.

## Reports, evidence and encrypted notes

Each executed mapped action stores:

- Timestamp
- Selected distribution and package manager
- Workspace and working directory
- Redacted rendered command
- Full redacted command output
- Exit status

Reports can be generated as readable HTML. Structured data can be exported as JSON.

Encrypted notes require GPG. S.O.T decrypts into a private temporary file, opens the configured editor, re-encrypts using AES-256 and removes the temporary plaintext file.

## Tool catalogue

The v2.7 release contains **93 mapped tool entries** and **205 mapped actions**.

### Recon & Enumeration

| Tool | Purpose | Mapped actions |
|---|---|---|
| **nmap** | Host discovery, ports, service/version detection. | Quick service scan; Full TCP scan; UDP top ports; Ping sweep; Vuln scripts |
| **rustscan** | Fast port discovery wrapper. | Fast scan; Custom ports |
| **masscan** | High-speed TCP port scanning. | CIDR scan; Single target |
| **netdiscover** | Local ARP discovery. | Passive interface; Range discover |
| **arp-scan** | ARP host discovery. | Localnet; CIDR |
| **whois** | Registry lookup. | Lookup |
| **dig** | DNS query utility. | Any records; Zone transfer check; Reverse lookup |
| **dnsrecon** | DNS enumeration. | Standard enum; Zone transfer; Bruteforce |
| **dnsenum** | DNS and subdomain enum. | Standard; Wordlist |
| **amass** | Subdomain/intel enumeration. | Passive enum; Active enum; Intel |
| **theHarvester** | Email, host, IP, URL and subdomain discovery. | Full discovery; Quick discovery; Deep discovery; DNS resolution |
| **enum4linux-ng** | SMB/Windows enumeration. | Full enum; Shares/users |
| **smbmap** | SMB share permissions. | Guest enum; Credentialed |
| **nbtscan** | NetBIOS scanning. | Scan range |
| **onesixtyone** | SNMP community checking. | SNMP check |
| **ike-scan** | IKE/VPN discovery. | IKE scan |
| **sslscan** | TLS/SSL configuration scanner. | SSL scan |

### Web Application Testing

| Tool | Purpose | Mapped actions |
|---|---|---|
| **whatweb** | Web technology fingerprinting. | Standard; Verbose; Aggressive |
| **wafw00f** | WAF detection. | Detect WAF |
| **nikto** | Web server checks. | Standard; SSL host; Tuning |
| **nuclei** | Template based checks. | Standard; Severity; Templates path |
| **gobuster** | Dir, DNS and vhost discovery. | Directory; Vhost; DNS |
| **feroxbuster** | Recursive content discovery. | Recursive; Extensions |
| **ffuf** | Fast web fuzzer. | Path fuzz; Vhost fuzz; Param fuzz |
| **dirb** | Classic content brute forcing. | Common list |
| **wpscan** | WordPress security assessment. | Enumerate; Plugin enum; Token scan |
| **sqlmap** | SQL injection testing. | URL test; Request file; DBS enum |
| **burpsuite** | Web proxy GUI. | Launch |
| **zaproxy** | OWASP ZAP proxy. | Launch GUI; Daemon help |

### Vulnerability Analysis

| Tool | Purpose | Mapped actions |
|---|---|---|
| **lynis** | Linux audit checks. | System audit; Quick audit |
| **unix-privesc-check** | Local privilege escalation checks. | Standard; Detailed |
| **gvm/openvas** | OpenVAS/GVM scanner stack. | Setup; Check setup; Start; Stop |
| **legion** | GUI recon/enumeration. | Launch |
| **searchsploit** | Local Exploit-DB search. | Search; Path; Help |
| **wpscan-vuln** | WordPress vulnerability checks. | Vuln enum; API vuln check |

### Password & Hash Recovery

| Tool | Purpose | Mapped actions |
|---|---|---|
| **john** | Password hash recovery. | Crack hash file; Wordlist mode; Show cracked |
| **hashcat** | GPU/CPU hash recovery. | Dictionary; Show cracked; Benchmark |
| **hashid** | Hash type identification. | Identify string; Identify file |
| **hydra** | Network login testing. | Service test; SSH test; HTTP form template |
| **ncrack** | Network authentication auditing. | Service audit |
| **cewl** | Custom wordlist generation. | Generate; Depth/min length |
| **crunch** | Wordlist generation. | Generate; Output file |
| **seclists** | Security wordlists under `/usr/share/seclists`. | List root; Find list |
| **wordlists** | Kali wordlists. | List; RockYou path |

### Wireless Assessment

| Tool | Purpose | Mapped actions |
|---|---|---|
| **airmon-ng** | Monitor mode control and restoration. | Monitor ON; Monitor OFF; Check adapters; Verify mode; Unblock Wi-Fi |
| **airodump-ng** | Wireless capture and discovery. | General capture; Targeted capture; 5 GHz scan |
| **aireplay-ng** | Wireless injection testing. | Broadcast deauth; Targeted deauth; Test injection |
| **aircrack-ng** | WPA/WEP recovery from captures. | Crack WPA; List handshakes; Help |
| **wifite** | Automated wireless auditing UI. | Launch; Specify interface; WPA targets; WPS targets |
| **kismet** | Wireless/RF monitoring and capture. | Launch; Specify interface; Headless mode |
| **reaver** | WPS PIN assessment. | WPS test; Pixie-Dust; Resume session |
| **pixiewps** | Offline WPS analysis helper. | Help/options |
| **hcxdumptool** | PMKID/EAPOL capture. | All APs; Target BSSID |
| **hcxpcapngtool** | Convert captures for hashcat. | Convert 22000; Convert 16800 |
| **bettercap-wifi** | Wi-Fi recon via bettercap. | Recon caplet; Interactive console |

### Packet Analysis & Spoofing

| Tool | Purpose | Mapped actions |
|---|---|---|
| **wireshark** | Packet analysis GUI. | Launch |
| **tshark** | CLI packet analysis. | Capture; Read pcap; Interfaces |
| **tcpdump** | Packet capture. | Live capture; Save pcap; Host filter |
| **bettercap** | LAN/Wi-Fi assessment console. | Launch interface; Caplet |
| **ettercap** | LAN assessment/sniffing suite. | Text UI; GUI |
| **responder** | LLMNR/NBT-NS/mDNS responder. | Launch |
| **macchanger** | MAC address changes. | Random MAC; Reset MAC |

### Exploitation Frameworks

| Tool | Purpose | Mapped actions |
|---|---|---|
| **metasploit-framework** | Exploit framework launcher. | Launch msfconsole; Resource file; Search module |
| **msfvenom** | Payload options/listing helper. | List payloads; List formats; Payload options |
| **searchsploit** | Local Exploit-DB search. | Search; Mirror/copy path; Help |
| **commix** | Command injection testing. | URL test; Request file |
| **setoolkit** | SET launcher for controlled lab training. | Launch |

### Post-Exploitation & Active Directory

| Tool | Purpose | Mapped actions |
|---|---|---|
| **netexec** | Internal Active Directory assessment toolkit. | SMB check; Credentialed SMB; Help |
| **crackmapexec** | Internal network assessment toolkit. | SMB check; Credentialed SMB |
| **impacket-scripts** | Impacket script collection. | List tools; SMB client help; Secretsdump help |
| **evil-winrm** | WinRM client. | Connect; SSL connect |
| **bloodhound** | Active Directory graph GUI. | Launch GUI |
| **bloodhound-python** | BloodHound collector. | Collect all |
| **ldapdomaindump** | LDAP domain enumeration. | Dump domain |

### Forensics & Reverse Engineering

| Tool | Purpose | Mapped actions |
|---|---|---|
| **autopsy** | Forensics GUI/web interface. | Launch |
| **sleuthkit** | Filesystem forensics tools. | List files; Filesystem stats; Recover files |
| **binwalk** | Firmware/file analysis. | Analyze; Extract |
| **foremost** | File carving. | Carve |
| **exiftool** | Metadata inspection/removal. | Read metadata; Remove metadata copy |
| **volatility3** | Memory forensics. | Windows info; Plugin list |
| **ghidra** | Reverse engineering GUI. | Launch |
| **radare2** | Reverse engineering CLI. | Analyze binary; Strings |
| **gdb** | Debugger. | Debug file; Quiet |
| **apktool** | APK decode/build. | Decode APK; Build folder |
| **jadx** | Dex/APK Java decompiler. | Decompile APK; GUI |

### Reporting & Operator Utilities

| Tool | Purpose | Mapped actions |
|---|---|---|
| **cherrytree** | Notes GUI. | Launch |
| **faraday** | Pentest IDE/reporting platform. | Launch; Help |
| **eyewitness** | Screenshot/reporting helper. | Single URL; URL file |
| **curl** | HTTP/client utility. | Headers; Verbose TLS; Save response |
| **jq** | JSON parser. | Pretty print; Query |
| **git** | Version control/source retrieval. | Clone repo; Status |
| **tmux** | Terminal multiplexing. | New session; Attach; List sessions |
| **proxychains4** | Run commands through configured proxychains. | HTTP headers through proxy |

## Environment options

### Custom data root

Set `SOT_HOME` to an absolute, non-root, non-symlink path before launch:

```bash
export SOT_HOME="$HOME/Documents/sot-data"
./sot.sh
```

After installing the launcher as `sot`, the last command can instead be `sot`.

Do not set `SOT_HOME` to `/`, a relative path, an empty path or a location reached through an unsafe symbolic link.

### Disable colour

Portable file:

```bash
NO_COLOR=1 ./sot.sh
```

Installed launcher:

```bash
NO_COLOR=1 sot
```

## Built-in validation

Run both checks after downloading, editing, moving or updating the file:

```bash
bash -n sot.sh
./sot.sh --check
```

Expected built-in summary:

```text
S.O.T Bash check · 93 mapped entries · 205 mapped actions · 10 categories
OVERALL: PASS
```

The built-in check validates catalogue structure, action syntax, package-policy rules, destructive mapped-command detection, Lab Mode command previews, custom terminal separation, monitor-mode restoration logic, output filtering, HTML escaping, detailed help and version consistency.

## Troubleshooting

### Permission denied

```bash
chmod 700 sot.sh
./sot.sh
```

### S.O.T refuses to run as root

Exit the root shell and launch it as the normal user:

```bash
exit
./sot.sh
```

### A mapped tool is missing

Open **Status Report**, then use **Install / Verify Tools**. Package availability varies by distribution. S.O.T stops safely when the supported signed repositories do not provide a mapped package.

### A mapped command fails

Open the newest file in the active workspace's `evidence/` directory. Check the target, scope, interface, input file, permissions, installed tool version and exit status.

### Monitor mode does not start

Confirm the adapter and driver support monitor mode:

```bash
iw dev
ip link
rfkill list
lsusb
```

Use the Monitor Mode OFF workflow after a failed test so S.O.T can restore the recorded managed interface and network services.

### Wi-Fi does not return after monitor mode

Run Monitor Mode OFF and enter the actual monitor and managed interfaces. If a service still fails, inspect the evidence log and manually check:

```bash
sudo systemctl restart NetworkManager
sudo rfkill unblock wifi
nmcli radio wifi on
iw dev
```

The exact network manager may be `iwd`, `wpa_supplicant` or a distribution-specific service instead of NetworkManager.

### The custom terminal does not load an alias or function

Confirm it is defined in a readable `~/.bashrc`. The custom terminal loads that file before reapplying the S.O.T prompt.

### Internal check fails

```bash
bash -n sot.sh
./sot.sh --check
```

Restore an unmodified copy if syntax or integrity checks fail after manual editing.

## Updating

1. Back up `~/.sot-bash/` or the configured `SOT_HOME` directory.
2. Replace the old `sot.sh` file with the new release.
3. Restore executable permissions.
4. Run `--check` before starting a normal session.

Example portable-file update check:

```bash
chmod 700 sot.sh
bash -n sot.sh
./sot.sh --check
```

Example user-install update:

```bash
cp -a "$HOME/.sot-bash" "$HOME/sot-backup"
chmod 700 sot.sh
cp sot.sh "$HOME/.local/bin/sot"
chmod 700 "$HOME/.local/bin/sot"
sot --check
```

Do not delete the workspace directory during an update unless its evidence, reports, scope and notes are intentionally being removed.

## Uninstalling

### Remove a user installation

```bash
rm -f -- "$HOME/.local/bin/sot"
```

### Remove a system-wide installation

```bash
sudo rm -f -- /usr/local/bin/sot
```

### Optionally remove S.O.T data

Inspect it first:

```bash
find "$HOME/.sot-bash" -maxdepth 2 -print
```

Only after confirming the exact path:

```bash
rm -rf -- "$HOME/.sot-bash"
```

When using a custom `SOT_HOME`, remove that exact verified directory instead. Removing S.O.T does not remove third-party tools installed on the system.

## Release checksum

Verify the release file using its correct filename:

```bash
sha256sum sot.sh
```

Expected SHA-256 for the audited v2.7 script contents:

```text
74f40d9494efd1d7ae68b91fa8f0c2eb95fc02bf833914ed34e8d21b0c6d20f2
```

Renaming the script to `sot.sh` does not alter its checksum. The expected value only matches an otherwise unmodified audited v2.7 release.

## Important notes

- Use mapped security-testing functions only on systems and networks where you have permission.
- Scope enforcement reduces mistakes but does not replace operator responsibility.
- Third-party command-line options and package availability can differ by version and distribution.
- Hardware-specific wireless behaviour cannot be fully validated without the target adapter and driver.
- The custom terminal is unrestricted and executes commands with the current user's permissions.
- Run `--check` after every manual modification or transfer.

---

**S.O.T · SpecOps Terminal v2.7 — Made by 0v3r51ght**
