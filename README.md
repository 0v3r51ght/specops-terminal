# S.O.T — SpecOps Terminal

**Version:** 2.6  
**Author:** 0v3r51ght  
**Platform:** Linux  
**Format:** Standalone Bash application

S.O.T is a menu-driven Linux security toolkit that organises installed command-line tools into mapped, guided actions. It provides workspaces, target scope controls, evidence logging, reports, encrypted notes, package-manager detection and guarded wireless monitor-mode workflows.

> S.O.T does not bundle the third-party security tools listed below. It detects installed tools and can install mapped packages only through supported signed distribution repositories.

## Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Running S.O.T](#running-sot)
- [First-run workflow](#first-run-workflow)
- [Main menu](#main-menu)
- [Package-manager support](#package-manager-support)
- [Workspaces and stored data](#workspaces-and-stored-data)
- [Confirmations and output](#confirmations-and-output)
- [Tool catalogue](#tool-catalogue)
- [Environment options](#environment-options)
- [Troubleshooting](#troubleshooting)
- [Updating](#updating)
- [Uninstalling S.O.T](#uninstalling-sot)
- [Important notes](#important-notes)

## Requirements

- Linux operating system.
- Bash 4.3 or newer.
- Core commands: `awk`, `base64`, `chmod`, `date`, `find`, `grep`, `mkdir`, `mktemp`, `mv`, `sed`, `sort`, `stat`, `tee`, `touch` and `uname`.
- `sudo` or `doas` for approved privileged actions and package installation.
- A terminal with normal interactive input.
- Individual third-party tools only when their mapped actions are used.

Check Bash:

```bash
bash --version
```

S.O.T must be launched as a normal user. Do not run the whole application with `sudo` or as `root`; approved individual operations request privilege when required.

## Installation

### Option 1 — Portable use

Keep the script in its current folder:

```bash
chmod +x sot.sh
./sot.sh --check
./sot.sh
```

### Option 2 — Install for your user

This installs the launcher as `sot` without changing system directories:

```bash
mkdir -p "$HOME/.local/bin"
cp sot.sh "$HOME/.local/bin/sot"
chmod +x "$HOME/.local/bin/sot"
```

Ensure `~/.local/bin` is in your `PATH`:

```bash
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$HOME/.bashrc" ;;
esac
source "$HOME/.bashrc"
```

Then verify and run:

```bash
sot --check
sot
```

### Verify the version

```bash
./sot.sh --version
# or, after user installation:
sot --version
```

## Running S.O.T

On startup, select the profile matching the running distribution:

1. Kali Linux
2. Arch Linux
3. Parrot OS
4. Other Linux distribution — automatic package-manager detection

Kali, Arch and Parrot selections are accepted only when `/etc/os-release` matches the chosen system. Use **Other** for MX Linux, Debian, Ubuntu, Fedora, openSUSE, Alpine, Void and other Linux distributions.

To exit the application, select `Q` from the main menu. In the How to Use and Information menus, `B`, `Q`, `X`, `Back`, `Exit` and `Quit` return to the main menu.

## First-run workflow

1. Open **Workspace / Projects** and create or select a workspace.
2. Open **Scope Manager** and add every permitted domain, IP address, CIDR or MAC address.
3. Select a profile: **Lab**, **CTF** or **Engagement**.
4. Use **Install / Verify Tools** to check any missing utility.
5. Open **Tools by Category**, choose a tool and select a mapped action.
6. Enter the requested target and options, then complete the confirmation prompt.
7. Review **Reports / Evidence** after execution.

Engagement mode enables strict scope and requires a non-empty scope list. Lab and CTF modes leave strict scope disabled unless it is enabled manually.

## Main menu

| Option | Function |
|---|---|
| **Tools by Category** | Browse all mapped utilities and actions by category. |
| **Install / Verify Tools** | Install a mapped package, verify availability or refresh trusted package metadata. |
| **Workspace / Projects** | Create, list and switch private project workspaces. |
| **Scope Manager** | Maintain allowed domains, IPs, CIDRs and MAC addresses; enable strict enforcement. |
| **Professional Bash Terminal** | Open a normal unrestricted interactive Bash shell in the active workspace. Type `exit` or press `Ctrl-D` to return to S.O.T. |
| **Reports / Evidence** | Review history and logs, create HTML reports, export JSON and manage encrypted notes. |
| **Profiles / Modes** | Switch between Lab, CTF and Engagement behaviour. |
| **Status Report** | Show installation status across the mapped catalogue. |
| **Change selected distro** | Return to the distribution selector. |
| **How to use** | Open the detailed built-in guide and complete mapped reference. |
| **Information / Policies** | View package, execution, scope, privacy and session information. |

The Professional Bash Terminal is intentionally unrestricted. S.O.T does not parse, filter, confirm or audit commands entered inside that shell. Commands run with the current user's normal permissions.

## Package-manager support

| System | Installation behaviour |
|---|---|
| **Kali Linux** | Uses an isolated official `kali-rolling` APT source for S.O.T package transactions. |
| **Parrot OS** | Uses isolated official Parrot stable, security and backports APT sources. |
| **Exact Arch Linux** | Uses `pacman` only through a separate locked configuration containing official `core`, `extra` and `multilib`. It does not import additional repositories from the user’s normal pacman configuration. |
| **Other APT systems** | Uses the detected APT setup and mapped APT package names. MX Linux is handled here. |
| **DNF / Zypper / APK / XBPS** | Uses the detected signed binary-package manager and an exact executable-name package candidate. |
| **Portage / Nix / unknown managers** | S.O.T launches and uses already-installed tools, but automatic installation is disabled. |
| **pacman-based non-Arch systems** | S.O.T launches, but automatic package installation is disabled to avoid repository mixing. |

S.O.T does not add third-party repositories, disable signature checks, perform local package builds, pipe downloaded scripts into a shell or remove system packages. If an approved repository does not provide a mapped package, installation stops safely.

## Workspaces and stored data

The default private data directory is:

```text
~/.sot-bash/
```

Each workspace is stored under:

```text
~/.sot-bash/workspaces/<workspace-name>/
```

| Item | Purpose |
|---|---|
| `evidence/` | Full command logs and return information. |
| `reports/` | Generated HTML reports. |
| `exports/` | JSON exports. |
| `notes/` | GPG-encrypted notes. |
| `loot/` | Captures and mapped output files. |
| `tmp/` | Private temporary files. |
| `scope.txt` | Allowed targets for the workspace. |
| `history.tsv` | Command history and evidence-log references. |

Passwords and tokens entered through sensitive placeholders are hidden during entry and redacted from stored metadata/output where detected. Workspace paths are permission-restricted and path traversal or symbolic-link redirection is rejected.

## Confirmations and output

- Passive actions use a normal `y/N` confirmation.
- Active or credential-testing actions require typing `RUN`.
- Network or system-state changes require typing `CHANGE`.
- Monitor-mode start requires `MONITOR`.
- Monitor-mode restoration requires `RESTORE`.

When a mapped action starts, S.O.T clears the screen and shows the selected tool’s result stream. Audit metadata and the full redacted output are saved separately in the active workspace.

## Tool catalogue

The current build contains **93 mapped tool entries** and **205 mapped actions**. A tool must be installed before its actions can run. Some entries may share an underlying executable or package.

### Recon & Enumeration

| Tool | Purpose | Mapped functions |
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
| **theHarvester** | Email, host and subdomain discovery. | DuckDuckGo; Bing; DNSDumpster; Custom source |
| **enum4linux-ng** | SMB/Windows enumeration. | Full enum; Shares/users |
| **smbmap** | SMB share permissions. | Guest enum; Credentialed |
| **nbtscan** | NetBIOS scanning. | Scan range |
| **onesixtyone** | SNMP community checking. | SNMP check |
| **ike-scan** | IKE/VPN discovery. | IKE scan |
| **sslscan** | TLS/SSL configuration scanner. | SSL scan |

### Web Application Testing

| Tool | Purpose | Mapped functions |
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

| Tool | Purpose | Mapped functions |
|---|---|---|
| **lynis** | Linux audit checks. | System audit; Quick audit |
| **unix-privesc-check** | Local privilege escalation checks. | Standard; Detailed |
| **gvm/openvas** | OpenVAS/GVM scanner stack. | Setup; Check setup; Start; Stop |
| **legion** | GUI recon/enumeration. | Launch |
| **searchsploit** | Local Exploit-DB search. | Search; Path; Help |
| **wpscan-vuln** | WordPress vulnerability checks. | Vuln enum; API vuln check |

### Password & Hash Recovery

| Tool | Purpose | Mapped functions |
|---|---|---|
| **john** | Password hash recovery. | Crack hash file; Wordlist mode; Show cracked |
| **hashcat** | GPU/CPU hash recovery. | Dictionary; Show cracked; Benchmark |
| **hashid** | Hash type identification. | Identify string; Identify file |
| **hydra** | Network login testing. | Service test; SSH test; HTTP form template |
| **ncrack** | Network authentication auditing. | Service audit |
| **cewl** | Custom wordlist generation. | Generate; Depth/min length |
| **crunch** | Wordlist generation. | Generate; Output file |
| **seclists** | Security wordlists under /usr/share/seclists. | List root; Find list |
| **wordlists** | Kali wordlists. | List; RockYou path |

### Wireless Assessment

| Tool | Purpose | Mapped functions |
|---|---|---|
| **airmon-ng** | Monitor mode control (shell=False, step-by-step). ON  → check kill, then start monitor. OFF → stop monitor, restart NetworkManager, unblock rfkill. | Monitor mode ON; Monitor mode OFF + restore networking; Check adapters (show interfering procs); Verify interface mode (iw dev); Unblock Wi-Fi (rfkill fallback) |
| **airodump-ng** | Wireless capture / network discovery. | General capture (all channels); Targeted capture (specific BSSID/channel); Band 5 GHz scan |
| **aireplay-ng** | Wireless frame injection and deauthentication. | Deauth (broadcast) — capture handshake; Deauth (targeted client); Test injection capability |
| **aircrack-ng** | WPA/WEP key recovery from captured handshake files. | Crack WPA capture; List capture handshakes; Help / usage |
| **wifite** | Automated wireless auditing UI. | Launch (auto-select interface); Specify interface; WPA-only targets; WPS targets only |
| **kismet** | Wireless / RF monitoring and PCAP capture. | Launch (auto-detect); Specify interface; Headless / daemon mode |
| **reaver** | WPS PIN assessment. | WPS brute-force; Pixie-Dust + Reaver; Resume previous session |
| **pixiewps** | Offline WPS Pixie-Dust attack helper. | Help / options |
| **hcxdumptool** | PMKID/EAPOL capture (no client needed). Requires monitor mode. | PMKID capture (all APs); Target specific BSSID |
| **hcxpcapngtool** | Convert hcxdumptool PMKID/EAPOL captures to hashcat format. | Convert to hashcat 22000; Convert to hashcat 16800 (PMKID) |
| **bettercap-wifi** | Wi-Fi recon and probe sniffing via bettercap. | Wi-Fi recon caplet; Interactive Wi-Fi console |

### Packet Analysis & Spoofing

| Tool | Purpose | Mapped functions |
|---|---|---|
| **wireshark** | Packet analysis GUI. | Launch |
| **tshark** | CLI packet analysis. | Capture; Read pcap; Interfaces |
| **tcpdump** | Packet capture. | Live capture; Save pcap; Host filter |
| **bettercap** | LAN/Wi-Fi assessment console. | Launch interface; Caplet |
| **ettercap** | LAN assessment/sniffing suite. | Text UI; GUI |
| **responder** | LLMNR/NBT-NS/mDNS responder. | Launch |
| **macchanger** | MAC address changes. | Random MAC; Reset MAC |

### Exploitation Frameworks

| Tool | Purpose | Mapped functions |
|---|---|---|
| **metasploit-framework** | Exploit framework launcher. | Launch msfconsole; Resource file; Search module |
| **msfvenom** | Payload options/listing helper. | List payloads; List formats; Payload options |
| **searchsploit** | Local Exploit-DB search. | Search; Mirror/copy path; Help |
| **commix** | Command injection testing. | URL test; Request file |
| **setoolkit** | SET launcher for controlled lab training. | Launch |

### Post-Exploitation & Active Directory

| Tool | Purpose | Mapped functions |
|---|---|---|
| **netexec** | Internal Active Directory assessment toolkit. | SMB check; Credentialed SMB; Help |
| **crackmapexec** | Internal network assessment toolkit. | SMB check; Credentialed SMB |
| **impacket-scripts** | Impacket script collection. | List tools; SMB client help; Secretsdump help |
| **evil-winrm** | WinRM client. | Connect; SSL connect |
| **bloodhound** | Active Directory graph GUI. | Launch GUI |
| **bloodhound-python** | BloodHound collector. | Collect all |
| **ldapdomaindump** | LDAP domain enumeration. | Dump domain |

### Forensics & Reverse Engineering

| Tool | Purpose | Mapped functions |
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

| Tool | Purpose | Mapped functions |
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

| Variable | Effect |
|---|---|
| `SOT_SKIP_INTRO=1` | Skip the boot animation. |
| `SOT_INTRO_DELAY=0.075` | Set seconds between animation frames. Larger values make the animation slower. |
| `NO_COLOR=1` | Disable ANSI colours. |
| `SOT_HOME=/absolute/path` | Store S.O.T configuration and workspaces in another private directory. |

Examples:

```bash
SOT_INTRO_DELAY=0.12 sot
NO_COLOR=1 sot
SOT_HOME="$HOME/Documents/sot-data" sot
```

## Troubleshooting

### S.O.T says a tool is missing

Open **Status Report**, then **Install / Verify Tools**. Refresh trusted metadata and verify the mapped package. A package may not exist under the same name on every distribution.

### Package installation is disabled

This is expected on Portage, Nix, unknown package managers and pacman-based systems that are not exact Arch Linux. Install the required tool using the distribution’s official documentation and repositories, then restart S.O.T.

### A mapped command fails

Review the newest file in the active workspace’s `evidence/` directory. Confirm the target, interface, input file, permissions and installed tool version.

### Monitor mode does not start or restore

The wireless adapter, chipset and driver must support monitor mode. Use `iw dev`, `ip link`, `lsusb` and `rfkill` to identify the adapter. Use S.O.T’s monitor OFF workflow to restore the interface and then restart the normal network service when necessary.

### The internal check fails

Run:

```bash
bash -n ./sot.sh
./sot.sh --check
```

Re-download or restore the original script if it was edited or transferred incorrectly.

## Updating

1. Back up `~/.sot-bash/` or your custom `SOT_HOME`.
2. Replace the old script with the new version.
3. Restore executable permissions with `chmod 700` or reinstall it into `~/.local/bin/sot`.
4. Run `sot --check` before starting a normal session.

Do not overwrite or delete the workspace directory when updating unless you intentionally want to remove stored evidence and configuration.

## Uninstalling S.O.T

S.O.T is a standalone Bash script. Uninstalling it means removing the launcher and, optionally, its private data directory.

### 1. Back up any data you need

```bash
cp -a "$HOME/.sot-bash" "$HOME/sot-backup"
```

Skip this command if no S.O.T data needs to be preserved.

### 2. Remove the launcher

For a user installation:

```bash
rm -f -- "$HOME/.local/bin/sot"
```

For portable use, remove the downloaded file from its folder:

```bash
rm -f -- "sot.sh"
```

### 3. Optionally remove S.O.T data

> **Warning:** This permanently deletes every S.O.T workspace, scope file, evidence log, report, export, encrypted note and cached package-metadata file stored in the default data directory.

Inspect the path first:

```bash
find "$HOME/.sot-bash" -maxdepth 2 -print
```

Then remove it only when the displayed path is correct:

```bash
rm -rf -- "$HOME/.sot-bash"
```

When `SOT_HOME` was customised, remove that exact custom directory instead of `~/.sot-bash`. Never copy an unverified or empty variable into an `rm -rf` command.

### 4. Third-party tools

Uninstalling S.O.T does **not** uninstall Nmap, Wireshark, Metasploit or any other system package installed through the toolkit. Those programs may be shared with other workflows, so S.O.T deliberately leaves them installed. Remove them separately through the distribution’s official package manager only after confirming they are no longer needed.

## Important notes

- Use security-testing functions only on systems and networks where you have permission.
- Scope controls reduce mistakes but do not replace operator responsibility.
- Tool command-line options and output can change between distribution package versions.
- Monitor mode depends on physical hardware and drivers and cannot be guaranteed by the script.
- Run `--check` after editing, moving or updating the application.

---

**S.O.T · SpecOps Terminal v2.6 — Made by 0v3r51ght**
