#!/usr/bin/env bash
# S.O.T · SpecOps Terminal v2.6 — AUDITED RELEASE
# Made by 0v3r51ght
# Linux targets: Kali Linux, Arch Linux, Parrot OS, and Other Linux distributions.
# Package policy: signed repositories only; Arch installs use pacman with a locked official configuration.

set -o pipefail
umask 077
exec 3<&0

VERSION="2.6"
APP_NAME="S.O.T · SpecOps Terminal"
AUTHOR="0v3r51ght"
SOT_HOME="${SOT_HOME:-$HOME/.sot-bash}"
CONFIG_FILE="$SOT_HOME/config"
WORKSPACES_DIR="$SOT_HOME/workspaces"
CURRENT_DISTRO=""
DETECTED_DISTRO="unknown"
DETECTED_DISTRO_NAME="Unknown Linux"
DETECTED_ID_LIKE=""
PACKAGE_MANAGER="unknown"
PACKAGE_MANAGER_CMD=""
ACTIVE_WORKSPACE="default"
ACTIVE_MODE="lab"
STRICT_SCOPE="0"
CWD="$PWD"

# ── Colours ──────────────────────────────────────────────────────────────────
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    RESET=$'\033[0m'; BOLD=$'\033[1m'; DIM=$'\033[2m'
    DARK=$'\033[38;2;0;75;0m'; MID=$'\033[38;2;0;145;0m'
    GREEN=$'\033[38;2;0;210;25m'; NEON=$'\033[38;2;0;255;65m'
    WHITE=$'\033[38;2;221;255;221m'; GREY=$'\033[38;2;100;150;100m'
    RED=$'\033[38;2;255;85;85m'; ORANGE=$'\033[38;2;190;255;40m'
else
    RESET=""; BOLD=""; DIM=""; DARK=""; MID=""; GREEN=""; NEON=""
    WHITE=""; GREY=""; RED=""; ORANGE=""
fi

cleanup() {
    if [[ -t 1 ]]; then
        printf '\033[?25h%s' "$RESET" 2>/dev/null || true
    fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

clear_screen() {
    if [[ -t 1 ]] && command -v clear >/dev/null 2>&1; then clear; else printf '\n\n'; fi
}

pause() { read -r -u 3 -p "Press Enter to continue..." _ || true; }
info()  { printf '%b\n' "${GREEN}[i]${RESET} $*"; }
ok()    { printf '%b\n' "${NEON}[✓]${RESET} $*"; }
warn()  { printf '%b\n' "${ORANGE}[!]${RESET} $*"; }
error() { printf '%b\n' "${RED}[✗]${RESET} $*" >&2; }

safe_mkdir() {
    local path=$1 owner
    [[ ! -L "$path" ]] || { error "Refusing symbolic-link directory: $path"; return 1; }
    if [[ -e "$path" && ! -d "$path" ]]; then
        error "Expected a directory but found another file type: $path"
        return 1
    fi
    mkdir -p -- "$path" || { error "Could not create: $path"; return 1; }
    [[ ! -L "$path" ]] || { error "Refusing symbolic-link directory: $path"; return 1; }
    owner=$(stat -c '%u' "$path" 2>/dev/null || printf '')
    [[ "$owner" == "$EUID" ]] || { error "Directory must be owned by the current user: $path"; return 1; }
}

safe_relative_path() {
    local value=$1 part
    local -a parts=()
    [[ -n "$value" && "$value" != /* ]] || return 1
    contains_control_chars "$value" && return 1
    IFS='/' read -r -a parts <<< "$value"
    ((${#parts[@]})) || return 1
    for part in "${parts[@]}"; do
        [[ -n "$part" && "$part" != . && "$part" != .. ]] || return 1
    done
}

safe_child_path() {
    local base=$1 relative=$2 current part
    local -a parts=()
    safe_relative_path "$relative" || { error "Unsafe relative path: $relative"; return 1; }
    [[ -d "$base" && ! -L "$base" ]] || { error "Unsafe base directory: $base"; return 1; }
    current=$base
    IFS='/' read -r -a parts <<< "$relative"
    for part in "${parts[@]}"; do
        current="$current/$part"
        [[ ! -L "$current" ]] || { error "Refusing symbolic-link path component: $current"; return 1; }
    done
    printf '%s' "$current"
}

safe_mkdir_under() {
    local base=$1 relative=$2 current part
    local -a parts=()
    safe_relative_path "$relative" || { error "Unsafe relative directory: $relative"; return 1; }
    [[ -d "$base" && ! -L "$base" ]] || { error "Unsafe base directory: $base"; return 1; }
    current=$base
    IFS='/' read -r -a parts <<< "$relative"
    for part in "${parts[@]}"; do
        current="$current/$part"
        safe_mkdir "$current" || return 1
    done
    printf '%s' "$current"
}

private_temp_file() {
    local dir=$1 prefix=$2 suffix=${3:-} tmp final
    [[ -d "$dir" && ! -L "$dir" ]] || { error "Unsafe temporary-file directory: $dir"; return 1; }
    prefix=$(safe_name "$prefix")
    tmp=$(mktemp "$dir/${prefix}.XXXXXX") || return 1
    final="${tmp}${suffix}"
    if [[ -n "$suffix" ]]; then
        mv -f -- "$tmp" "$final" || { rm -f -- "$tmp"; return 1; }
    fi
    chmod 600 -- "$final" || { rm -f -- "$final"; return 1; }
    printf '%s' "$final"
}

list_workspace_names() {
    local path
    for path in "$WORKSPACES_DIR"/*; do
        [[ -d "$path" && ! -L "$path" ]] || continue
        printf '%s\n' "${path##*/}"
    done | sort
}

list_evidence_logs() {
    local path
    for path in "$(evidence_dir)"/*; do
        [[ -f "$path" && ! -L "$path" ]] || continue
        printf '%s\n' "${path##*/}"
    done | sort -r
}

ensure_private_file() {
    local path=$1 owner parent
    parent=${path%/*}
    safe_mkdir "$parent" || return 1
    [[ ! -L "$path" ]] || { error "Refusing symbolic-link file: $path"; return 1; }
    if [[ -e "$path" ]]; then
        [[ -f "$path" ]] || { error "Expected a regular file: $path"; return 1; }
        owner=$(stat -c '%u' "$path" 2>/dev/null || printf '')
        [[ "$owner" == "$EUID" ]] || { error "File must be owned by the current user: $path"; return 1; }
    else
        (umask 077; : > "$path") || { error "Could not create file: $path"; return 1; }
    fi
    chmod 600 -- "$path" || return 1
}

validate_storage_root() {
    local owner parent
    [[ "$SOT_HOME" == /* ]] || { error "SOT_HOME must be an absolute path."; return 1; }
    case "$SOT_HOME/" in
        *'/../'*|*'/./'*|*'//'*) error "SOT_HOME contains unsafe path components: $SOT_HOME"; return 1 ;;
    esac
    case "$SOT_HOME" in
        /|/bin|/boot|/dev|/etc|/lib|/lib64|/proc|/root|/run|/sbin|/sys|/usr|/var)
            error "Refusing unsafe SOT_HOME path: $SOT_HOME"; return 1 ;;
    esac
    [[ ! -L "$SOT_HOME" ]] || { error "SOT_HOME cannot be a symbolic link."; return 1; }
    if [[ -e "$SOT_HOME" ]]; then
        [[ -d "$SOT_HOME" ]] || { error "SOT_HOME is not a directory."; return 1; }
        owner=$(stat -c '%u' "$SOT_HOME" 2>/dev/null || printf '')
        [[ "$owner" == "$EUID" ]] || { error "SOT_HOME must be owned by the current user."; return 1; }
    else
        parent=${SOT_HOME%/*}; [[ -n "$parent" ]] || parent=/
        [[ -d "$parent" && -w "$parent" ]] || { error "SOT_HOME parent is not writable: $parent"; return 1; }
    fi
}

logo() {
    printf '%b\n' "${NEON}${BOLD}███████╗ ██████╗ ████████╗${RESET}"
    printf '%b\n' "${GREEN}${BOLD}██╔════╝██╔═══██╗╚══██╔══╝${RESET}"
    printf '%b\n' "${GREEN}${BOLD}███████╗██║   ██║   ██║   ${RESET}"
    printf '%b\n' "${MID}${BOLD}╚════██║██║   ██║   ██║   ${RESET}"
    printf '%b\n' "${MID}${BOLD}███████║╚██████╔╝   ██║   ${RESET}"
    printf '%b\n' "${DARK}${BOLD}╚══════╝ ╚═════╝    ╚═╝   ${RESET}"
    printf '%b\n' "${WHITE}${BOLD}S.O.T SpecOps Terminal v${VERSION}${RESET}"
    printf '%b\n' "${GREY}Made by ${AUTHOR}${RESET}"
}

boot_animation() {
    [[ -n "${SOT_SKIP_INTRO:-}" || ! -t 1 ]] && return 0
    local width lines frame row col out delay chars='01▓▒░SOT#$%&'
    delay=${SOT_INTRO_DELAY:-0.075}
    [[ "$delay" =~ ^0\.[0-9]{1,3}$|^[1-9][0-9]*(\.[0-9]{1,3})?$ ]] || delay=0.075
    width=$(tput cols 2>/dev/null || printf '80')
    lines=$(tput lines 2>/dev/null || printf '24')
    (( width > 90 )) && width=90
    (( lines > 16 )) && lines=16
    (( width < 30 )) && width=30
    printf '\033[?25l'
    for frame in 1 2 3 4 5 6 7 8; do
        out=$'\033[H'
        for ((row=0; row<lines; row++)); do
            for ((col=0; col<width; col++)); do
                if (( RANDOM % 8 == 0 )); then
                    out+="${chars:RANDOM%${#chars}:1}"
                else
                    out+=' '
                fi
            done
            out+=$'\n'
        done
        printf '%b' "${GREEN}${out}${RESET}"
        sleep "$delay"
    done
    printf '\033[?25h'
}

header() {
    clear_screen
    logo
    printf '%b\n\n' "${DARK}────────────────────────────────────────────────────────────────────────${RESET}"
    printf '%b\n' "${GREY}Distro:${RESET} ${WHITE}$(distro_display)${RESET}  ${GREY}Workspace:${RESET} ${WHITE}${ACTIVE_WORKSPACE}${RESET}  ${GREY}Mode:${RESET} ${WHITE}${ACTIVE_MODE}${RESET}"
    printf '%b\n\n' "${DARK}────────────────────────────────────────────────────────────────────────${RESET}"
}

# ── Tool database ─────────────────────────────────────────────────────────────
declare -a CATEGORIES=()
declare -A CATEGORY_TOOLS=()
declare -A TOOL_DISPLAY=()
declare -A TOOL_PKG_APT=()
declare -A TOOL_PKG_ARCH=()
declare -A TOOL_BIN=()
declare -A TOOL_HINT=()
declare -A TOOL_FUNC_COUNT=()
declare -A TOOL_FUNC_LABEL=()
declare -A TOOL_FUNC_CMD_B64=()
declare -A RESOLVED_PACKAGE=()

register_category() {
    local cat=$1
    CATEGORIES+=("$cat")
    CATEGORY_TOOLS["$cat"]=""
}

register_tool() {
    local cat=$1 name=$2 apt_pkg=$3 arch_candidates=$4 bin=$5 hint=$6 display=${7:-$2}
    CATEGORY_TOOLS["$cat"]+="$name"$'\n'
    TOOL_DISPLAY["$name"]=$display
    TOOL_PKG_APT["$name"]=$apt_pkg
    TOOL_PKG_ARCH["$name"]=$arch_candidates
    TOOL_BIN["$name"]=$bin
    TOOL_HINT["$name"]=$hint
    TOOL_FUNC_COUNT["$name"]=0
}

register_func() {
    local tool=$1 label=$2 cmd_b64=$3 n
    n=$(( ${TOOL_FUNC_COUNT["$tool"]:-0} + 1 ))
    TOOL_FUNC_COUNT["$tool"]=$n
    TOOL_FUNC_LABEL["$tool|$n"]=$label
    TOOL_FUNC_CMD_B64["$tool|$n"]=$cmd_b64
}

decode_b64() { printf '%s' "$1" | base64 -d 2>/dev/null; }
tool_label() { printf '%s' "${TOOL_DISPLAY[$1]:-$1}"; }

tool_exists() {
    local key=$1
    [[ -n "${TOOL_HINT["$key"]+present}" ]]
}

# __DATA_START__
register_category 'Recon & Enumeration'
register_tool 'Recon & Enumeration' nmap nmap nmap nmap 'Host discovery, ports, service/version detection.'
register_func nmap 'Quick service scan' bm1hcCAtc0MgLXNWIHt0YXJnZXR9
register_func nmap 'Full TCP scan' bm1hcCAtcC0gLS1taW4tcmF0ZSAzMDAwIHt0YXJnZXR9
register_func nmap 'UDP top ports' c3VkbyBubWFwIC1zVSAtLXRvcC1wb3J0cyA1MCB7dGFyZ2V0fQ==
register_func nmap 'Ping sweep' bm1hcCAtc24ge2NpZHJ9
register_func nmap 'Vuln scripts' bm1hcCAtLXNjcmlwdCB2dWxuIHt0YXJnZXR9
register_tool 'Recon & Enumeration' rustscan rustscan rustscan rustscan 'Fast port discovery wrapper.'
register_func rustscan 'Fast scan' cnVzdHNjYW4gLWEge3RhcmdldH0gLS0gLXNW
register_func rustscan 'Custom ports' cnVzdHNjYW4gLWEge3RhcmdldH0gLXIge3BvcnRzfSAtLSAtc1Y=
register_tool 'Recon & Enumeration' masscan masscan masscan masscan 'High-speed TCP port scanning.'
register_func masscan 'CIDR scan' c3VkbyBtYXNzY2FuIHtjaWRyfSAtcCB7cG9ydHN9IC0tcmF0ZSB7cmF0ZX0=
register_func masscan 'Single target' c3VkbyBtYXNzY2FuIHt0YXJnZXR9IC1wIHtwb3J0c30gLS1yYXRlIHtyYXRlfQ==
register_tool 'Recon & Enumeration' netdiscover netdiscover netdiscover netdiscover 'Local ARP discovery.'
register_func netdiscover 'Passive interface' c3VkbyBuZXRkaXNjb3ZlciAtcCAtaSB7aWZhY2V9
register_func netdiscover 'Range discover' c3VkbyBuZXRkaXNjb3ZlciAtciB7Y2lkcn0=
register_tool 'Recon & Enumeration' arp-scan arp-scan arp-scan arp-scan 'ARP host discovery.'
register_func arp-scan Localnet c3VkbyBhcnAtc2NhbiAtLWxvY2FsbmV0IC1JIHtpZmFjZX0=
register_func arp-scan CIDR c3VkbyBhcnAtc2NhbiB7Y2lkcn0=
register_tool 'Recon & Enumeration' whois whois whois whois 'Registry lookup.'
register_func whois Lookup d2hvaXMge3RhcmdldH0=
register_tool 'Recon & Enumeration' dig dnsutils 'bind dnsutils' dig 'DNS query utility.'
register_func dig 'Any records' ZGlnIHtkb21haW59IGFueSArbm9hbGwgK2Fuc3dlcg==
register_func dig 'Zone transfer check' ZGlnIGF4ZnIgQHtuYW1lc2VydmVyfSB7ZG9tYWlufQ==
register_func dig 'Reverse lookup' ZGlnIC14IHtpcH0gK3Nob3J0
register_tool 'Recon & Enumeration' dnsrecon dnsrecon dnsrecon dnsrecon 'DNS enumeration.'
register_func dnsrecon 'Standard enum' ZG5zcmVjb24gLWQge2RvbWFpbn0gLWE=
register_func dnsrecon 'Zone transfer' ZG5zcmVjb24gLWQge2RvbWFpbn0gLXQgYXhmcg==
register_func dnsrecon Bruteforce ZG5zcmVjb24gLWQge2RvbWFpbn0gLUQge3dvcmRsaXN0fSAtdCBicnQ=
register_tool 'Recon & Enumeration' dnsenum dnsenum dnsenum dnsenum 'DNS and subdomain enum.'
register_func dnsenum Standard ZG5zZW51bSB7ZG9tYWlufQ==
register_func dnsenum Wordlist ZG5zZW51bSAtZiB7d29yZGxpc3R9IHtkb21haW59
register_tool 'Recon & Enumeration' amass amass amass amass 'Subdomain/intel enumeration.'
register_func amass 'Passive enum' YW1hc3MgZW51bSAtcGFzc2l2ZSAtZCB7ZG9tYWlufQ==
register_func amass 'Active enum' YW1hc3MgZW51bSAtYWN0aXZlIC1kIHtkb21haW59
register_func amass Intel YW1hc3MgaW50ZWwgLWQge2RvbWFpbn0gLXdob2lz
register_tool 'Recon & Enumeration' theHarvester theharvester theharvester theHarvester 'All-source email, host, IP, URL and subdomain discovery with automatic fallbacks.'
register_func theHarvester 'Full discovery · all sources + fallback' X190aGVoYXJ2ZXN0ZXJfZnVsbF9f
register_func theHarvester 'Quick discovery · all sources + fallback' X190aGVoYXJ2ZXN0ZXJfcXVpY2tfXw==
register_func theHarvester 'Deep discovery · all sources + fallback' X190aGVoYXJ2ZXN0ZXJfZGVlcF9f
register_func theHarvester 'Full discovery + DNS resolution + fallback' X190aGVoYXJ2ZXN0ZXJfcmVzb2x2ZV9f
register_tool 'Recon & Enumeration' enum4linux-ng enum4linux-ng enum4linux-ng enum4linux-ng 'SMB/Windows enumeration.'
register_func enum4linux-ng 'Full enum' ZW51bTRsaW51eC1uZyAtQSB7dGFyZ2V0fQ==
register_func enum4linux-ng Shares/users ZW51bTRsaW51eC1uZyAtUyAtVSB7dGFyZ2V0fQ==
register_tool 'Recon & Enumeration' smbmap smbmap smbmap smbmap 'SMB share permissions.'
register_func smbmap 'Guest enum' c21ibWFwIC1IIHt0YXJnZXR9
register_func smbmap Credentialed c21ibWFwIC1IIHt0YXJnZXR9IC11IHt1c2VybmFtZX0gLXAge3Bhc3N3b3JkfQ==
register_tool 'Recon & Enumeration' nbtscan nbtscan nbtscan nbtscan 'NetBIOS scanning.'
register_func nbtscan 'Scan range' bmJ0c2NhbiB7Y2lkcn0=
register_tool 'Recon & Enumeration' onesixtyone onesixtyone onesixtyone onesixtyone 'SNMP community checking.'
register_func onesixtyone 'SNMP check' b25lc2l4dHlvbmUgLWMge2NvbW11bml0eV9maWxlfSB7dGFyZ2V0fQ==
register_tool 'Recon & Enumeration' ike-scan ike-scan ike-scan ike-scan 'IKE/VPN discovery.'
register_func ike-scan 'IKE scan' c3VkbyBpa2Utc2NhbiB7dGFyZ2V0fQ==
register_tool 'Recon & Enumeration' sslscan sslscan sslscan sslscan 'TLS/SSL configuration scanner.'
register_func sslscan 'SSL scan' c3Nsc2NhbiB7aG9zdH0=
register_category 'Web Application Testing'
register_tool 'Web Application Testing' whatweb whatweb whatweb whatweb 'Web technology fingerprinting.'
register_func whatweb Standard d2hhdHdlYiB7dXJsfQ==
register_func whatweb Verbose d2hhdHdlYiAtdiB7dXJsfQ==
register_func whatweb Aggressive d2hhdHdlYiAtYSAzIHt1cmx9
register_tool 'Web Application Testing' wafw00f wafw00f wafw00f wafw00f 'WAF detection.'
register_func wafw00f 'Detect WAF' d2FmdzAwZiB7dXJsfQ==
register_tool 'Web Application Testing' nikto nikto nikto nikto 'Web server checks.'
register_func nikto Standard bmlrdG8gLWgge3VybH0=
register_func nikto 'SSL host' bmlrdG8gLXNzbCAtaCB7aG9zdH0=
register_func nikto Tuning bmlrdG8gLWgge3VybH0gLVR1bmluZyB7dHVuaW5nfQ==
register_tool 'Web Application Testing' nuclei nuclei nuclei nuclei 'Template based checks.'
register_func nuclei Standard bnVjbGVpIC11IHt1cmx9
register_func nuclei Severity bnVjbGVpIC11IHt1cmx9IC1zZXZlcml0eSB7c2V2ZXJpdHl9
register_func nuclei 'Templates path' bnVjbGVpIC11IHt1cmx9IC10IHt0ZW1wbGF0ZXN9
register_tool 'Web Application Testing' gobuster gobuster gobuster gobuster 'Dir, DNS and vhost discovery.'
register_func gobuster Directory Z29idXN0ZXIgZGlyIC11IHt1cmx9IC13IHt3b3JkbGlzdH0=
register_func gobuster Vhost Z29idXN0ZXIgdmhvc3QgLXUge3VybH0gLXcge3dvcmRsaXN0fQ==
register_func gobuster DNS Z29idXN0ZXIgZG5zIC1kIHtkb21haW59IC13IHt3b3JkbGlzdH0=
register_tool 'Web Application Testing' feroxbuster feroxbuster feroxbuster feroxbuster 'Recursive content discovery.'
register_func feroxbuster Recursive ZmVyb3hidXN0ZXIgLXUge3VybH0gLXcge3dvcmRsaXN0fQ==
register_func feroxbuster Extensions ZmVyb3hidXN0ZXIgLXUge3VybH0gLXcge3dvcmRsaXN0fSAteCB7ZXh0ZW5zaW9uc30=
register_tool 'Web Application Testing' ffuf ffuf ffuf ffuf 'Fast web fuzzer.'
register_func ffuf 'Path fuzz' ZmZ1ZiAtdSB7dXJsfS9GVVpaIC13IHt3b3JkbGlzdH0=
register_func ffuf 'Vhost fuzz' ZmZ1ZiAtdSB7dXJsfSAtSCBIb3N0OlwgRlVaWi57ZG9tYWlufSAtdyB7d29yZGxpc3R9
register_func ffuf 'Param fuzz' ZmZ1ZiAtdSB7dXJsfVw/RlVaWj10ZXN0IC13IHt3b3JkbGlzdH0=
register_tool 'Web Application Testing' dirb dirb dirb dirb 'Classic content brute forcing.'
register_func dirb 'Common list' ZGlyYiB7dXJsfSB7d29yZGxpc3R9
register_tool 'Web Application Testing' wpscan wpscan wpscan wpscan 'WordPress security assessment.'
register_func wpscan Enumerate d3BzY2FuIC0tdXJsIHt1cmx9IC0tZW51bWVyYXRlIGFwLGF0LHU=
register_func wpscan 'Plugin enum' d3BzY2FuIC0tdXJsIHt1cmx9IC0tZW51bWVyYXRlIHA=
register_func wpscan 'Token scan' d3BzY2FuIC0tdXJsIHt1cmx9IC0tYXBpLXRva2VuIHt0b2tlbn0=
register_tool 'Web Application Testing' sqlmap sqlmap sqlmap sqlmap 'SQL injection testing.'
register_func sqlmap 'URL test' c3FsbWFwIC11IHt1cmx9IC0tYmF0Y2g=
register_func sqlmap 'Request file' c3FsbWFwIC1yIHtyZXF1ZXN0X2ZpbGV9IC0tYmF0Y2g=
register_func sqlmap 'DBS enum' c3FsbWFwIC11IHt1cmx9IC0tZGJzIC0tYmF0Y2g=
register_tool 'Web Application Testing' burpsuite burpsuite burpsuite burpsuite 'Web proxy GUI.'
register_func burpsuite Launch YnVycHN1aXRl
register_tool 'Web Application Testing' zaproxy zaproxy zaproxy zaproxy 'OWASP ZAP proxy.'
register_func zaproxy 'Launch GUI' emFwcm94eQ==
register_func zaproxy 'Daemon help' emFwcm94eSAtZGFlbW9uIC1oZWxw
register_category 'Vulnerability Analysis'
register_tool 'Vulnerability Analysis' lynis lynis lynis lynis 'Linux audit checks.'
register_func lynis 'System audit' c3VkbyBseW5pcyBhdWRpdCBzeXN0ZW0=
register_func lynis 'Quick audit' c3VkbyBseW5pcyBhdWRpdCBzeXN0ZW0gLS1xdWljaw==
register_tool 'Vulnerability Analysis' unix-privesc-check unix-privesc-check unix-privesc-check unix-privesc-check 'Local privilege escalation checks.'
register_func unix-privesc-check Standard dW5peC1wcml2ZXNjLWNoZWNrIHN0YW5kYXJk
register_func unix-privesc-check Detailed dW5peC1wcml2ZXNjLWNoZWNrIGRldGFpbGVk
register_tool 'Vulnerability Analysis' gvm/openvas gvm gvm gvm-check-setup 'OpenVAS/GVM scanner stack.'
register_func gvm/openvas Setup c3VkbyBndm0tc2V0dXA=
register_func gvm/openvas 'Check setup' c3VkbyBndm0tY2hlY2stc2V0dXA=
register_func gvm/openvas Start c3VkbyBndm0tc3RhcnQ=
register_func gvm/openvas Stop c3VkbyBndm0tc3RvcA==
register_tool 'Vulnerability Analysis' legion legion legion legion 'GUI recon/enumeration.'
register_func legion Launch bGVnaW9u
register_tool 'Vulnerability Analysis' searchsploit exploitdb exploitdb searchsploit 'Local Exploit-DB search.'
register_func searchsploit Search c2VhcmNoc3Bsb2l0IHtzZWFyY2hfdGVybX0=
register_func searchsploit Path c2VhcmNoc3Bsb2l0IC1wIHtzZWFyY2hfdGVybX0=
register_func searchsploit Help c2VhcmNoc3Bsb2l0IC1o
register_tool 'Vulnerability Analysis' wpscan-vuln wpscan wpscan wpscan 'WordPress vulnerability checks.'
register_func wpscan-vuln 'Vuln enum' d3BzY2FuIC0tdXJsIHt1cmx9IC0tZW51bWVyYXRlIHZwLHZ0
register_func wpscan-vuln 'API vuln check' d3BzY2FuIC0tdXJsIHt1cmx9IC0tYXBpLXRva2VuIHt0b2tlbn0=
register_category 'Password & Hash Recovery'
register_tool 'Password & Hash Recovery' john john john john 'Password hash recovery.'
register_func john 'Crack hash file' am9obiB7aGFzaF9maWxlfQ==
register_func john 'Wordlist mode' am9obiAtLXdvcmRsaXN0PXt3b3JkbGlzdH0ge2hhc2hfZmlsZX0=
register_func john 'Show cracked' am9obiAtLXNob3cge2hhc2hfZmlsZX0=
register_tool 'Password & Hash Recovery' hashcat hashcat hashcat hashcat 'GPU/CPU hash recovery.'
register_func hashcat Dictionary aGFzaGNhdCAtbSB7bW9kZX0ge2hhc2hfZmlsZX0ge3dvcmRsaXN0fQ==
register_func hashcat 'Show cracked' aGFzaGNhdCAtbSB7bW9kZX0ge2hhc2hfZmlsZX0gLS1zaG93
register_func hashcat Benchmark aGFzaGNhdCAtYg==
register_tool 'Password & Hash Recovery' hashid hashid hashid hashid 'Hash type identification.'
register_func hashid 'Identify string' aGFzaGlkIHtoYXNofQ==
register_func hashid 'Identify file' aGFzaGlkIC1mIHtoYXNoX2ZpbGV9
register_tool 'Password & Hash Recovery' hydra hydra hydra hydra 'Network login testing.'
register_func hydra 'Service test' aHlkcmEgLUwge3VzZXJzfSAtUCB7cGFzc3dvcmRzfSB7dGFyZ2V0fSB7c2VydmljZX0=
register_func hydra 'SSH test' aHlkcmEgLUwge3VzZXJzfSAtUCB7cGFzc3dvcmRzfSBzc2g6Ly97dGFyZ2V0fQ==
register_func hydra 'HTTP form template' aHlkcmEgLUwge3VzZXJzfSAtUCB7cGFzc3dvcmRzfSB7dGFyZ2V0fSBodHRwLXBvc3QtZm9ybSB7cGF0aH06e3Bvc3RfZGF0YX06e2ZhaWxfdGV4dH0=
register_tool 'Password & Hash Recovery' ncrack ncrack ncrack ncrack 'Network authentication auditing.'
register_func ncrack 'Service audit' bmNyYWNrIC1VIHt1c2Vyc30gLVAge3Bhc3N3b3Jkc30ge3RhcmdldH06e3BvcnR9
register_tool 'Password & Hash Recovery' cewl cewl cewl cewl 'Custom wordlist generation.'
register_func cewl Generate Y2V3bCB7dXJsfQ==
register_func cewl 'Depth/min length' Y2V3bCB7dXJsfSAtZCB7ZGVwdGh9IC1tIHttaW5fbGVuZ3RofQ==
register_tool 'Password & Hash Recovery' crunch crunch crunch crunch 'Wordlist generation.'
register_func crunch Generate Y3J1bmNoIHttaW59IHttYXh9IHtjaGFyc2V0fQ==
register_func crunch 'Output file' Y3J1bmNoIHttaW59IHttYXh9IHtjaGFyc2V0fSAtbyB7b3V0cHV0X2ZpbGV9
register_tool 'Password & Hash Recovery' seclists seclists seclists '' 'Security wordlists under /usr/share/seclists.'
register_func seclists 'List root' ZmluZCAvdXNyL3NoYXJlL3NlY2xpc3RzIC1tYXhkZXB0aCAyIC10eXBlIGYgfCBoZWFkIC0xMDA=
register_func seclists 'Find list' ZmluZCAvdXNyL3NoYXJlL3NlY2xpc3RzIC10eXBlIGYgLWluYW1lIFwqe3Rlcm19XCogfCBoZWFkIC01MA==
register_tool 'Password & Hash Recovery' wordlists wordlists wordlists '' 'Kali wordlists.'
register_func wordlists List ZmluZCAvdXNyL3NoYXJlL3dvcmRsaXN0cyAtdHlwZSBmIHwgaGVhZCAtMTAw
register_func wordlists 'RockYou path' bHMgLWxoIC91c3Ivc2hhcmUvd29yZGxpc3RzL3JvY2t5b3UudHh0Kg==
register_category 'Wireless Assessment'
register_tool 'Wireless Assessment' airmon-ng aircrack-ng aircrack-ng airmon-ng 'Monitor mode control (shell=False, step-by-step). ON  → check kill, then start monitor. OFF → stop monitor, restart NetworkManager, unblock rfkill.'
register_func airmon-ng 'Monitor mode ON' X19tb25pdG9yX29uX18=
register_func airmon-ng 'Monitor mode OFF + restore networking' X19tb25pdG9yX29mZl9f
register_func airmon-ng 'Check adapters (show interfering procs)' c3VkbyBhaXJtb24tbmcgY2hlY2s=
register_func airmon-ng 'Verify interface mode (iw dev)' aXcgZGV2
register_func airmon-ng 'Unblock Wi-Fi (rfkill fallback)' c3VkbyByZmtpbGwgdW5ibG9jayB3aWZpICYmIG5tY2xpIHJhZGlvIHdpZmkgb24=
register_tool 'Wireless Assessment' airodump-ng aircrack-ng aircrack-ng airodump-ng 'Wireless capture / network discovery.'
register_func airodump-ng 'General capture (all channels)' c3VkbyBhaXJvZHVtcC1uZyB7bW9uaXRvcl9pbnRlcmZhY2V9
register_func airodump-ng 'Targeted capture (specific BSSID/channel)' c3VkbyBhaXJvZHVtcC1uZyAtLWJzc2lkIHtic3NpZH0gLWMge2NoYW5uZWx9IC13IHtjYXB0dXJlX3ByZWZpeH0ge21vbml0b3JfaW50ZXJmYWNlfQ==
register_func airodump-ng 'Band 5 GHz scan' c3VkbyBhaXJvZHVtcC1uZyAtLWJhbmQgYSB7bW9uaXRvcl9pbnRlcmZhY2V9
register_tool 'Wireless Assessment' aireplay-ng aircrack-ng aircrack-ng aireplay-ng 'Wireless frame injection and deauthentication.'
register_func aireplay-ng 'Deauth (broadcast) — capture handshake' c3VkbyBhaXJlcGxheS1uZyAtMCA1IC1hIHtic3NpZH0ge21vbml0b3JfaW50ZXJmYWNlfQ==
register_func aireplay-ng 'Deauth (targeted client)' c3VkbyBhaXJlcGxheS1uZyAtMCA1IC1hIHtic3NpZH0gLWMge2NsaWVudF9tYWN9IHttb25pdG9yX2ludGVyZmFjZX0=
register_func aireplay-ng 'Test injection capability' c3VkbyBhaXJlcGxheS1uZyAtOSB7bW9uaXRvcl9pbnRlcmZhY2V9
register_tool 'Wireless Assessment' aircrack-ng aircrack-ng aircrack-ng aircrack-ng 'WPA/WEP key recovery from captured handshake files.'
register_func aircrack-ng 'Crack WPA capture' YWlyY3JhY2stbmcgLXcge3dvcmRsaXN0fSB7Y2FwdHVyZV9maWxlfQ==
register_func aircrack-ng 'List capture handshakes' YWlyY3JhY2stbmcge2NhcHR1cmVfZmlsZX0=
register_func aircrack-ng 'Help / usage' YWlyY3JhY2stbmcgLS1oZWxw
register_tool 'Wireless Assessment' wifite wifite wifite wifite 'Automated wireless auditing UI.'
register_func wifite 'Launch (auto-select interface)' c3VkbyB3aWZpdGU=
register_func wifite 'Specify interface' c3VkbyB3aWZpdGUgLWkge21vbml0b3JfaW50ZXJmYWNlfQ==
register_func wifite 'WPA-only targets' c3VkbyB3aWZpdGUgLS13cGE=
register_func wifite 'WPS targets only' c3VkbyB3aWZpdGUgLS13cHM=
register_tool 'Wireless Assessment' kismet kismet kismet kismet 'Wireless / RF monitoring and PCAP capture.'
register_func kismet 'Launch (auto-detect)' c3VkbyBraXNtZXQ=
register_func kismet 'Specify interface' c3VkbyBraXNtZXQgLWMge3dpcmVsZXNzX2NhcmR9
register_func kismet 'Headless / daemon mode' c3VkbyBraXNtZXQgLS1kYWVtb25pemU=
register_tool 'Wireless Assessment' reaver reaver reaver reaver 'WPS PIN assessment.'
register_func reaver 'WPS brute-force' c3VkbyByZWF2ZXIgLWkge21vbml0b3JfaW50ZXJmYWNlfSAtYiB7YnNzaWR9IC1jIHtjaGFubmVsfSAtdnY=
register_func reaver 'Pixie-Dust + Reaver' c3VkbyByZWF2ZXIgLWkge21vbml0b3JfaW50ZXJmYWNlfSAtYiB7YnNzaWR9IC1jIHtjaGFubmVsfSAtdnYgLUsgMQ==
register_func reaver 'Resume previous session' c3VkbyByZWF2ZXIgLWkge21vbml0b3JfaW50ZXJmYWNlfSAtYiB7YnNzaWR9IC1jIHtjaGFubmVsfSAtdnYgLXIgMzA6Mw==
register_tool 'Wireless Assessment' pixiewps pixiewps pixiewps pixiewps 'Offline WPS Pixie-Dust attack helper.'
register_func pixiewps 'Help / options' cGl4aWV3cHMgLS1oZWxw
register_tool 'Wireless Assessment' hcxdumptool hcxdumptool hcxdumptool hcxdumptool 'PMKID/EAPOL capture (no client needed). Requires monitor mode.'
register_func hcxdumptool 'PMKID capture (all APs)' c3VkbyBoY3hkdW1wdG9vbCAtbyB7Y2FwdHVyZV9wcmVmaXh9LnBjYXBuZyAtaSB7bW9uaXRvcl9pbnRlcmZhY2V9IC0tZW5hYmxlX3N0YXR1cz0x
register_func hcxdumptool 'Target specific BSSID' c3VkbyBoY3hkdW1wdG9vbCAtbyB7Y2FwdHVyZV9wcmVmaXh9LnBjYXBuZyAtaSB7bW9uaXRvcl9pbnRlcmZhY2V9IC0tZmlsdGVybGlzdF9hcD17YnNzaWR9IC0tZmlsdGVybW9kZT0y
register_tool 'Wireless Assessment' hcxpcapngtool hcxtools hcxtools hcxpcapngtool 'Convert hcxdumptool PMKID/EAPOL captures to hashcat format.'
register_func hcxpcapngtool 'Convert to hashcat 22000' aGN4cGNhcG5ndG9vbCAtbyB7b3V0cHV0X2ZpbGV9LmhjMjIwMDAge2NhcHR1cmVfZmlsZX0=
register_func hcxpcapngtool 'Convert to hashcat 16800 (PMKID)' aGN4cGNhcG5ndG9vbCAtLXBta2lkPXtvdXRwdXRfZmlsZX0uMTY4MDAge2NhcHR1cmVfZmlsZX0=
register_tool 'Wireless Assessment' bettercap-wifi bettercap bettercap bettercap 'Wi-Fi recon and probe sniffing via bettercap.'
register_func bettercap-wifi 'Wi-Fi recon caplet' c3VkbyBiZXR0ZXJjYXAgLWlmYWNlIHt3aXJlbGVzc19jYXJkfSAtZXZhbCAnd2lmaS5yZWNvbiBvbjsgd2lmaS5zaG93Jw==
register_func bettercap-wifi 'Interactive Wi-Fi console' c3VkbyBiZXR0ZXJjYXAgLWlmYWNlIHt3aXJlbGVzc19jYXJkfQ==
register_category 'Packet Analysis & Spoofing'
register_tool 'Packet Analysis & Spoofing' wireshark wireshark 'wireshark-qt wireshark-cli wireshark' wireshark 'Packet analysis GUI.'
register_func wireshark Launch d2lyZXNoYXJr
register_tool 'Packet Analysis & Spoofing' tshark tshark 'wireshark-cli tshark' tshark 'CLI packet analysis.'
register_func tshark Capture c3VkbyB0c2hhcmsgLWkge2lmYWNlfSAtdyB7b3V0cHV0X2ZpbGV9
register_func tshark 'Read pcap' dHNoYXJrIC1yIHtwY2FwX2ZpbGV9
register_func tshark Interfaces dHNoYXJrIC1E
register_tool 'Packet Analysis & Spoofing' tcpdump tcpdump tcpdump tcpdump 'Packet capture.'
register_func tcpdump 'Live capture' c3VkbyB0Y3BkdW1wIC1pIHtpZmFjZX0=
register_func tcpdump 'Save pcap' c3VkbyB0Y3BkdW1wIC1pIHtpZmFjZX0gLXcge291dHB1dF9maWxlfQ==
register_func tcpdump 'Host filter' c3VkbyB0Y3BkdW1wIC1pIHtpZmFjZX0gaG9zdCB7aG9zdH0=
register_tool 'Packet Analysis & Spoofing' bettercap bettercap bettercap bettercap 'LAN/Wi-Fi assessment console.'
register_func bettercap 'Launch interface' c3VkbyBiZXR0ZXJjYXAgLWlmYWNlIHtpZmFjZX0=
register_func bettercap Caplet c3VkbyBiZXR0ZXJjYXAgLWlmYWNlIHtpZmFjZX0gLWNhcGxldCB7Y2FwbGV0fQ==
register_tool 'Packet Analysis & Spoofing' ettercap ettercap-graphical 'ettercap ettercap-graphical' ettercap 'LAN assessment/sniffing suite.'
register_func ettercap 'Text UI' c3VkbyBldHRlcmNhcCAtVCAtaSB7aWZhY2V9
register_func ettercap GUI c3VkbyBldHRlcmNhcCAtRw==
register_tool 'Packet Analysis & Spoofing' responder responder responder responder 'LLMNR/NBT-NS/mDNS responder.'
register_func responder Launch c3VkbyByZXNwb25kZXIgLUkge2lmYWNlfSAtdyAtRg==
register_tool 'Packet Analysis & Spoofing' macchanger macchanger macchanger macchanger 'MAC address changes.'
register_func macchanger 'Random MAC' c3VkbyBpcCBsaW5rIHNldCB7aWZhY2V9IGRvd247IHN1ZG8gbWFjY2hhbmdlciAtciB7aWZhY2V9OyBzdWRvIGlwIGxpbmsgc2V0IHtpZmFjZX0gdXA=
register_func macchanger 'Reset MAC' c3VkbyBpcCBsaW5rIHNldCB7aWZhY2V9IGRvd247IHN1ZG8gbWFjY2hhbmdlciAtcCB7aWZhY2V9OyBzdWRvIGlwIGxpbmsgc2V0IHtpZmFjZX0gdXA=
register_category 'Exploitation Frameworks'
register_tool 'Exploitation Frameworks' metasploit-framework metasploit-framework 'metasploit metasploit-framework' msfconsole 'Exploit framework launcher.'
register_func metasploit-framework 'Launch msfconsole' bXNmY29uc29sZQ==
register_func metasploit-framework 'Resource file' bXNmY29uc29sZSAtciB7cmVzb3VyY2VfZmlsZX0=
register_func metasploit-framework 'Search module' bXNmY29uc29sZSAtcSAteCBzZWFyY2hcIHtzZWFyY2hfdGVybX1cO1wgZXhpdA==
register_tool 'Exploitation Frameworks' msfvenom metasploit-framework 'metasploit metasploit-framework' msfvenom 'Payload options/listing helper.'
register_func msfvenom 'List payloads' bXNmdmVub20gLWwgcGF5bG9hZHM=
register_func msfvenom 'List formats' bXNmdmVub20gLWwgZm9ybWF0cw==
register_func msfvenom 'Payload options' bXNmdmVub20gLXAge3BheWxvYWR9IC0tbGlzdC1vcHRpb25z
register_tool 'Exploitation Frameworks' searchsploit-exploit exploitdb exploitdb searchsploit 'Local Exploit-DB search.' searchsploit
register_func searchsploit-exploit Search c2VhcmNoc3Bsb2l0IHtzZWFyY2hfdGVybX0=
register_func searchsploit-exploit 'Mirror/copy path' c2VhcmNoc3Bsb2l0IC1tIHtleHBsb2l0X3BhdGh9
register_func searchsploit-exploit Help c2VhcmNoc3Bsb2l0IC1o
register_tool 'Exploitation Frameworks' commix commix commix commix 'Command injection testing.'
register_func commix 'URL test' Y29tbWl4IC11IHt1cmx9IC0tYmF0Y2g=
register_func commix 'Request file' Y29tbWl4IC1yIHtyZXF1ZXN0X2ZpbGV9IC0tYmF0Y2g=
register_tool 'Exploitation Frameworks' setoolkit set 'setoolkit set' setoolkit 'SET launcher for controlled lab training.'
register_func setoolkit Launch c3VkbyBzZXRvb2xraXQ=
register_category 'Post-Exploitation & Active Directory'
register_tool 'Post-Exploitation & Active Directory' netexec netexec netexec nxc 'Internal Active Directory assessment toolkit.'
register_func netexec 'SMB check' bnhjIHNtYiB7dGFyZ2V0X29yX2NpZHJ9
register_func netexec 'Credentialed SMB' bnhjIHNtYiB7dGFyZ2V0X29yX2NpZHJ9IC11IHt1c2VybmFtZX0gLXAge3Bhc3N3b3JkfQ==
register_func netexec Help bnhjIC0taGVscA==
register_tool 'Post-Exploitation & Active Directory' crackmapexec crackmapexec crackmapexec crackmapexec 'Internal network assessment toolkit.'
register_func crackmapexec 'SMB check' Y3JhY2ttYXBleGVjIHNtYiB7dGFyZ2V0X29yX2NpZHJ9
register_func crackmapexec 'Credentialed SMB' Y3JhY2ttYXBleGVjIHNtYiB7dGFyZ2V0X29yX2NpZHJ9IC11IHt1c2VybmFtZX0gLXAge3Bhc3N3b3JkfQ==
register_tool 'Post-Exploitation & Active Directory' impacket-scripts impacket-scripts 'python-impacket impacket-scripts' impacket-smbclient 'Impacket script collection.'
register_func impacket-scripts 'List tools' bHMgL3Vzci9iaW4vaW1wYWNrZXQtKg==
register_func impacket-scripts 'SMB client help' aW1wYWNrZXQtc21iY2xpZW50IC1o
register_func impacket-scripts 'Secretsdump help' aW1wYWNrZXQtc2VjcmV0c2R1bXAgLWg=
register_tool 'Post-Exploitation & Active Directory' evil-winrm evil-winrm evil-winrm evil-winrm 'WinRM client.'
register_func evil-winrm Connect ZXZpbC13aW5ybSAtaSB7dGFyZ2V0fSAtdSB7dXNlcm5hbWV9IC1wIHtwYXNzd29yZH0=
register_func evil-winrm 'SSL connect' ZXZpbC13aW5ybSAtUyAtaSB7dGFyZ2V0fSAtdSB7dXNlcm5hbWV9IC1wIHtwYXNzd29yZH0=
register_tool 'Post-Exploitation & Active Directory' bloodhound bloodhound bloodhound bloodhound 'Active Directory graph GUI.'
register_func bloodhound 'Launch GUI' Ymxvb2Rob3VuZA==
register_tool 'Post-Exploitation & Active Directory' bloodhound-python bloodhound.py 'bloodhound-python bloodhound.py' bloodhound-python 'BloodHound collector.'
register_func bloodhound-python 'Collect all' Ymxvb2Rob3VuZC1weXRob24gLWQge2RvbWFpbn0gLXUge3VzZXJuYW1lfSAtcCB7cGFzc3dvcmR9IC1ucyB7ZGNfaXB9IC1jIEFsbCAtemlw
register_tool 'Post-Exploitation & Active Directory' ldapdomaindump ldapdomaindump 'python-ldapdomaindump ldapdomaindump' ldapdomaindump 'LDAP domain enumeration.'
register_func ldapdomaindump 'Dump domain' bGRhcGRvbWFpbmR1bXAgLXUge2RvbWFpbn1cXHt1c2VybmFtZX0gLXAge3Bhc3N3b3JkfSB7ZGNfaXB9
register_category 'Forensics & Reverse Engineering'
register_tool 'Forensics & Reverse Engineering' autopsy autopsy autopsy autopsy 'Forensics GUI/web interface.'
register_func autopsy Launch YXV0b3BzeQ==
register_tool 'Forensics & Reverse Engineering' sleuthkit sleuthkit sleuthkit fls 'Filesystem forensics tools.'
register_func sleuthkit 'List files' ZmxzIHtpbWFnZV9maWxlfQ==
register_func sleuthkit 'Filesystem stats' ZnNzdGF0IHtpbWFnZV9maWxlfQ==
register_func sleuthkit 'Recover files' dHNrX3JlY292ZXIge2ltYWdlX2ZpbGV9IHtvdXRwdXRfZGlyfQ==
register_tool 'Forensics & Reverse Engineering' binwalk binwalk binwalk binwalk 'Firmware/file analysis.'
register_func binwalk Analyze Ymlud2FsayB7ZmlsZX0=
register_func binwalk Extract Ymlud2FsayAtZSB7ZmlsZX0=
register_tool 'Forensics & Reverse Engineering' foremost foremost foremost foremost 'File carving.'
register_func foremost Carve Zm9yZW1vc3QgLWkge2ltYWdlX2ZpbGV9IC1vIHtvdXRwdXRfZGlyfQ==
register_tool 'Forensics & Reverse Engineering' exiftool libimage-exiftool-perl 'perl-image-exiftool libimage-exiftool-perl' exiftool 'Metadata inspection/removal.'
register_func exiftool 'Read metadata' ZXhpZnRvb2wge2ZpbGV9
register_func exiftool 'Remove metadata copy' ZXhpZnRvb2wgLWFsbD0gLW8ge291dHB1dF9maWxlfSB7ZmlsZX0=
register_tool 'Forensics & Reverse Engineering' volatility3 volatility3 volatility3 vol 'Memory forensics.'
register_func volatility3 'Windows info' dm9sIC1mIHttZW1vcnlfaW1hZ2V9IHdpbmRvd3MuaW5mbw==
register_func volatility3 'Plugin list' dm9sIC1o
register_tool 'Forensics & Reverse Engineering' ghidra ghidra ghidra ghidra 'Reverse engineering GUI.'
register_func ghidra Launch Z2hpZHJh
register_tool 'Forensics & Reverse Engineering' radare2 radare2 radare2 r2 'Reverse engineering CLI.'
register_func radare2 'Analyze binary' cjIgLUEge2ZpbGV9
register_func radare2 Strings cmFiaW4yIC16eiB7ZmlsZX0=
register_tool 'Forensics & Reverse Engineering' gdb gdb gdb gdb Debugger.
register_func gdb 'Debug file' Z2RiIHtmaWxlfQ==
register_func gdb Quiet Z2RiIC1xIHtmaWxlfQ==
register_tool 'Forensics & Reverse Engineering' apktool apktool apktool apktool 'APK decode/build.'
register_func apktool 'Decode APK' YXBrdG9vbCBkIHthcGtfZmlsZX0gLW8ge291dHB1dF9kaXJ9
register_func apktool 'Build folder' YXBrdG9vbCBiIHtmb2xkZXJ9
register_tool 'Forensics & Reverse Engineering' jadx jadx jadx jadx 'Dex/APK Java decompiler.'
register_func jadx 'Decompile APK' amFkeCB7YXBrX2ZpbGV9IC1kIHtvdXRwdXRfZGlyfQ==
register_func jadx GUI amFkeC1ndWkge2Fwa19maWxlfQ==
register_category 'Reporting & Operator Utilities'
register_tool 'Reporting & Operator Utilities' cherrytree cherrytree cherrytree cherrytree 'Notes GUI.'
register_func cherrytree Launch Y2hlcnJ5dHJlZQ==
register_tool 'Reporting & Operator Utilities' faraday faraday faraday faraday 'Pentest IDE/reporting platform.'
register_func faraday Launch ZmFyYWRheQ==
register_func faraday Help ZmFyYWRheSAtLWhlbHA=
register_tool 'Reporting & Operator Utilities' eyewitness eyewitness eyewitness eyewitness 'Screenshot/reporting helper.'
register_func eyewitness 'Single URL' ZXlld2l0bmVzcyAtLXNpbmdsZSB7dXJsfSAtZCB7b3V0cHV0X2Rpcn0=
register_func eyewitness 'URL file' ZXlld2l0bmVzcyAtZiB7dXJsX2ZpbGV9IC1kIHtvdXRwdXRfZGlyfQ==
register_tool 'Reporting & Operator Utilities' curl curl curl curl 'HTTP/client utility.'
register_func curl Headers Y3VybCAtSSB7dXJsfQ==
register_func curl 'Verbose TLS' Y3VybCAtdmsge3VybH0=
register_func curl 'Save response' Y3VybCAtTCB7dXJsfSAtbyB7b3V0cHV0X2ZpbGV9
register_tool 'Reporting & Operator Utilities' jq jq jq jq 'JSON parser.'
register_func jq 'Pretty print' anEgLiB7anNvbl9maWxlfQ==
register_func jq Query anEge2pxX2ZpbHRlcn0ge2pzb25fZmlsZX0=
register_tool 'Reporting & Operator Utilities' git git git git 'Version control/source retrieval.'
register_func git 'Clone repo' Z2l0IGNsb25lIHtyZXBvX3VybH0ge291dHB1dF9kaXJ9
register_func git Status Z2l0IHN0YXR1cw==
register_tool 'Reporting & Operator Utilities' tmux tmux tmux tmux 'Terminal multiplexing.'
register_func tmux 'New session' dG11eCBuZXcgLXMge3Nlc3Npb25fbmFtZX0=
register_func tmux Attach dG11eCBhdHRhY2ggLXQge3Nlc3Npb25fbmFtZX0=
register_func tmux 'List sessions' dG11eCBscw==
register_tool 'Reporting & Operator Utilities' proxychains4 proxychains4 'proxychains-ng proxychains4' proxychains4 'Run commands through configured proxychains.'
register_func proxychains4 'HTTP headers through proxy' cHJveHljaGFpbnM0IGN1cmwgLUkge3VybH0=

# __DATA_END__

# ── Configuration and workspace storage ───────────────────────────────────────
safe_name() {
    local value=${1:-default}
    value=${value//[^A-Za-z0-9._-]/_}
    [[ -n "$value" ]] || value=default
    case "$value" in .|..) value=default ;; esac
    printf '%s' "${value:0:80}"
}

workspace_path() { printf '%s/%s' "$WORKSPACES_DIR" "$ACTIVE_WORKSPACE"; }
evidence_dir() { printf '%s/evidence' "$(workspace_path)"; }
history_file() { printf '%s/history.tsv' "$(workspace_path)"; }
scope_file() { printf '%s/scope.txt' "$(workspace_path)"; }

ensure_workspace() {
    local ws root
    ws=$(safe_name "${1:-$ACTIVE_WORKSPACE}")
    root="$WORKSPACES_DIR/$ws"
    safe_mkdir "$root" || return 1
    safe_mkdir "$root/evidence" || return 1
    safe_mkdir "$root/reports" || return 1
    safe_mkdir "$root/exports" || return 1
    safe_mkdir "$root/notes" || return 1
    safe_mkdir "$root/loot" || return 1
    safe_mkdir "$root/tmp" || return 1
    ensure_private_file "$root/history.tsv" || return 1
    ensure_private_file "$root/scope.txt" || return 1
    chmod 700 "$root" "$root/evidence" "$root/reports" "$root/exports" "$root/notes" "$root/loot" "$root/tmp" || return 1
}

save_config() {
    local tmp
    safe_mkdir "$SOT_HOME" || return 1
    tmp=$(mktemp "$SOT_HOME/config.XXXXXX") || { error "Could not create config file."; return 1; }
    {
        printf 'ACTIVE_WORKSPACE=%s\n' "$(safe_name "$ACTIVE_WORKSPACE")"
        printf 'ACTIVE_MODE=%s\n' "$ACTIVE_MODE"
        printf 'STRICT_SCOPE=%s\n' "$STRICT_SCOPE"
    } > "$tmp" || { rm -f -- "$tmp"; return 1; }
    chmod 600 "$tmp"
    mv -f -- "$tmp" "$CONFIG_FILE"
}

load_config() {
    local key value mode owner
    safe_mkdir "$SOT_HOME" || exit 1
    safe_mkdir "$WORKSPACES_DIR" || exit 1
    if [[ -L "$CONFIG_FILE" ]]; then
        warn "Ignoring symbolic-link config file: $CONFIG_FILE"
    elif [[ -f "$CONFIG_FILE" ]]; then
        mode=$(stat -c '%a' "$CONFIG_FILE" 2>/dev/null || printf '000')
        owner=$(stat -c '%u' "$CONFIG_FILE" 2>/dev/null || printf '%s' "$EUID")
        if [[ "$owner" == "$EUID" && "$mode" =~ ^[0-7]00$ ]]; then
            while IFS='=' read -r key value; do
                case "$key" in
                    ACTIVE_WORKSPACE) ACTIVE_WORKSPACE=$(safe_name "$value") ;;
                    ACTIVE_MODE) [[ "$value" =~ ^(lab|ctf|engagement)$ ]] && ACTIVE_MODE=$value ;;
                    STRICT_SCOPE) [[ "$value" =~ ^[01]$ ]] && STRICT_SCOPE=$value ;;
                esac
            done < "$CONFIG_FILE"
        else
            warn "Ignoring config with unsafe ownership or permissions: $CONFIG_FILE"
        fi
    fi
    ACTIVE_WORKSPACE=$(safe_name "${ACTIVE_WORKSPACE:-default}")
    [[ "$ACTIVE_MODE" =~ ^(lab|ctf|engagement)$ ]] || ACTIVE_MODE=lab
    [[ "$STRICT_SCOPE" =~ ^[01]$ ]] || STRICT_SCOPE=0
    ensure_workspace "$ACTIVE_WORKSPACE" || exit 1
}

# ── Distro selection and package policy ──────────────────────────────────────
os_release_value() {
    local key=$1 file=${2:-/etc/os-release}
    [[ -r "$file" ]] || return 1
    awk -F= -v wanted="$key" '
        $1 == wanted {
            value = substr($0, index($0, "=") + 1)
            if (value ~ /^".*"$/) { sub(/^"/, "", value); sub(/"$/, "", value) }
            gsub(/\\"/, "\"", value)
            print value
            exit
        }
    ' "$file"
}

detect_distro() {
    local id name pretty id_like
    id=$(os_release_value ID 2>/dev/null || true)
    name=$(os_release_value NAME 2>/dev/null || true)
    pretty=$(os_release_value PRETTY_NAME 2>/dev/null || true)
    id_like=$(os_release_value ID_LIKE 2>/dev/null || true)
    DETECTED_DISTRO=${id,,}
    DETECTED_DISTRO=${DETECTED_DISTRO:-unknown}
    DETECTED_DISTRO_NAME=${pretty:-${name:-$DETECTED_DISTRO}}
    DETECTED_ID_LIKE=${id_like,,}
}

detect_package_manager() {
    local family=" $DETECTED_DISTRO $DETECTED_ID_LIKE "
    PACKAGE_MANAGER=unknown
    PACKAGE_MANAGER_CMD=""

    case "$family" in
        *" arch "*)
            if command -v pacman >/dev/null 2>&1; then PACKAGE_MANAGER=pacman; PACKAGE_MANAGER_CMD=pacman; return; fi ;;
        *" debian "*|*" ubuntu "*)
            if command -v apt-get >/dev/null 2>&1; then PACKAGE_MANAGER=apt; PACKAGE_MANAGER_CMD=apt-get; return; fi ;;
        *" fedora "*|*" rhel "*|*" centos "*|*" rocky "*|*" almalinux "*)
            if command -v dnf >/dev/null 2>&1; then PACKAGE_MANAGER=dnf; PACKAGE_MANAGER_CMD=dnf; return; fi
            if command -v dnf5 >/dev/null 2>&1; then PACKAGE_MANAGER=dnf; PACKAGE_MANAGER_CMD=dnf5; return; fi ;;
        *" suse "*|*" opensuse "*|*" sles "*)
            if command -v zypper >/dev/null 2>&1; then PACKAGE_MANAGER=zypper; PACKAGE_MANAGER_CMD=zypper; return; fi ;;
        *" alpine "*)
            if command -v apk >/dev/null 2>&1; then PACKAGE_MANAGER=apk; PACKAGE_MANAGER_CMD=apk; return; fi ;;
        *" void "*)
            if command -v xbps-install >/dev/null 2>&1 && command -v xbps-query >/dev/null 2>&1; then
                PACKAGE_MANAGER=xbps; PACKAGE_MANAGER_CMD=xbps-install; return
            fi ;;
        *" gentoo "*)
            if command -v emerge >/dev/null 2>&1; then PACKAGE_MANAGER=portage; PACKAGE_MANAGER_CMD=emerge; return; fi ;;
        *" nixos "*)
            if command -v nix-env >/dev/null 2>&1; then PACKAGE_MANAGER=nix; PACKAGE_MANAGER_CMD=nix-env; return; fi ;;
    esac

    if command -v apt-get >/dev/null 2>&1 && command -v dpkg-query >/dev/null 2>&1; then
        PACKAGE_MANAGER=apt; PACKAGE_MANAGER_CMD=apt-get
    elif command -v dnf >/dev/null 2>&1; then
        PACKAGE_MANAGER=dnf; PACKAGE_MANAGER_CMD=dnf
    elif command -v dnf5 >/dev/null 2>&1; then
        PACKAGE_MANAGER=dnf; PACKAGE_MANAGER_CMD=dnf5
    elif command -v zypper >/dev/null 2>&1; then
        PACKAGE_MANAGER=zypper; PACKAGE_MANAGER_CMD=zypper
    elif command -v apk >/dev/null 2>&1; then
        PACKAGE_MANAGER=apk; PACKAGE_MANAGER_CMD=apk
    elif command -v xbps-install >/dev/null 2>&1 && command -v xbps-query >/dev/null 2>&1; then
        PACKAGE_MANAGER=xbps; PACKAGE_MANAGER_CMD=xbps-install
    elif command -v pacman >/dev/null 2>&1; then
        PACKAGE_MANAGER=pacman; PACKAGE_MANAGER_CMD=pacman
    elif command -v emerge >/dev/null 2>&1; then
        PACKAGE_MANAGER=portage; PACKAGE_MANAGER_CMD=emerge
    elif command -v nix-env >/dev/null 2>&1; then
        PACKAGE_MANAGER=nix; PACKAGE_MANAGER_CMD=nix-env
    fi
}

distro_display() {
    case "$CURRENT_DISTRO" in
        kali) printf 'Kali Linux' ;;
        arch) printf 'Arch Linux' ;;
        parrot) printf 'Parrot OS' ;;
        other) printf 'Other · %s · %s' "$DETECTED_DISTRO_NAME" "$PACKAGE_MANAGER" ;;
        *) printf 'not selected' ;;
    esac
}

effective_package_manager() {
    case "$CURRENT_DISTRO" in
        kali|parrot) printf 'apt' ;;
        arch) printf 'pacman' ;;
        other) printf '%s' "$PACKAGE_MANAGER" ;;
        *) printf 'unknown' ;;
    esac
}

run_root() {
    if (( EUID == 0 )); then
        command "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    elif command -v doas >/dev/null 2>&1; then
        doas "$@"
    else
        error "A privilege helper is required for this action (sudo or doas)."
        return 1
    fi
}

verify_distro_tools() {
    case "$CURRENT_DISTRO" in
        kali|parrot)
            PACKAGE_MANAGER=apt; PACKAGE_MANAGER_CMD=apt-get
            command -v apt-get >/dev/null 2>&1 && command -v apt-cache >/dev/null 2>&1 && command -v dpkg-query >/dev/null 2>&1 || {
                error "APT tools are missing. The selected distro cannot be managed safely."; return 1; }
            ;;
        arch)
            PACKAGE_MANAGER=pacman; PACKAGE_MANAGER_CMD=pacman
            command -v pacman >/dev/null 2>&1 || { error "pacman is missing."; return 1; }
            ;;
        other)
            detect_package_manager
            case "$PACKAGE_MANAGER" in
                apt)
                    command -v apt-cache >/dev/null 2>&1 && command -v dpkg-query >/dev/null 2>&1 || {
                        warn "APT detection is incomplete; package installation will be unavailable."; PACKAGE_MANAGER=unknown; }
                    ;;
                dnf|zypper|apk|pacman|portage|nix) : ;;
                xbps)
                    command -v xbps-query >/dev/null 2>&1 || { warn "XBPS detection is incomplete."; PACKAGE_MANAGER=unknown; }
                    ;;
                unknown) warn "No supported package manager was detected. S.O.T will still run installed tools." ;;
            esac
            if [[ "$PACKAGE_MANAGER" == pacman && "$DETECTED_DISTRO" != arch ]]; then
                warn "pacman was detected on a non-Arch system. Package installation is disabled to avoid repository mixing."
            fi
            ;;
    esac
}

select_distro() {
    detect_distro
    detect_package_manager
    while true; do
        clear_screen
        logo
        printf '\n%b\n' "${WHITE}${BOLD}SELECT YOUR DISTRIBUTION${RESET}"
        printf 'Detected: %s (ID: %s, package manager: %s)\n\n' "$DETECTED_DISTRO_NAME" "$DETECTED_DISTRO" "$PACKAGE_MANAGER"
        printf '1. Kali Linux\n'
        printf '2. Arch Linux\n'
        printf '3. Parrot OS\n'
        printf '4. Other Linux distribution (automatic package-manager detection)\n'
        printf '5. Exit\n\n'
        read -r -u 3 -p "Select an option: " choice || exit 0
        case "$choice" in
            1) CURRENT_DISTRO=kali ;;
            2) CURRENT_DISTRO=arch ;;
            3) CURRENT_DISTRO=parrot ;;
            4) CURRENT_DISTRO=other ;;
            5|q|Q) exit 0 ;;
            *) error "Invalid option."; sleep 1; continue ;;
        esac
        if [[ "$CURRENT_DISTRO" != other && "$DETECTED_DISTRO" != "$CURRENT_DISTRO" ]]; then
            error "Detected '$DETECTED_DISTRO', so '$CURRENT_DISTRO' package operations are blocked."
            warn "Choose Other for this Linux distribution."
            sleep 1
            continue
        fi
        verify_distro_tools || { pause; continue; }
        if [[ "$CURRENT_DISTRO" == other ]]; then
            ok "Other distro mode enabled: $DETECTED_DISTRO_NAME · package manager: $PACKAGE_MANAGER"
            sleep 1
        fi
        return 0
    done
}

safe_package_state_dir() {
    local path=$1 base relative
    base="$SOT_HOME/package-lists"
    safe_mkdir "$base" || return 1
    case "$path" in
        "$base") return 0 ;;
        "$base"/*) relative=${path#"$base"/} ;;
        *) error "Package state path escaped its allowed directory: $path"; return 1 ;;
    esac
    safe_mkdir_under "$base" "$relative" >/dev/null
}

official_apt_context() {
    local tmp
    OFFICIAL_APT_SOURCE="$SOT_HOME/package-sources/${CURRENT_DISTRO}.list"
    OFFICIAL_APT_LISTS="$SOT_HOME/package-lists/${CURRENT_DISTRO}"
    safe_mkdir "$SOT_HOME/package-sources" || return 1
    safe_mkdir "$SOT_HOME/package-lists" || return 1
    safe_package_state_dir "$OFFICIAL_APT_LISTS" || return 1
    safe_package_state_dir "$OFFICIAL_APT_LISTS/partial" || return 1
    chmod 711 "$SOT_HOME" 2>/dev/null || true
    chmod 755 "$SOT_HOME/package-sources" "$OFFICIAL_APT_LISTS" "$OFFICIAL_APT_LISTS/partial" 2>/dev/null || true
    tmp=$(mktemp "$SOT_HOME/package-sources/.${CURRENT_DISTRO}.list.XXXXXX") || {
        error "Could not create the locked APT source file."; return 1; }
    case "$CURRENT_DISTRO" in
        kali)
            printf '%s\n' 'deb http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware' > "$tmp"
            ;;
        parrot)
            cat > "$tmp" <<'PARROT_SOURCES'
deb https://deb.parrot.sh/parrot echo main contrib non-free non-free-firmware
deb https://deb.parrot.sh/parrot echo-security main contrib non-free non-free-firmware
deb https://deb.parrot.sh/parrot echo-backports main contrib non-free non-free-firmware
PARROT_SOURCES
            ;;
        *) rm -f -- "$tmp"; return 1 ;;
    esac
    chmod 644 "$tmp" || { rm -f -- "$tmp"; return 1; }
    mv -f -- "$tmp" "$OFFICIAL_APT_SOURCE" || { rm -f -- "$tmp"; return 1; }
}

apt_official_options() {
    APT_OFFICIAL_OPTS=(
        -o "Dir::Etc::sourcelist=$OFFICIAL_APT_SOURCE"
        -o 'Dir::Etc::sourceparts=-'
        -o 'Dir::Etc::preferences=/dev/null'
        -o 'Dir::Etc::preferencesparts=-'
        -o "Dir::State::Lists=$OFFICIAL_APT_LISTS"
        -o 'APT::Get::List-Cleanup=0'
        -o 'Acquire::AllowInsecureRepositories=false'
        -o 'Acquire::AllowDowngradeToInsecureRepositories=false'
        -o 'Acquire::AllowWeakRepositories=false'
        -o 'APT::Get::AllowUnauthenticated=false'
    )
}

apt_system_security_ok() {
    local unsafe=0 dump
    if grep -RIsE --include='*.list' --include='*.sources' \
        '(\[[^]]*(trusted|allow-insecure|allow-weak)[[:space:]]*=[[:space:]]*yes|^[[:space:]]*(Trusted|Allow-Insecure|Allow-Weak):[[:space:]]*yes)' \
        /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null | grep -q .; then
        error "APT contains a source that disables normal trust checks. Package installation is blocked."
        unsafe=1
    fi
    if command -v apt-config >/dev/null 2>&1; then
        dump=$(apt-config dump 2>/dev/null || true)
        if grep -Eqi '(AllowUnauthenticated|AllowInsecureRepositories|AllowWeakRepositories).*"true"' <<< "$dump"; then
            error "APT is configured to permit insecure or unauthenticated packages. Installation is blocked."
            unsafe=1
        fi
    fi
    (( unsafe == 0 ))
}

apt_system_options() {
    APT_SYSTEM_OPTS=(
        -o 'Acquire::AllowInsecureRepositories=false'
        -o 'Acquire::AllowDowngradeToInsecureRepositories=false'
        -o 'Acquire::AllowWeakRepositories=false'
        -o 'APT::Get::AllowUnauthenticated=false'
    )
}

official_apt_package_available() {
    local pkg=$1 candidate
    official_apt_context || return 1
    apt_official_options
    candidate=$(LC_ALL=C apt-cache "${APT_OFFICIAL_OPTS[@]}" policy -- "$pkg" 2>/dev/null | awk '/^[[:space:]]*Candidate:/{print $2; exit}')
    [[ -n "$candidate" && "$candidate" != "(none)" ]]
}

system_apt_package_available() {
    local pkg=$1 candidate
    apt_system_security_ok || return 1
    apt_system_options
    candidate=$(LC_ALL=C apt-cache "${APT_SYSTEM_OPTS[@]}" policy -- "$pkg" 2>/dev/null | awk '/^[[:space:]]*Candidate:/{print $2; exit}')
    [[ -n "$candidate" && "$candidate" != "(none)" ]]
}

write_arch_pacman_config() {
    local tmp
    ARCH_PACMAN_CONFIG="$SOT_HOME/package-sources/pacman-official.conf"
    [[ -r /etc/pacman.d/mirrorlist ]] || { error "Arch mirror list is missing: /etc/pacman.d/mirrorlist"; return 1; }
    safe_mkdir "$SOT_HOME/package-sources" || return 1
    tmp=$(mktemp "$SOT_HOME/package-sources/.pacman-official.XXXXXX") || {
        error "Could not create the locked pacman configuration."; return 1; }
    cat > "$tmp" <<PACMAN_CONFIG
[options]
Architecture = auto
CheckSpace
HookDir = /etc/pacman.d/hooks
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Required
RemoteFileSigLevel = Required

[core]
Include = /etc/pacman.d/mirrorlist

[extra]
Include = /etc/pacman.d/mirrorlist
PACMAN_CONFIG
    if [[ "$(uname -m)" == x86_64 ]]; then
        cat >> "$tmp" <<'PACMAN_MULTILIB'

[multilib]
Include = /etc/pacman.d/mirrorlist
PACMAN_MULTILIB
    fi
    chmod 600 "$tmp" || { rm -f -- "$tmp"; return 1; }
    mv -f -- "$tmp" "$ARCH_PACMAN_CONFIG" || { rm -f -- "$tmp"; return 1; }
}

refresh_arch_query_database() {
    write_arch_pacman_config || return 1
    ARCH_QUERY_DB="$SOT_HOME/package-lists/arch-query"
    safe_mkdir "$SOT_HOME/package-lists" || return 1
    safe_package_state_dir "$ARCH_QUERY_DB" || return 1
    safe_package_state_dir "$ARCH_QUERY_DB/local" || return 1
    safe_package_state_dir "$ARCH_QUERY_DB/sync" || return 1
    safe_package_state_dir "$ARCH_QUERY_DB/pkg" || return 1
    chmod 711 "$SOT_HOME" 2>/dev/null || true
    chmod 755 "$SOT_HOME/package-lists" "$ARCH_QUERY_DB" "$ARCH_QUERY_DB/local" "$ARCH_QUERY_DB/sync" "$ARCH_QUERY_DB/pkg" 2>/dev/null || true
    run_root pacman --config "$ARCH_PACMAN_CONFIG" --dbpath "$ARCH_QUERY_DB" --logfile "$ARCH_QUERY_DB/pacman.log" -Sy
}

arch_official_package_available() {
    local pkg=$1 repo
    write_arch_pacman_config || return 1
    ARCH_QUERY_DB="$SOT_HOME/package-lists/arch-query"
    [[ -d "$ARCH_QUERY_DB/sync" ]] || return 1
    repo=$(LC_ALL=C run_root pacman --config "$ARCH_PACMAN_CONFIG" --dbpath "$ARCH_QUERY_DB" --logfile "$ARCH_QUERY_DB/pacman.log" -Si -- "$pkg" 2>/dev/null | awk -F: '/^Repository/{gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit}')
    case "$repo" in
        core|extra|multilib) return 0 ;;
        *) return 1 ;;
    esac
}

package_install_supported() {
    case "$(effective_package_manager)" in
        apt|dnf|zypper|apk|xbps) return 0 ;;
        pacman) [[ "$DETECTED_DISTRO" == arch ]] ;;
        *) return 1 ;;
    esac
}

package_candidates_for_tool() {
    local tool=$1 manager candidate
    local -A seen=()
    manager=$(effective_package_manager)
    case "$manager" in
        pacman) candidate="${TOOL_PKG_ARCH[$tool]:-}" ;;
        apt) candidate="${TOOL_PKG_APT[$tool]:-}" ;;
        dnf|zypper|apk|xbps) candidate="${TOOL_BIN[$tool]:-}" ;;
        *) candidate='' ;;
    esac
    for candidate in $candidate; do
        [[ "$candidate" =~ ^[A-Za-z0-9@._+:-]+$ ]] || continue
        [[ -z "${seen[$candidate]+present}" ]] || continue
        seen[$candidate]=1
        printf '%s\n' "$candidate"
    done
}

other_package_available() {
    local pkg=$1 escaped
    case "$PACKAGE_MANAGER" in
        apt) system_apt_package_available "$pkg" ;;
        dnf) "$PACKAGE_MANAGER_CMD" -q --setopt=gpgcheck=1 list --available "$pkg" >/dev/null 2>&1 ;;
        zypper)
            LC_ALL=C zypper --non-interactive search --match-exact --type package "$pkg" 2>/dev/null |
                awk -F'|' -v wanted="$pkg" '{
                    name=$2; type=$4
                    gsub(/^[ \t]+|[ \t]+$/, "", name)
                    gsub(/^[ \t]+|[ \t]+$/, "", type)
                    if (name == wanted && type == "package") found=1
                } END { exit(found ? 0 : 1) }'
            ;;
        apk)
            escaped=${pkg//./\\.}
            apk search -x "$pkg" 2>/dev/null | grep -Eq "^${escaped}-[0-9]" ;;
        xbps)
            escaped=${pkg//./\\.}
            xbps-query -Rs "^${escaped}-[0-9]" 2>/dev/null | grep -Eq "^[^ ]+ ${escaped}-[0-9]" ;;
        pacman)
            [[ "$DETECTED_DISTRO" == arch ]] && arch_official_package_available "$pkg" ;;
        *) return 1 ;;
    esac
}

resolve_package() {
    local tool=$1 pkg cache_key
    cache_key="$CURRENT_DISTRO:$DETECTED_DISTRO:$PACKAGE_MANAGER|$tool"
    if [[ -n "${RESOLVED_PACKAGE[$cache_key]:-}" ]]; then
        printf '%s' "${RESOLVED_PACKAGE[$cache_key]}"; return 0
    fi
    while IFS= read -r pkg; do
        [[ -n "$pkg" ]] || continue
        case "$CURRENT_DISTRO" in
            kali|parrot) official_apt_package_available "$pkg" || continue ;;
            arch) arch_official_package_available "$pkg" || continue ;;
            other) other_package_available "$pkg" || continue ;;
            *) continue ;;
        esac
        RESOLVED_PACKAGE[$cache_key]=$pkg
        printf '%s' "$pkg"
        return 0
    done < <(package_candidates_for_tool "$tool")
    return 1
}

package_installed() {
    local pkg=$1
    case "$(effective_package_manager)" in
        apt) dpkg-query -W -f='${Status}' -- "$pkg" 2>/dev/null | grep -q '^install ok installed$' ;;
        pacman) pacman -Q -- "$pkg" >/dev/null 2>&1 ;;
        dnf|zypper) rpm -q -- "$pkg" >/dev/null 2>&1 ;;
        apk) apk info -e "$pkg" >/dev/null 2>&1 ;;
        xbps) xbps-query -p pkgver "$pkg" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

resolve_installed_package() {
    local tool=$1 pkg
    while IFS= read -r pkg; do
        [[ -n "$pkg" ]] || continue
        package_installed "$pkg" && { printf '%s' "$pkg"; return 0; }
    done < <(package_candidates_for_tool "$tool")
    return 1
}

tool_installed() {
    local tool bin pkg
    tool=$1
    bin=${TOOL_BIN[$tool]:-}
    [[ -n "$bin" ]] && command -v "$bin" >/dev/null 2>&1 && return 0
    pkg=$(resolve_installed_package "$tool" 2>/dev/null) && [[ -n "$pkg" ]]
}

confirm_yes() {
    local text=$1 answer
    read -r -u 3 -p "$text [y/N]: " answer || return 1
    [[ "$answer" =~ ^[Yy]$ ]]
}

refresh_other_package_metadata() {
    case "$PACKAGE_MANAGER" in
        apt)
            apt_system_security_ok || return 1
            apt_system_options
            run_root apt-get "${APT_SYSTEM_OPTS[@]}" update
            ;;
        dnf) run_root "$PACKAGE_MANAGER_CMD" --setopt=gpgcheck=1 makecache --refresh ;;
        zypper) run_root zypper --non-interactive refresh ;;
        apk) run_root apk update ;;
        xbps) run_root xbps-install -S ;;
        pacman)
            [[ "$DETECTED_DISTRO" == arch ]] || { error "Package installation is disabled for pacman-based non-Arch systems."; return 1; }
            refresh_arch_query_database
            ;;
        *) error "Package installation is unavailable for detected manager: $PACKAGE_MANAGER"; return 1 ;;
    esac
}

refresh_package_index_for_lookup() {
    case "$CURRENT_DISTRO" in
        kali|parrot)
            official_apt_context || return 1
            apt_official_options
            run_root apt-get "${APT_OFFICIAL_OPTS[@]}" update
            ;;
        arch) refresh_arch_query_database ;;
        other) refresh_other_package_metadata ;;
    esac
}

refresh_official_package_metadata() {
    case "$CURRENT_DISTRO" in
        kali|parrot)
            official_apt_context || return 1
            apt_official_options
            run_root apt-get "${APT_OFFICIAL_OPTS[@]}" update
            ;;
        arch)
            write_arch_pacman_config || return 1
            run_root pacman --config "$ARCH_PACMAN_CONFIG" -Syu
            ;;
        other)
            refresh_other_package_metadata
            ;;
    esac
}

install_tool_package() {
    local tool=$1 pkg cache_key
    package_install_supported || {
        error "Automatic installation is unavailable for $DETECTED_DISTRO_NAME ($PACKAGE_MANAGER)."
        info "S.O.T remains usable with tools already installed on the system."
        return 1
    }
    cache_key="$CURRENT_DISTRO:$DETECTED_DISTRO:$PACKAGE_MANAGER|$tool"
    case "$CURRENT_DISTRO" in
        kali|parrot)
            official_apt_context || return 1
            apt_official_options
            warn "Only the hardcoded official ${CURRENT_DISTRO^} repository director is enabled for this transaction."
            confirm_yes "Refresh official metadata before resolving '$(tool_label "$tool")'?" || return 0
            run_root apt-get "${APT_OFFICIAL_OPTS[@]}" update || { error "Official repository refresh failed."; return 1; }
            unset "RESOLVED_PACKAGE[$cache_key]"
            pkg=$(resolve_package "$tool") || { error "No official package was found for '$tool'."; return 1; }
            printf '\n%b\n' "${WHITE}Tool:${RESET} $(tool_label "$tool")"
            printf '%b\n' "${WHITE}Official package:${RESET} $pkg"
            confirm_yes "Install '$pkg' with apt-get?" || return 0
            run_root apt-get "${APT_OFFICIAL_OPTS[@]}" install -- "$pkg"
            ;;
        arch)
            write_arch_pacman_config || return 1
            warn "Package lookup uses a separate user-owned database and does not alter the system package database."
            confirm_yes "Refresh the locked core/extra/multilib package index?" || return 0
            refresh_arch_query_database || { error "Official package-index refresh failed."; return 1; }
            unset "RESOLVED_PACKAGE[$cache_key]"
            pkg=$(resolve_package "$tool") || { error "No package for '$tool' exists in core, extra, or multilib."; return 1; }
            printf '\n%b\n' "${WHITE}Tool:${RESET} $(tool_label "$tool")"
            printf '%b\n' "${WHITE}Official package:${RESET} $pkg"
            warn "The installation uses pacman with S.O.T's locked core/extra/multilib configuration."
            warn "A full synchronized upgrade is included to avoid an unsupported partial upgrade."
            confirm_yes "Run pacman -Syu --needed for '$pkg'?" || return 0
            run_root pacman --config "$ARCH_PACMAN_CONFIG" -Syu --needed -- "$pkg"
            ;;
        other)
            warn "S.O.T will not add repositories or bypass package signature checks."
            if [[ "$PACKAGE_MANAGER" == pacman ]]; then
                write_arch_pacman_config || return 1
                confirm_yes "Refresh the locked core/extra/multilib package index?" || return 0
                refresh_arch_query_database || return 1
            else
                confirm_yes "Refresh signed repository metadata before resolving '$(tool_label "$tool")'?" || return 0
                refresh_other_package_metadata || { error "Package metadata refresh failed."; return 1; }
            fi
            unset "RESOLVED_PACKAGE[$cache_key]"
            pkg=$(resolve_package "$tool") || { error "No matching package was found in the enabled signed repositories."; return 1; }
            printf '\n%b\n' "${WHITE}Tool:${RESET} $(tool_label "$tool")"
            printf '%b\n' "${WHITE}Resolved package:${RESET} $pkg"
            case "$PACKAGE_MANAGER" in
                apt)
                    apt_system_security_ok || return 1; apt_system_options
                    confirm_yes "Install '$pkg' with apt-get?" || return 0
                    run_root apt-get "${APT_SYSTEM_OPTS[@]}" install -- "$pkg"
                    ;;
                dnf)
                    confirm_yes "Install '$pkg' with $PACKAGE_MANAGER_CMD and enforced package GPG checking?" || return 0
                    run_root "$PACKAGE_MANAGER_CMD" --setopt=gpgcheck=1 install "$pkg"
                    ;;
                zypper)
                    confirm_yes "Install '$pkg' with zypper?" || return 0
                    run_root zypper install --no-recommends "$pkg"
                    ;;
                apk)
                    confirm_yes "Install '$pkg' with apk?" || return 0
                    run_root apk add "$pkg"
                    ;;
                xbps)
                    confirm_yes "Install '$pkg' with xbps-install?" || return 0
                    run_root xbps-install "$pkg"
                    ;;
                pacman)
                    confirm_yes "Run pacman -Syu --needed for '$pkg' through the locked configuration?" || return 0
                    run_root pacman --config "$ARCH_PACMAN_CONFIG" -Syu --needed -- "$pkg"
                    ;;
            esac
            ;;
    esac
}

# ── Scope validation ──────────────────────────────────────────────────────────
ipv4_to_int() {
    local ip=$1 a b c d
    IFS=. read -r a b c d <<< "$ip"
    [[ $a =~ ^[0-9]+$ && $b =~ ^[0-9]+$ && $c =~ ^[0-9]+$ && $d =~ ^[0-9]+$ ]] || return 1
    (( a<=255 && b<=255 && c<=255 && d<=255 )) || return 1
    printf '%u' "$(( (a<<24) + (b<<16) + (c<<8) + d ))"
}

ipv4_in_cidr() {
    local ip cidr network bits ipn netn mask
    ip=$1; cidr=$2
    network=${cidr%/*}; bits=${cidr#*/}
    [[ $bits =~ ^[0-9]+$ ]] && (( bits>=0 && bits<=32 )) || return 1
    ipn=$(ipv4_to_int "$ip") || return 1
    netn=$(ipv4_to_int "$network") || return 1
    if (( bits == 0 )); then mask=0; else mask=$(( (0xFFFFFFFF << (32-bits)) & 0xFFFFFFFF )); fi
    (( (ipn & mask) == (netn & mask) ))
}

normalise_host() {
    local value=$1
    value=${value#*://}
    value=${value%%/*}
    value=${value%%\?*}
    value=${value%%#*}
    value=${value#*@}
    if [[ "$value" == \[*\]* ]]; then value=${value#[}; value=${value%%]*};
    elif [[ "$value" == *:* && "$value" != *:*:* ]]; then value=${value%%:*}; fi
    printf '%s' "${value,,}"
}

ipv4_cidr_within() {
    local child=$1 parent=$2 child_ip child_bits parent_ip parent_bits
    child_ip=${child%/*}; child_bits=${child#*/}
    parent_ip=${parent%/*}; parent_bits=${parent#*/}
    [[ "$child_bits" =~ ^[0-9]+$ && "$parent_bits" =~ ^[0-9]+$ ]] || return 1
    (( child_bits >= parent_bits && child_bits <= 32 && parent_bits <= 32 )) || return 1
    ipv4_to_int "$child_ip" >/dev/null || return 1
    ipv4_to_int "$parent_ip" >/dev/null || return 1
    ipv4_in_cidr "$child_ip" "$parent"
}

scope_allows_one() {
    local raw=$1 host item item_host raw_is_cidr=0 raw_bits
    if [[ "$raw" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
        ipv4_cidr_within "$raw" "$raw" || return 1
        raw_is_cidr=1
        raw_bits=${raw#*/}
    fi
    host=$(normalise_host "$raw")
    [[ -n "$host" ]] || return 1
    while IFS= read -r item; do
        item=${item%%#*}; item=${item//[[:space:]]/}
        [[ -n "$item" ]] || continue
        item_host=$(normalise_host "$item")
        if (( raw_is_cidr )); then
            if [[ "$item" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]]; then
                ipv4_cidr_within "$raw" "$item" && return 0
            elif [[ "$item_host" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && (( raw_bits == 32 )); then
                [[ "$host" == "$item_host" ]] && return 0
            fi
            continue
        fi
        if [[ "$item" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] && [[ "$host" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            ipv4_in_cidr "$host" "$item" && return 0
        elif [[ "$item_host" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ || "$item_host" =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ || "$item_host" == *:* ]]; then
            [[ "$host" == "$item_host" ]] && return 0
        elif [[ "$host" == "$item_host" || "$host" == *."$item_host" ]]; then
            return 0
        fi
    done < "$(scope_file)"
    return 1
}

scope_check_value() {
    local key=$1 value=$2 part strict=0
    local -a parts=()
    [[ "$STRICT_SCOPE" == 1 || "$ACTIVE_MODE" == engagement ]] && strict=1
    if [[ ! -s "$(scope_file)" ]]; then
        if (( strict )); then error "Strict scope is enabled but the scope list is empty."; return 1; fi
        return 0
    fi
    if [[ "$key" == url_file ]]; then
        [[ -r "$value" ]] || { error "Cannot read URL file: $value"; return 1; }
        while IFS= read -r part; do
            [[ -z "$part" || "$part" == \#* ]] && continue
            scope_allows_one "$part" || {
                if (( strict )); then error "Blocked out-of-scope entry in $value: $part"; return 1
                else warn "URL-file entry is not in scope: $part"; confirm_yes "Continue in $ACTIVE_MODE mode?" || return 1; fi
            }
        done < "$value"
        return 0
    fi
    IFS=',' read -ra parts <<< "$value"
    for part in "${parts[@]}"; do
        scope_allows_one "$part" || {
            if (( strict )); then error "Blocked out-of-scope target: $part"; return 1
            else warn "Target is not in scope: $part"; confirm_yes "Continue in $ACTIVE_MODE mode?" || return 1; fi
        }
    done
}

validate_scope_item() {
    local item=$1 host
    [[ -n "$item" && "$item" != *[[:space:]]* ]] || { error "Scope entries cannot be empty or contain whitespace."; return 1; }
    contains_control_chars "$item" && { error "Control characters are not allowed."; return 1; }
    if [[ "$item" == */* ]]; then
        host=${item%/*}
        [[ "$host" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] && ipv4_in_cidr "$host" "$item" || {
            error "Invalid IPv4 CIDR: $item"; return 1; }
    else
        host=$(normalise_host "$item")
        if [[ "$host" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
            ipv4_to_int "$host" >/dev/null || { error "Invalid IPv4 address: $item"; return 1; }
        elif [[ "$host" =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]]; then
            :
        elif [[ "$host" == *:* ]]; then
            command -v python3 >/dev/null 2>&1 && python3 - "$host" <<'PYIP' >/dev/null 2>&1 || {
import ipaddress, sys
ipaddress.ip_address(sys.argv[1])
PYIP
                error "Invalid IPv6 address: $item"; return 1;
            }
        else
            [[ "$host" =~ ^([A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?$ ]] || {
                error "Invalid hostname or domain: $item"; return 1; }
        fi
    fi
}

scope_key() {
    case "$1" in
        target|target_or_cidr|cidr|domain|host|ip|dc_ip|url|repo_url|url_file|nameserver|bssid|client_mac) return 0 ;;
        *) return 1 ;;
    esac
}

# ── Command rendering and execution ──────────────────────────────────────────
declare -A PLACEHOLDER_VALUE=()
declare -a SENSITIVE_VALUES=()
RENDERED_CMD=""
AUDIT_CMD=""

prompt_hint() {
    case "$1" in
        target) printf 'target IP or hostname' ;; cidr) printf 'CIDR, e.g. 192.168.1.0/24' ;;
        target_or_cidr) printf 'target IP, hostname or CIDR' ;; url) printf 'URL including scheme' ;;
        domain) printf 'domain name' ;; host) printf 'host' ;; ip) printf 'IP address' ;;
        wireless_card) printf 'managed wireless interface, e.g. wlan0' ;;
        monitor_interface) printf 'monitor interface, e.g. wlan0mon' ;;
        iface) printf 'network interface' ;; bssid) printf 'BSSID MAC address' ;;
        client_mac) printf 'client MAC address' ;; wordlist) printf 'wordlist path' ;;
        password) printf 'password (hidden)' ;; token) printf 'token (hidden)' ;;
        command) printf 'command and arguments' ;; *) printf '%s' "$1" ;;
    esac
}

contains_control_chars() { local LC_ALL=C; [[ "$1" =~ [[:cntrl:]] ]]; }

validate_interface() {
    local iface=$1
    [[ "$iface" =~ ^[A-Za-z0-9_.:-]{1,32}$ ]] || { error "Invalid interface name."; return 1; }
    ip link show dev "$iface" >/dev/null 2>&1 || iw dev 2>/dev/null | awk '$1=="Interface"{print $2}' | grep -Fxq -- "$iface" || {
        error "Interface not found: $iface"; return 1; }
}

normalise_output_path() {
    local value=$1 base parent_rel path
    base="$(workspace_path)/loot"
    safe_mkdir "$base" || return 1
    safe_relative_path "$value" || {
        error "Use a relative output path without '.', '..', empty components, or control characters."
        return 1
    }
    if [[ "$value" == */* ]]; then
        parent_rel=${value%/*}
        safe_mkdir_under "$base" "$parent_rel" >/dev/null || return 1
    fi
    path=$(safe_child_path "$base" "$value") || return 1
    printf '%s' "$path"
}

validate_port_spec() {
    local spec=$1 part start end
    local -a parts=()
    [[ "$spec" =~ ^[0-9,-]+$ ]] || { error "Ports must use numbers, commas, or ranges."; return 1; }
    IFS=',' read -r -a parts <<< "$spec"
    ((${#parts[@]})) || return 1
    for part in "${parts[@]}"; do
        if [[ "$part" =~ ^([0-9]{1,5})-([0-9]{1,5})$ ]]; then
            start=${BASH_REMATCH[1]}; end=${BASH_REMATCH[2]}
            (( start >= 1 && start <= 65535 && end >= 1 && end <= 65535 && start <= end )) || {
                error "Invalid port range: $part"; return 1; }
        elif [[ "$part" =~ ^[0-9]{1,5}$ ]]; then
            (( part >= 1 && part <= 65535 )) || { error "Invalid port: $part"; return 1; }
        else
            error "Invalid port specification: $part"; return 1
        fi
    done
}

validate_value() {
    local key=$1 value=$2
    [[ -n "$value" ]] || { error "A value is required for $key."; return 1; }
    contains_control_chars "$value" && { error "Control characters are not allowed."; return 1; }
    case "$key" in
        wireless_card|monitor_interface|iface)
            validate_interface "$value" || return 1 ;;
        port)
            [[ "$value" =~ ^[0-9]{1,5}$ ]] && (( value >= 1 && value <= 65535 )) || {
                error "Port must be between 1 and 65535."; return 1; } ;;
        ports)
            validate_port_spec "$value" || return 1 ;;
        channel)
            [[ "$value" =~ ^[0-9]{1,3}$ ]] && (( value >= 1 && value <= 233 )) || {
                error "Wireless channel must be between 1 and 233."; return 1; } ;;
        depth|limit|max|min|min_length|rate)
            [[ "$value" =~ ^[0-9]{1,9}$ ]] && (( value >= 1 )) || { error "$key must be a positive number."; return 1; } ;;
        mode)
            [[ "$value" =~ ^[0-9]{1,9}$ ]] || { error "$key must be numeric."; return 1; } ;;
        bssid|client_mac)
            [[ "$value" =~ ^([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}$ ]] || { error "Invalid MAC address."; return 1; } ;;
        url|repo_url)
            [[ "$value" =~ ^https?:// ]] || { error "Use a full http:// or https:// URL."; return 1; } ;;
        file|hash_file|wordlist|url_file|community_file|request_file|resource_file|pcap_file|capture_file|image_file|memory_image|apk_file|passwords|users)
            [[ -f "$value" && -r "$value" ]] || { error "Input file is not a readable regular file: $value"; return 1; } ;;
        templates)
            [[ ( -f "$value" || -d "$value" ) && -r "$value" ]] || { error "Template path is not readable: $value"; return 1; } ;;
        folder)
            [[ -d "$value" && -r "$value" ]] || { error "Input folder is not a readable directory: $value"; return 1; } ;;
    esac
    scope_key "$key" && scope_check_value "$key" "$value" || {
        scope_key "$key" && return 1 || true
    }
}

render_template() {
    local template=$1 key hint value quoted audit_repl
    PLACEHOLDER_VALUE=()
    SENSITIVE_VALUES=()
    RENDERED_CMD=$template
    AUDIT_CMD=$template
    while [[ "$RENDERED_CMD" =~ \{([A-Za-z0-9_]+)\} ]]; do
        key=${BASH_REMATCH[1]}
        if [[ -v "PLACEHOLDER_VALUE[$key]" ]]; then
            value=${PLACEHOLDER_VALUE[$key]}
        else
            hint=$(prompt_hint "$key")
            if [[ "$key" == password || "$key" == token ]]; then
                read -r -s -u 3 -p "$hint: " value; printf '\n'
            else
                read -r -u 3 -p "$hint: " value
            fi
            validate_value "$key" "$value" || return 1
            case "$key" in
                output_file|output_dir|capture_prefix)
                    value=$(normalise_output_path "$value") || return 1 ;;
            esac
            PLACEHOLDER_VALUE[$key]=$value
        fi
        printf -v quoted '%q' "$value"
        if [[ "$key" == password || "$key" == token || "$key" == post_data ]]; then
            audit_repl="<redacted:$key>"
            SENSITIVE_VALUES+=("$value")
        else
            audit_repl=$quoted
        fi
        RENDERED_CMD=${RENDERED_CMD//\{$key\}/$quoted}
        AUDIT_CMD=${AUDIT_CMD//\{$key\}/$audit_repl}
    done
}

catastrophic_command() {
    local cmd=" $1 "
    local disk_re='(^|[[:space:];|&])(mkfs(\.[A-Za-z0-9]+)?|wipefs|fdisk|cfdisk|sfdisk|parted)([[:space:];|&]|$)'
    local power_re='(shutdown|poweroff|halt|reboot)([[:space:];|&]|$)'
    [[ "$cmd" =~ rm[[:space:]]+(-[^[:space:]]*[rf][^[:space:]]*[[:space:]]+)*(/|/\*|--no-preserve-root) ]] ||
    [[ "$cmd" =~ $disk_re ]] ||
    [[ "$cmd" =~ dd[[:space:]].*of=/dev/ ]] ||
    [[ "$cmd" =~ $power_re ]] ||
    [[ "$cmd" == *':(){:|:&};:'* ]]
}

high_risk_command() {
    local cmd=$1
    [[ "$cmd" =~ (hydra|ncrack|reaver|pixiewps|aireplay-ng[[:space:]].*-0|msfvenom|responder|commix|sqlmap|masscan|setoolkit|bettercap|ettercap|wifite|hcxdumptool|netexec|crackmapexec|evil-winrm|bloodhound-python|ldapdomaindump|gvm-(setup|start|stop)) ]]
}

system_change_command() {
    local cmd=$1
    [[ "$cmd" =~ (macchanger|ip[[:space:]]+link[[:space:]]+set|systemctl|service[[:space:]]|rfkill|airmon-ng|nmcli[[:space:]]+radio|pacman|apt-get|dnf5?|zypper|apk[[:space:]]+(add|del|upgrade)|xbps-install|gvm-(setup|start|stop)) ]]
}

output_log_path() {
    local source=$1 stamp
    stamp=$(date '+%Y%m%d_%H%M%S')
    private_temp_file "$(evidence_dir)" "${stamp}_$(safe_name "$source")" '.log'
}

append_history() {
    local ts=$1 source=$2 rc=$3 logfile=$4 command=$5
    command=${command//$'\t'/ }
    command=${command//$'\n'/ }
    printf '%s\t%s\t%s\t%s\t%s\n' "$ts" "$source" "$rc" "$logfile" "$command" >> "$(history_file)"
}

redact_output_stream() {
    local line secret
    while IFS= read -r line || [[ -n "$line" ]]; do
        for secret in "${SENSITIVE_VALUES[@]}"; do
            [[ -n "$secret" ]] && line=${line//"$secret"/<redacted>}
        done
        printf '%s\n' "$line"
    done
}

clean_result_stream() {
    local line lower
    while IFS= read -r line || [[ -n "$line" ]]; do
        lower=${line,,}
        case "$lower" in
            *"legal disclaimer"*|\
            *"attacking targets without prior mutual consent is illegal"*|\
            *"end user's responsibility to obey all applicable"*|\
            *"end users responsibility to obey all applicable"*|\
            *"developers assume no liability"*|\
            *"developer assumes no liability"*|\
            *"authors assume no liability"*|\
            *"author assumes no liability"*|\
            *"terms of use"*|\
            *"terms of service"*|\
            *"use this tool responsibly"*) continue ;;
        esac
        printf '%s\n' "$line"
    done
}

execute_shell_command() {
    local command=$1 source=${2:-manual} audit=${3:-$1} logfile rc ts run_dir answer
    run_dir=$(workspace_path)
    if [[ "$command" == *'sudo '* ]] && ! command -v sudo >/dev/null 2>&1; then
        if command -v doas >/dev/null 2>&1; then
            command=${command//sudo /doas }
            audit=${audit//sudo /doas }
        else
            error "This mapped action needs sudo or doas, but neither privilege helper is installed."
            return 1
        fi
    fi
    catastrophic_command "$command" && {
        error "Blocked a destructive disk, root-filesystem, shutdown, or fork-bomb command."; return 1; }
    if high_risk_command "$command"; then
        read -r -u 3 -p "Type RUN to execute the selected action: " answer || return 1
        [[ "$answer" == RUN ]] || return 0
    elif system_change_command "$command"; then
        read -r -u 3 -p "Type CHANGE to execute the selected action: " answer || return 1
        [[ "$answer" == CHANGE ]] || return 0
    else
        if [[ "$ACTIVE_MODE" == "lab" ]]; then
            printf '\n%b\n' "${WHITE}${BOLD}Command to execute:${RESET}"
            printf '%s\n\n' "$audit"
        fi
        confirm_yes "Run the selected action?" || return 0
    fi
    logfile=$(output_log_path "$source") || { error "Could not create an evidence log."; return 1; }
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    printf '# S.O.T command log\n# time: %s\n# distro: %s\n# package-manager: %s\n# workspace: %s\n# working-directory: %s\n# command: %s\n\n' \
        "$ts" "$(distro_display)" "$(effective_package_manager)" "$ACTIVE_WORKSPACE" "$run_dir" "$audit" > "$logfile"
    clear_screen
    (cd -- "$run_dir" && bash --noprofile --norc -o pipefail -c "$command") \
        2>&1 | redact_output_stream | tee -a -- "$logfile" | clean_result_stream
    rc=${PIPESTATUS[0]}
    append_history "$ts" "$source" "$rc" "$logfile" "$audit"
    return "$rc"
}


# ── theHarvester all-source workflow ─────────────────────────────────────────
theharvester_supported_fallback_sources() {
    local help_text source
    local -a candidates=(
        baidu certspotter commoncrawl crtsh duckduckgo gitlab hackertarget
        hudsonrock otx rapiddns robtex shodanInternetDB subdomaincenter
        subdomainfinderc99 thc threatcrowd urlscan waybackarchive yahoo
    )
    help_text=$(theHarvester -h 2>&1 || true)
    for source in "${candidates[@]}"; do
        if grep -Eiq "(^|[^[:alnum:]_-])${source}([^[:alnum:]_-]|$)" <<< "$help_text"; then
            printf '%s\n' "$source"
        fi
    done
}

theharvester_output_has_results() {
    local file=$1
    grep -Eiq \
        '(^|[^[:alpha:]])(hosts?|emails?|ips?|urls?|asns?|interesting urls?|people|linkedin links?)[[:space:]]+(found|discovered)|\[\*\][[:space:]]+(hosts?|emails?|ips?|urls?|asns?)' \
        "$file"
}

theharvester_output_is_fatal() {
    local file=$1
    grep -Eiq \
        'traceback \(most recent call last\)|invalid source|failed to initialize|no module named|unhandled exception|fatal error|argument .* is required' \
        "$file"
}

theharvester_run_pass() {
    local domain=$1 limit=$2 source=$3 resolve_dns=$4 output_file=$5
    local -a cmd=(theHarvester -d "$domain" -l "$limit" -b "$source")
    [[ "$resolve_dns" == 1 ]] && cmd+=(-r)
    "${cmd[@]}" 2>&1 | tee -- "$output_file"
    return "${PIPESTATUS[0]}"
}

theharvester_workflow() {
    local mode=$1 domain limit resolve_dns=0 answer logfile ts rc=0 all_rc=0 fallback_rc=0
    local all_output fallback_output source csv run_dir
    local -a fallback_sources=()

    command -v theHarvester >/dev/null 2>&1 || {
        error "theHarvester is not installed or is not available in PATH."
        return 1
    }

    read -r -u 3 -p "Domain name: " domain || return 1
    validate_value domain "$domain" || return 1

    case "$mode" in
        quick) limit=200 ;;
        deep) limit=1000 ;;
        full|resolve)
            read -r -u 3 -p "Result limit [500]: " limit || return 1
            limit=${limit:-500}
            validate_value limit "$limit" || return 1
            (( limit >= 1 && limit <= 100000 )) || {
                error "Result limit must be between 1 and 100000."
                return 1
            }
            ;;
        *) error "Unknown theHarvester workflow mode."; return 1 ;;
    esac
    [[ "$mode" == resolve ]] && resolve_dns=1

    if [[ "$ACTIVE_MODE" == lab ]]; then
        printf '
%b
' "${WHITE}${BOLD}Command to execute:${RESET}"
        printf 'theHarvester -d %q -l %q -b all' "$domain" "$limit"
        [[ "$resolve_dns" == 1 ]] && printf ' -r'
        printf '
'
        while IFS= read -r source; do
            [[ -n "$source" ]] || continue
            fallback_sources+=("$source")
        done < <(theharvester_supported_fallback_sources)
        if ((${#fallback_sources[@]})); then
            printf '
Conditional fallback commands (only if the all-source pass fails or returns no results):
'
            for source in "${fallback_sources[@]}"; do
                printf 'theHarvester -d %q -l %q -b %q' "$domain" "$limit" "$source"
                [[ "$resolve_dns" == 1 ]] && printf ' -r'
                printf '
'
            done
        fi
        printf '
'
    fi

    confirm_yes "Run all available theHarvester sources with automatic fallback?" || return 0

    run_dir=$(workspace_path)
    logfile=$(output_log_path theHarvester) || {
        error "Could not create an evidence log."
        return 1
    }
    all_output=$(private_temp_file "$(workspace_path)/tmp" theharvester-all '.out') || return 1
    fallback_output=$(private_temp_file "$(workspace_path)/tmp" theharvester-fallback '.out') || {
        rm -f -- "$all_output"
        return 1
    }
    ts=$(date '+%Y-%m-%d %H:%M:%S')
    printf '# S.O.T command log\n# time: %s\n# distro: %s\n# package-manager: %s\n# workspace: %s\n# working-directory: %s\n# command: theHarvester -d %q -l %q -b all%s\n\n' \
        "$ts" "$(distro_display)" "$(effective_package_manager)" "$ACTIVE_WORKSPACE" "$run_dir" \
        "$domain" "$limit" "$([[ "$resolve_dns" == 1 ]] && printf ' -r')" > "$logfile"

    clear_screen
    {
        theharvester_run_pass "$domain" "$limit" all "$resolve_dns" "$all_output"
        all_rc=$?

        if (( all_rc != 0 )) || theharvester_output_is_fatal "$all_output" || ! theharvester_output_has_results "$all_output"; then
            if ((${#fallback_sources[@]} == 0)); then
                while IFS= read -r source; do
                    [[ -n "$source" ]] && fallback_sources+=("$source")
                done < <(theharvester_supported_fallback_sources)
            fi

            if ((${#fallback_sources[@]})); then
                printf '\n===== AUTOMATIC FALLBACK RESULTS =====\n\n'

                : > "$fallback_output"
                fallback_rc=1
                for source in "${fallback_sources[@]}"; do
                    printf '\n===== SOURCE: %s =====\n' "$source"
                    if theharvester_run_pass "$domain" "$limit" "$source" "$resolve_dns" "$fallback_output.$source"; then
                        fallback_rc=0
                    fi
                    cat -- "$fallback_output.$source" >> "$fallback_output"
                    rm -f -- "$fallback_output.$source"
                done
                rc=$fallback_rc
            else
                printf '\nNo supported fallback sources could be identified from this installed theHarvester version.\n'
                rc=$all_rc
            fi
        else
            rc=$all_rc
        fi
        exit "$rc"
    } 2>&1 | redact_output_stream | tee -a -- "$logfile" | clean_result_stream
    rc=${PIPESTATUS[0]}

    append_history "$ts" theHarvester "$rc" "$logfile" \
        "theHarvester all sources + automatic fallback; domain=$domain; limit=$limit; dns_resolve=$resolve_dns"

    rm -f -- "$all_output" "$fallback_output"
    return "$rc"
}

# ── Wireless monitor mode ─────────────────────────────────────────────────────
list_wireless_interfaces() {
    if command -v iw >/dev/null 2>&1; then
        iw dev 2>/dev/null | awk '$1=="Interface"{print $2}'
    fi
}

validate_wireless_interface() {
    local iface=$1
    [[ "$iface" =~ ^[A-Za-z0-9_.:-]{1,32}$ ]] || { error "Invalid wireless interface name."; return 1; }
    list_wireless_interfaces | grep -Fxq -- "$iface" || {
        error "Wireless interface not found in 'iw dev': $iface"
        return 1
    }
}

wireless_interface_type() {
    local iface=$1
    iw dev "$iface" info 2>/dev/null | awk '$1=="type"{print $2; exit}'
}

wireless_interface_phy() {
    local iface=$1 number
    number=$(iw dev "$iface" info 2>/dev/null | awk '$1=="wiphy"{print $2; exit}')
    [[ "$number" =~ ^[0-9]+$ ]] || return 1
    printf 'phy#%s' "$number"
}

monitor_interface_on_phy() {
    local wanted=$1
    iw dev 2>/dev/null | awk -v wanted="$wanted" '
        /^phy#[0-9]+/ { phy=$1 }
        $1=="Interface" { iface=$2 }
        $1=="type" && $2=="monitor" && phy==wanted { print iface; exit }
    '
}

record_active_network_services() {
    local state="$(workspace_path)/monitor-services.state" tmp svc
    tmp=$(mktemp "$(workspace_path)/tmp/monitor-services.XXXXXX") || return 1
    if command -v systemctl >/dev/null 2>&1; then
        for svc in NetworkManager.service iwd.service wpa_supplicant.service; do
            systemctl is-active --quiet "$svc" && printf '%s\n' "$svc" >> "$tmp"
        done
    fi
    chmod 600 "$tmp" || { rm -f -- "$tmp"; return 1; }
    mv -f -- "$tmp" "$state" || { rm -f -- "$tmp"; return 1; }
}

restart_recorded_network_services() {
    local state="$(workspace_path)/monitor-services.state" svc failed=0 restarted=0
    if command -v systemctl >/dev/null 2>&1 && [[ -s "$state" ]]; then
        while IFS= read -r svc; do
            [[ "$svc" =~ ^(NetworkManager|iwd|wpa_supplicant)\.service$ ]] || continue
            run_root systemctl restart "$svc" && restarted=1 || failed=1
        done < "$state"
    elif command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files NetworkManager.service --no-legend 2>/dev/null | grep -q NetworkManager; then
        run_root systemctl restart NetworkManager.service && restarted=1 || failed=1
    elif command -v service >/dev/null 2>&1; then
        if service --status-all 2>&1 | grep -Eq 'network-manager|NetworkManager'; then
            run_root service network-manager restart 2>/dev/null || run_root service NetworkManager restart
            [[ $? -eq 0 ]] && restarted=1 || failed=1
        else
            warn "No known network-manager service was found."
            failed=1
        fi
    else
        warn "No supported service manager was found; restart your network manager manually."
        failed=1
    fi
    return "$failed"
}

monitor_on() {
    local iface answer logfile rc phy monitor_iface monitor_state managed_type
    command -v airmon-ng >/dev/null 2>&1 || { error "airmon-ng is not installed."; return 1; }
    command -v iw >/dev/null 2>&1 || { error "iw is not installed."; return 1; }
    command -v sudo >/dev/null 2>&1 || command -v doas >/dev/null 2>&1 || { error "sudo or doas is required for monitor mode."; return 1; }
    printf '%b\n' "${WHITE}Wireless interfaces:${RESET}"
    list_wireless_interfaces | sed 's/^/  - /'
    read -r -u 3 -p "Managed wireless interface: " iface
    validate_wireless_interface "$iface" || return 1
    managed_type=$(wireless_interface_type "$iface")
    [[ "$managed_type" == managed ]] || {
        error "Interface '$iface' is in '$managed_type' mode, not managed mode."
        return 1
    }
    phy=$(wireless_interface_phy "$iface") || {
        error "Could not determine the wireless PHY for: $iface"
        return 1
    }
    warn "airmon-ng check kill can disconnect Wi-Fi and stop network-management processes."
    read -r -u 3 -p "Type MONITOR to continue: " answer
    [[ "$answer" == MONITOR ]] || { warn "Cancelled."; return 0; }
    record_active_network_services || { error "Could not record network service state."; return 1; }
    local state_tmp
    state_tmp=$(mktemp "$(workspace_path)/tmp/managed-interface.XXXXXX") || return 1
    printf '%s\n' "$iface" > "$state_tmp"
    chmod 600 "$state_tmp" || { rm -f -- "$state_tmp"; return 1; }
    mv -f -- "$state_tmp" "$(workspace_path)/managed-interface.state" || { rm -f -- "$state_tmp"; return 1; }
    logfile=$(output_log_path monitor_on) || { error "Could not create an evidence log."; return 1; }
    {
        run_root airmon-ng check kill && run_root airmon-ng start "$iface"
        rc=$?
        iw dev || true
        exit "$rc"
    } 2>&1 | tee -- "$logfile" | clean_result_stream
    rc=${PIPESTATUS[0]}
    if (( rc == 0 )); then
        for _ in 1 2 3; do
            monitor_iface=$(monitor_interface_on_phy "$phy")
            [[ -n "$monitor_iface" ]] && break
            sleep 1
        done
        if [[ -z "$monitor_iface" ]]; then
            printf '%s\n' "Monitor-mode verification failed: no monitor interface appeared on $phy." | tee -a -- "$logfile" >&2
            rc=1
        else
            monitor_state="$(workspace_path)/monitor-interface.state"
            ensure_private_file "$monitor_state" || rc=1
            (( rc != 0 )) || printf '%s\n' "$monitor_iface" > "$monitor_state"
        fi
    fi
    append_history "$(date '+%Y-%m-%d %H:%M:%S')" monitor_on "$rc" "$logfile" "airmon-ng monitor on $iface"
    if (( rc != 0 )); then
        error "Monitor-mode setup failed. Attempting to restore networking."
        monitor_iface=$(monitor_interface_on_phy "$phy" || true)
        [[ -n "$monitor_iface" ]] && run_root airmon-ng stop "$monitor_iface" || true
        if list_wireless_interfaces | grep -Fxq -- "$iface"; then
            [[ "$(wireless_interface_type "$iface")" == managed ]] || run_root iw dev "$iface" set type managed || true
            run_root ip link set dev "$iface" up || true
        fi
        restart_recorded_network_services || true
        command -v rfkill >/dev/null 2>&1 && run_root rfkill unblock wifi || true
        if command -v nmcli >/dev/null 2>&1; then nmcli radio wifi on >/dev/null 2>&1 || run_root nmcli radio wifi on >/dev/null 2>&1 || true; fi
    fi
    return "$rc"
}

monitor_off() {
    local mon managed answer logfile rc=0 step_rc mon_default managed_type
    command -v airmon-ng >/dev/null 2>&1 || { error "airmon-ng is not installed."; return 1; }
    command -v iw >/dev/null 2>&1 || { error "iw is not installed."; return 1; }
    printf '%b\n' "${WHITE}Current wireless interfaces:${RESET}"
    list_wireless_interfaces | sed 's/^/  - /'
    if [[ -r "$(workspace_path)/monitor-interface.state" ]]; then mon_default=$(<"$(workspace_path)/monitor-interface.state"); fi
    read -r -u 3 -p "Monitor interface to stop [${mon_default:-wlan0mon}]: " answer
    mon=${answer:-${mon_default:-wlan0mon}}
    validate_wireless_interface "$mon" || return 1
    [[ "$(wireless_interface_type "$mon")" == monitor ]] || {
        error "Interface '$mon' is not currently in monitor mode."
        return 1
    }
    if [[ -r "$(workspace_path)/managed-interface.state" ]]; then managed=$(<"$(workspace_path)/managed-interface.state"); fi
    read -r -u 3 -p "Managed interface to restore [${managed:-wlan0}]: " answer
    managed=${answer:-${managed:-wlan0}}
    [[ "$managed" =~ ^[A-Za-z0-9_.:-]{1,32}$ ]] || { error "Invalid managed interface."; return 1; }
    read -r -u 3 -p "Type RESTORE to stop monitor mode and restart networking: " answer
    [[ "$answer" == RESTORE ]] || { warn "Cancelled."; return 0; }
    logfile=$(output_log_path monitor_off) || { error "Could not create an evidence log."; return 1; }
    {
        run_root airmon-ng stop "$mon"; step_rc=$?; (( step_rc == 0 )) || rc=1
        for step_rc in 1 2 3; do
            list_wireless_interfaces | grep -Fxq -- "$managed" && break
            sleep 1
        done
        if list_wireless_interfaces | grep -Fxq -- "$managed"; then
            managed_type=$(wireless_interface_type "$managed")
            if [[ "$managed_type" != managed ]]; then
                run_root iw dev "$managed" set type managed || rc=1
            fi
            run_root ip link set dev "$managed" up || rc=1
        else
            printf '# Managed interface did not reappear: %s\n' "$managed"
            rc=1
        fi
        restart_recorded_network_services || rc=1
        command -v rfkill >/dev/null 2>&1 && run_root rfkill unblock wifi || true
        if command -v nmcli >/dev/null 2>&1; then nmcli radio wifi on || run_root nmcli radio wifi on || true; fi
        sleep 1
        if list_wireless_interfaces | grep -Fxq -- "$managed" && [[ "$(wireless_interface_type "$managed")" == managed ]]; then
            run_root ip link set dev "$managed" up || rc=1
        else
            printf '# Managed-mode verification failed for: %s\n' "$managed"
            rc=1
        fi
        iw dev || true
        command -v nmcli >/dev/null 2>&1 && nmcli radio wifi || true
        exit "$rc"
    } 2>&1 | tee -- "$logfile" | clean_result_stream
    rc=${PIPESTATUS[0]}
    append_history "$(date '+%Y-%m-%d %H:%M:%S')" monitor_off "$rc" "$logfile" "airmon-ng monitor off $mon restore $managed"
    if (( rc == 0 )); then
        rm -f -- "$(workspace_path)/monitor-interface.state" "$(workspace_path)/managed-interface.state"
    else
        error "One or more restoration steps failed. Review: $logfile"
    fi
    return "$rc"
}

# ── Menus ─────────────────────────────────────────────────────────────────────
choose_tool_from_all() {
    local cat tool i=1 choice
    local -a tools=() labels=()
    for cat in "${CATEGORIES[@]}"; do
        while IFS= read -r tool; do [[ -n "$tool" ]] && { tools+=("$tool"); labels+=("$cat"); }; done <<< "${CATEGORY_TOOLS[$cat]}"
    done
    while true; do
        header
        printf '%b\n\n' "${WHITE}${BOLD}SELECT TOOL${RESET}"
        for ((i=0; i<${#tools[@]}; i++)); do
            printf '%3d. %-24s %s\n' "$((i+1))" "$(tool_label "${tools[$i]}")" "${labels[$i]}"
        done
        printf 'Q. Back\n\n'
        read -r -u 3 -p "Select an option: " choice
        [[ "$choice" =~ ^[Qq]$ ]] && return 1
        [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=${#tools[@]} )) || { error "Invalid option."; sleep 1; continue; }
        SELECTED_TOOL=${tools[$((choice-1))]}
        return 0
    done
}

run_tool_function() {
    local tool idx encoded template
    tool=$1; idx=$2
    encoded=${TOOL_FUNC_CMD_B64[$tool|$idx]}
    template=$(decode_b64 "$encoded") || { error "Could not decode the mapped command."; return 1; }
    case "$template" in
        __monitor_on__) monitor_on ;;
        __monitor_off__) monitor_off ;;
        __theharvester_full__) theharvester_workflow full ;;
        __theharvester_quick__) theharvester_workflow quick ;;
        __theharvester_deep__) theharvester_workflow deep ;;
        __theharvester_resolve__) theharvester_workflow resolve ;;
        *)
            render_template "$template" || return 1
            execute_shell_command "$RENDERED_CMD" "$tool" "$AUDIT_CMD"
            ;;
    esac
}

tool_menu() {
    local tool=$1 choice i count
    while true; do
        header
        printf '%b\n' "${WHITE}${BOLD}$(tool_label "$tool")${RESET}"
        printf '%b\n\n' "${GREY}${TOOL_HINT[$tool]}${RESET}"
        if tool_installed "$tool"; then printf '%b\n\n' "${NEON}Status: installed/found${RESET}"
        else printf '%b\n\n' "${ORANGE}Status: not found${RESET}"; fi
        count=${TOOL_FUNC_COUNT[$tool]:-0}
        for ((i=1; i<=count; i++)); do printf '%2d. %s\n' "$i" "${TOOL_FUNC_LABEL[$tool|$i]}"; done
        printf 'I. Install from allowed repository\n'
        printf 'Q. Back\n\n'
        read -r -u 3 -p "Select an option: " choice
        case "$choice" in
            q|Q) return ;;
            i|I) install_tool_package "$tool"; pause ;;
            *)
                [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=count )) || { error "Invalid option."; sleep 1; continue; }
                run_tool_function "$tool" "$choice"; pause
                ;;
        esac
    done
}

category_menu() {
    local cat=$1 tool choice i
    local -a tools=()
    while IFS= read -r tool; do [[ -n "$tool" ]] && tools+=("$tool"); done <<< "${CATEGORY_TOOLS[$cat]}"
    while true; do
        header
        printf '%b\n\n' "${WHITE}${BOLD}${cat}${RESET}"
        for ((i=0; i<${#tools[@]}; i++)); do
            tool=${tools[$i]}
            if tool_installed "$tool"; then
                printf '%2d. %-26s %b\n' "$((i+1))" "$(tool_label "$tool")" "${NEON}[installed]${RESET}"
            else
                printf '%2d. %-26s %b\n' "$((i+1))" "$(tool_label "$tool")" "${GREY}[not found]${RESET}"
            fi
        done
        printf 'Q. Back\n\n'
        read -r -u 3 -p "Select an option: " choice
        [[ "$choice" =~ ^[Qq]$ ]] && return
        [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=${#tools[@]} )) || { error "Invalid option."; sleep 1; continue; }
        tool_menu "${tools[$((choice-1))]}"
    done
}

tools_by_category() {
    local choice i
    while true; do
        header
        printf '%b\n\n' "${WHITE}${BOLD}TOOLS BY CATEGORY${RESET}"
        for ((i=0; i<${#CATEGORIES[@]}; i++)); do printf '%2d. %s\n' "$((i+1))" "${CATEGORIES[$i]}"; done
        printf 'Q. Back\n\n'
        read -r -u 3 -p "Select an option: " choice
        [[ "$choice" =~ ^[Qq]$ ]] && return
        [[ "$choice" =~ ^[0-9]+$ ]] && (( choice>=1 && choice<=${#CATEGORIES[@]} )) || { error "Invalid option."; sleep 1; continue; }
        category_menu "${CATEGORIES[$((choice-1))]}"
    done
}

install_remove_menu() {
    local choice pkg manager cache_key
    while true; do
        header
        manager=$(effective_package_manager)
        printf '%b\n\n' "${WHITE}${BOLD}INSTALL / VERIFY TOOLS${RESET}"
        printf 'Detected package manager: %s\n\n' "$manager"
        printf '1. Install a mapped tool\n'
        printf '2. Verify a mapped package is available\n'
        printf '3. Refresh trusted package metadata / supported system update\n'
        printf 'Q. Back\n\n'
        read -r -u 3 -p "Select an option: " choice
        case "$choice" in
            1) choose_tool_from_all && install_tool_package "$SELECTED_TOOL"; pause ;;
            2)
                if choose_tool_from_all; then
                    if ! package_install_supported; then
                        error "Automatic package lookup is unavailable for $DETECTED_DISTRO_NAME ($PACKAGE_MANAGER)."
                        info "Installed mapped tools can still be used normally."
                        pause
                        continue
                    fi
                    warn "Package metadata must be current for an authoritative result."
                    if confirm_yes "Refresh trusted package metadata now?"; then
                        refresh_package_index_for_lookup || { error "Package-index refresh failed."; pause; continue; }
                    fi
                    RESOLVED_PACKAGE=()
                    if pkg=$(resolve_package "$SELECTED_TOOL"); then
                        ok "$SELECTED_TOOL → $pkg is available from the permitted signed repository set."
                    else
                        error "No matching package was found in the permitted signed repository set."
                    fi
                fi
                pause ;;
            3)
                case "$CURRENT_DISTRO:$manager" in
                    arch:pacman|other:pacman)
                        if [[ "$DETECTED_DISTRO" == arch ]]; then
                            warn "This runs a full synchronized Arch upgrade through the locked pacman configuration."
                        else
                            error "pacman package operations are disabled on non-Arch systems."
                            pause
                            continue
                        fi
                        ;;
                    kali:apt|parrot:apt)
                        warn "This refreshes only S.O.T's hardcoded official ${CURRENT_DISTRO^} source list."
                        ;;
                    other:*)
                        warn "This refreshes metadata only through the detected package manager; it does not add repositories."
                        ;;
                esac
                confirm_yes "Continue?" && refresh_official_package_metadata
                pause ;;
            q|Q) return ;;
            *) error "Invalid option."; sleep 1 ;;
        esac
    done
}

workspace_menu() {
    local choice name i
    local -a names
    while true; do
        header
        printf '%b\n\n' "${WHITE}${BOLD}WORKSPACES${RESET}"
        printf '1. List workspaces\n2. Create and switch workspace\n3. Switch workspace\n4. Show workspace path\nQ. Back\n\n'
        read -r -u 3 -p "Select an option: " choice
        case "$choice" in
            1) list_workspace_names; pause ;;
            2)
                read -r -u 3 -p "Workspace name: " name; name=$(safe_name "$name")
                ensure_workspace "$name" && { ACTIVE_WORKSPACE=$name; save_config; ok "Workspace active: $name"; }; pause ;;
            3)
                mapfile -t names < <(list_workspace_names)
                ((${#names[@]})) || { warn "No workspaces found."; pause; continue; }
                for i in "${!names[@]}"; do printf '%d. %s\n' "$((i+1))" "${names[$i]}"; done
                read -r -u 3 -p "Select: " choice
                [[ "$choice" =~ ^[0-9]+$ ]] && ((choice>=1 && choice<=${#names[@]})) || { error "Invalid option."; pause; continue; }
                ACTIVE_WORKSPACE=${names[$((choice-1))]}; ensure_workspace "$ACTIVE_WORKSPACE"; save_config ;;
            4) printf '%s\n' "$(workspace_path)"; pause ;;
            q|Q) return ;;
            *) error "Invalid option."; sleep 1 ;;
        esac
    done
}

scope_menu() {
    local choice item number
    while true; do
        header
        printf '%b\n' "${WHITE}${BOLD}SCOPE MANAGER${RESET}"
        printf 'Strict scope: %s\n\n' "$STRICT_SCOPE"
        if [[ -s "$(scope_file)" ]]; then nl -ba "$(scope_file)"; else printf '(scope is empty)\n'; fi
        printf '\n1. Add IP, CIDR or domain\n2. Remove item\n3. Clear scope\n4. Toggle strict scope\nQ. Back\n\n'
        read -r -u 3 -p "Select an option: " choice
        case "$choice" in
            1)
                read -r -u 3 -p "Scope item: " item
                validate_scope_item "$item" || { pause; continue; }
                if grep -Fxiq -- "$item" "$(scope_file)"; then warn "Scope item already exists."
                else printf '%s\n' "$item" >> "$(scope_file)"; chmod 600 "$(scope_file)"; fi ;;
            2)
                read -r -u 3 -p "Line number: " number
                [[ "$number" =~ ^[0-9]+$ ]] || { error "Invalid number."; pause; continue; }
                sed -i "${number}d" "$(scope_file)" ;;
            3) confirm_yes "Clear all scope entries?" && : > "$(scope_file)" ;;
            4) [[ "$STRICT_SCOPE" == 1 ]] && STRICT_SCOPE=0 || STRICT_SCOPE=1; save_config ;;
            q|Q) return ;;
            *) error "Invalid option."; sleep 1 ;;
        esac
    done
}

html_escape() {
    local s=$1
    s=${s//&/\&amp;}; s=${s//</\&lt;}; s=${s//>/\&gt;}; s=${s//\"/\&quot;}
    printf '%s' "$s"
}

generate_html_report() {
    local report ts source rc logfile command
    report=$(private_temp_file "$(workspace_path)/reports" "sot_report_$(date '+%Y%m%d_%H%M%S')" '.html') || {
        error "Could not create report file."; return 1; }
    {
        printf '<!doctype html><html><head><meta charset="utf-8"><title>S.O.T Report</title>'
        printf '<style>body{background:#050805;color:#d8ffd8;font-family:Arial}table{border-collapse:collapse;width:100%%}td,th{border:1px solid #246b24;padding:6px}th{background:#0b2f0b}h1,h2{color:#71ff71}</style></head><body>'
        printf '<h1>S.O.T Report</h1><p><b>Workspace:</b> %s<br><b>Distro:</b> %s<br><b>Mode:</b> %s<br><b>Generated:</b> %s</p>' "$(html_escape "$ACTIVE_WORKSPACE")" "$(html_escape "$(distro_display)")" "$(html_escape "$ACTIVE_MODE")" "$(date)"
        printf '<h2>Scope</h2><pre>'
        while IFS= read -r line; do html_escape "$line"; printf '\n'; done < "$(scope_file)"
        printf '</pre><h2>Command History</h2><table><tr><th>Time</th><th>Source</th><th>RC</th><th>Log</th><th>Command</th></tr>'
        while IFS=$'\t' read -r ts source rc logfile command; do
            [[ -n "$ts" ]] || continue
            printf '<tr><td>%s</td><td>%s</td><td>%s</td><td>%s</td><td><code>%s</code></td></tr>' "$(html_escape "$ts")" "$(html_escape "$source")" "$(html_escape "$rc")" "$(html_escape "$logfile")" "$(html_escape "$command")"
        done < "$(history_file)"
        printf '</table></body></html>'
    } > "$report"
    chmod 600 "$report"
    ok "Report created: $report"
}

json_escape() {
    local s=$1
    s=${s//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\n'/\\n}; s=${s//$'\r'/\\r}; s=${s//$'\t'/\\t}
    printf '%s' "$s"
}

export_json() {
    local out first=1 ts source rc logfile command line
    out=$(private_temp_file "$(workspace_path)/exports" "sot_export_$(date '+%Y%m%d_%H%M%S')" '.json') || {
        error "Could not create JSON export."; return 1; }
    {
        printf '{\n  "workspace":"%s",\n  "distro":"%s",\n  "mode":"%s",\n  "scope":[' "$(json_escape "$ACTIVE_WORKSPACE")" "$(json_escape "$(distro_display)")" "$(json_escape "$ACTIVE_MODE")"
        while IFS= read -r line; do [[ -n "$line" ]] || continue; ((first)) || printf ','; printf '\n    "%s"' "$(json_escape "$line")"; first=0; done < "$(scope_file)"
        printf '\n  ],\n  "commands":['; first=1
        while IFS=$'\t' read -r ts source rc logfile command; do
            [[ -n "$ts" ]] || continue; ((first)) || printf ','
            [[ "$rc" =~ ^[0-9]+$ ]] || rc=1
            printf '\n    {"time":"%s","source":"%s","rc":%s,"log":"%s","command":"%s"}' "$(json_escape "$ts")" "$(json_escape "$source")" "$rc" "$(json_escape "$logfile")" "$(json_escape "$command")"; first=0
        done < "$(history_file)"
        printf '\n  ]\n}\n'
    } > "$out"
    chmod 600 "$out"
    ok "JSON export created: $out"
}

secure_remove() {
    local path=$1 allowed relative checked
    allowed="$(workspace_path)/tmp"
    [[ ! -L "$path" ]] || { error "Refusing to remove a symbolic link."; return 1; }
    case "$path" in
        "$allowed"/*) relative=${path#"$allowed"/} ;;
        *) error "Refusing to remove a file outside the workspace temporary directory."; return 1 ;;
    esac
    safe_relative_path "$relative" || { error "Unsafe temporary-file path."; return 1; }
    checked=$(safe_child_path "$allowed" "$relative") || return 1
    [[ "$checked" == "$path" && -f "$path" ]] || {
        error "Refusing to remove a non-regular temporary file."; return 1; }
    rm -f -- "$path"
}

notes_menu() {
    local enc="$(workspace_path)/notes/notes.txt.gpg" tmp editor choice enc_dir enc_tmp
    command -v gpg >/dev/null 2>&1 || { error "gpg is required. Install the official gnupg package through the install menu."; pause; return; }
    while true; do
        header
        printf '%b\n\n' "${WHITE}${BOLD}ENCRYPTED NOTES (GPG AES-256)${RESET}"
        printf '1. Edit encrypted notes\n2. View encrypted notes\n3. Delete encrypted notes\nQ. Back\n\n'
        read -r -u 3 -p "Select an option: " choice
        case "$choice" in
            1)
                tmp=$(mktemp "$(workspace_path)/tmp/notes.XXXXXX") || { error "Could not create temporary file."; pause; continue; }
                if [[ -f "$enc" ]]; then gpg --quiet --decrypt --output "$tmp" "$enc" || { secure_remove "$tmp"; error "Decryption failed."; pause; continue; }; fi
                editor=${EDITOR:-nano}; command -v "$editor" >/dev/null 2>&1 || editor=vi
                "$editor" "$tmp"
                enc_dir=$(mktemp -d "$(workspace_path)/notes/.encrypt.XXXXXX") || { secure_remove "$tmp"; error "Could not create encryption workspace."; pause; continue; }
                enc_tmp="$enc_dir/notes.txt.gpg"
                if gpg --symmetric --cipher-algo AES256 --output "$enc_tmp" "$tmp" && mv -f -- "$enc_tmp" "$enc"; then
                    chmod 600 "$enc"
                    rmdir -- "$enc_dir" 2>/dev/null || true
                    secure_remove "$tmp"
                    ok "Notes encrypted."
                else
                    rm -f -- "$enc_tmp"
                    rmdir -- "$enc_dir" 2>/dev/null || true
                    secure_remove "$tmp"
                    error "Encryption failed; the existing encrypted notes were not replaced."
                fi
                pause ;;
            2)
                [[ -f "$enc" ]] || { warn "No encrypted notes exist."; pause; continue; }
                tmp=$(mktemp "$(workspace_path)/tmp/notes.XXXXXX") || continue
                if gpg --quiet --decrypt --output "$tmp" "$enc"; then
                    if command -v less >/dev/null 2>&1; then less "$tmp"; else cat "$tmp"; fi
                else error "Decryption failed."; fi
                secure_remove "$tmp" ;;
            3) confirm_yes "Permanently delete encrypted notes?" && rm -f -- "$enc" ;;
            q|Q) return ;;
            *) error "Invalid option." ;;
        esac
    done
}

reports_menu() {
    local choice
    while true; do
        header
        printf '%b\n\n' "${WHITE}${BOLD}REPORTS / EVIDENCE${RESET}"
        printf '1. Generate HTML report\n2. Export JSON\n3. Show command history\n4. List evidence logs\n5. Encrypted notes\nQ. Back\n\n'
        read -r -u 3 -p "Select an option: " choice
        case "$choice" in
            1) generate_html_report; pause ;;
            2) export_json; pause ;;
            3) column -t -s $'\t' "$(history_file)" 2>/dev/null || cat "$(history_file)"; pause ;;
            4) list_evidence_logs; pause ;;
            5) notes_menu ;;
            q|Q) return ;;
            *) error "Invalid option." ;;
        esac
    done
}

profiles_menu() {
    local choice
    while true; do
        header
        printf '%b\n\n' "${WHITE}${BOLD}PROFILES / MODES${RESET}"
        printf '1. Lab (warnings, confirmation)\n2. CTF (warnings, confirmation)\n3. Engagement (strict scope)\nQ. Back\n\n'
        read -r -u 3 -p "Select an option: " choice
        case "$choice" in
            1) ACTIVE_MODE=lab; STRICT_SCOPE=0; save_config; return ;;
            2) ACTIVE_MODE=ctf; STRICT_SCOPE=0; save_config; return ;;
            3)
                [[ -s "$(scope_file)" ]] || { error "Add at least one scope entry before engagement mode."; pause; continue; }
                ACTIVE_MODE=engagement; STRICT_SCOPE=1; save_config; return ;;
            q|Q) return ;;
            *) error "Invalid option." ;;
        esac
    done
}

status_report() {
    local cat tool pkg bin manager total=0 installed=0 cat_total cat_installed
    local -A installed_pkgs=()
    manager=$(effective_package_manager)
    case "$manager" in
        apt)
            while IFS= read -r pkg; do [[ -n "$pkg" ]] && installed_pkgs["$pkg"]=1; done < <(dpkg-query -W -f='${Package}\n' 2>/dev/null)
            ;;
        pacman)
            while IFS= read -r pkg; do [[ -n "$pkg" ]] && installed_pkgs["$pkg"]=1; done < <(pacman -Qq 2>/dev/null)
            ;;
        dnf|zypper)
            if command -v rpm >/dev/null 2>&1; then
                while IFS= read -r pkg; do [[ -n "$pkg" ]] && installed_pkgs["$pkg"]=1; done < <(rpm -qa --qf '%{NAME}\n' 2>/dev/null)
            fi
            ;;
        apk)
            while IFS= read -r pkg; do [[ -n "$pkg" ]] && installed_pkgs["$pkg"]=1; done < <(apk info 2>/dev/null)
            ;;
        xbps)
            while IFS= read -r pkg; do [[ -n "$pkg" ]] && installed_pkgs["$pkg"]=1; done < <(xbps-query -l 2>/dev/null | awk '{name=$2; sub(/-[0-9][^-]*_[0-9]+$/, "", name); print name}')
            ;;
    esac
    header
    printf '%b\n\n' "${WHITE}${BOLD}STATUS REPORT${RESET}"
    printf 'Selected profile: %s\nDetected distro: %s (%s)\nPackage manager: %s\nWorkspace: %s\nMode: %s\nStrict scope: %s\n\n' \
        "$CURRENT_DISTRO" "$DETECTED_DISTRO_NAME" "$DETECTED_DISTRO" "$manager" "$ACTIVE_WORKSPACE" "$ACTIVE_MODE" "$STRICT_SCOPE"
    for cat in "${CATEGORIES[@]}"; do
        cat_total=0; cat_installed=0
        while IFS= read -r tool; do
            [[ -n "$tool" ]] || continue
            ((cat_total++)); ((total++))
            bin=${TOOL_BIN[$tool]:-}
            if [[ -n "$bin" ]] && command -v "$bin" >/dev/null 2>&1; then
                ((cat_installed++)); ((installed++)); continue
            fi
            while IFS= read -r pkg; do
                if [[ -n "${installed_pkgs[$pkg]+present}" ]]; then
                    ((cat_installed++)); ((installed++)); break
                fi
            done < <(package_candidates_for_tool "$tool")
        done <<< "${CATEGORY_TOOLS[$cat]}"
        printf '%-38s %2d/%2d installed\n' "$cat" "$cat_installed" "$cat_total"
    done
    printf '\nMapped entries: %d · Found/installed: %d\n' "$total" "$installed"
    pause
}

professional_terminal() {
    local rc=0 run_dir
    run_dir=$(workspace_path) || {
        error "Could not resolve the active workspace."
        return 1
    }
    header
    printf '%b\n\n' "${WHITE}${BOLD}PROFESSIONAL BASH TERMINAL${RESET}"
    printf '%s\n' "Working directory: $run_dir"
    printf '%s\n\n' "This is a normal unrestricted interactive Bash shell. Type 'exit' or press Ctrl-D to return to S.O.T."
    (
        cd -- "$run_dir" || exit 1
        exec bash -i <&3
    )
    rc=$?
    if (( rc != 0 )); then
        warn "The interactive Bash shell exited with status $rc."
    fi
    return 0
}

view_text_file() {
    local path=$1
    if [[ -t 3 && -t 1 ]] && command -v less >/dev/null 2>&1; then
        printf '%s\n' "Press q to close this page and return to the guide."
        less -R -- "$path" <&3
    else
        cat -- "$path"
    fi
}

help_page() {
    local title=$1
    header
    printf '%b\n\n' "${WHITE}${BOLD}${title}${RESET}"
    cat
    printf '\n'
    read -r -u 3 -p "Press Enter to continue..." _ || true
}
tool_reference_help() {
    local tmp cat tool i count template candidates pkg first
    tmp=$(mktemp "$(workspace_path)/tmp/tool-reference.XXXXXX") || {
        error "Could not create the tool reference."; pause; return; }
    chmod 600 "$tmp"
    {
        printf 'S.O.T MAPPED TOOL REFERENCE\n'
        printf 'Workspace: %s\nDistro: %s\nPackage manager: %s\n\n' \
            "$ACTIVE_WORKSPACE" "$(distro_display)" "$(effective_package_manager)"
        for cat in "${CATEGORIES[@]}"; do
            printf '======================================================================\n'
            printf '%s\n' "$cat"
            printf '======================================================================\n'
            while IFS= read -r tool; do
                [[ -n "$tool" ]] || continue
                printf '\n%s\n' "$(tool_label "$tool")"
                printf '  Purpose: %s\n' "${TOOL_HINT[$tool]}"
                printf '  Executable check: %s\n' "${TOOL_BIN[$tool]:-(none)}"
                candidates=''; first=1
                while IFS= read -r pkg; do
                    [[ -n "$pkg" ]] || continue
                    if (( first )); then candidates=$pkg; first=0; else candidates+=", $pkg"; fi
                done < <(package_candidates_for_tool "$tool")
                printf '  Package candidates for this session: %s\n' "${candidates:-(none)}"
                count=${TOOL_FUNC_COUNT[$tool]:-0}
                for ((i=1; i<=count; i++)); do
                    template=$(decode_b64 "${TOOL_FUNC_CMD_B64[$tool|$i]}")
                    case "$template" in
                        __monitor_on__) template='Built-in monitor-mode ON workflow with service-state recording and rollback.' ;;
                        __monitor_off__) template='Built-in monitor-mode OFF workflow with interface and network-service restoration.' ;;
                        __theharvester_full__) template='Runs every source supported by the installed theHarvester version, then automatically retries supported public/no-key sources individually if the all-source pass fails or returns no recognised result sections.' ;;
                        __theharvester_quick__) template='Same all-source and automatic-fallback workflow with a result limit of 200.' ;;
                        __theharvester_deep__) template='Same all-source and automatic-fallback workflow with a result limit of 1000.' ;;
                        __theharvester_resolve__) template='Runs the all-source and automatic-fallback workflow with DNS resolution enabled.' ;;
                    esac
                    printf '  %d. %s\n' "$i" "${TOOL_FUNC_LABEL[$tool|$i]}"
                    printf '     Template: %s\n' "$template"
                done
            done <<< "${CATEGORY_TOOLS[$cat]}"
            printf '\n'
        done
    } > "$tmp"
    view_text_file "$tmp"
    secure_remove "$tmp"
}

complete_how_to() {
    local tmp
    tmp=$(mktemp "$(workspace_path)/tmp/how-to.XXXXXX") || {
        error "Could not create the complete guide."; pause; return; }
    chmod 600 "$tmp"
    cat > "$tmp" <<EOF
S.O.T SPECOPS TERMINAL v${VERSION} — COMPLETE HOW-TO

CURRENT SESSION
  Distribution: $(distro_display)
  Package manager: $(effective_package_manager)
  Workspace: ${ACTIVE_WORKSPACE}
  Mode: ${ACTIVE_MODE}
  Strict scope: ${STRICT_SCOPE}

MAIN MENU WORKFLOW
  1. Tools by Category: choose a category, choose a mapped tool, then choose an action.
  2. Install / Verify Tools: resolve or install only packages allowed by the current distro policy.
  3. Workspace / Projects: isolate scope, logs, reports, notes, exports, captures and output per project.
  4. Scope Manager: add authorised domains, IP addresses, IPv4 CIDRs or MAC addresses.
  5. Professional Bash Terminal: open a normal unrestricted interactive Bash shell in the active workspace.
  6. Reports / Evidence: create HTML/JSON output, review history and logs, and manage encrypted notes.
  7. Profiles / Modes: choose Lab, CTF or Engagement behaviour.
  8. Status Report: scan all mapped tools and show what is available on the current machine.
  9. Change selected distro: use only when the selected profile does not match the running system.
  H. How to use: open this guide.

RUNNING A TOOL
  Open Tools by Category, select a category and then a tool. The tool screen shows its purpose,
  whether its executable or mapped package is present, and every mapped action. Select an action,
  enter the requested values and confirm. Once execution starts, the terminal is cleared and shows a
  results-only view of the selected command's stdout/stderr. S.O.T shell-quotes placeholder values, checks scope-sensitive
  values, blocks catastrophic patterns, records the exit code, redacts entered passwords/tokens from
  stored output, and saves command metadata plus results in a private evidence log.

INSTALLING OR VERIFYING TOOLS
  Use Install / Verify Tools instead of typing package-manager commands. Kali and Parrot use isolated
  official APT source lists. Exact Arch Linux uses pacman through S.O.T's locked configuration with
  core, extra and multilib only. Other distributions use their detected signed binary-package manager
  when supported, without borrowing package names from another distribution family. S.O.T does not add repositories, remove packages, perform local package builds or
  execute downloaded installer scripts. A package that cannot be resolved safely is refused.

WORKSPACES
  Create one workspace per lab, CTF or authorised engagement. Every workspace contains:
    evidence/  command and monitor-mode logs
    reports/   HTML reports
    exports/   JSON exports
    notes/     encrypted GPG notes
    loot/      mapped output files and captures
    tmp/       private temporary files
    scope.txt  authorised targets
    history.tsv command history
  Workspace names are sanitised and storage paths reject symbolic-link redirection.

SCOPE AND MODES
  Add exact domains, subdomains, IPv4 addresses, IPv4 CIDRs, IPv6 addresses or MAC addresses before
  active work. Lab and CTF modes warn when a target is outside the list and ask before continuing.
  Engagement mode forces strict scope and refuses out-of-scope targets. Requested CIDRs must be equal
  to or narrower than an authorised CIDR. Keep one target per scope line.

WIRELESS AND MONITOR MODE
  Use the mapped wireless checks first: iw dev, ip link, rfkill and lsusb. Monitor ON lists wireless
  interfaces, validates the chosen managed interface, records active network services, requires the
  word MONITOR, runs airmon-ng and verifies the resulting interfaces. If setup fails, S.O.T attempts
  to restore networking. Monitor OFF validates the monitor interface, stops it, restores the managed
  interface, restarts recorded services, unblocks Wi-Fi and displays verification output. Adapter,
  chipset, driver and regulatory support still determine whether monitor mode is physically available.

REPORTS, EVIDENCE AND NOTES
  Each mapped command writes a private log and a TSV history entry. HTML reports include session,
  scope and command-history information. JSON exports contain the same structured data. Encrypted
  notes use GPG symmetric AES-256 encryption. Temporary plaintext note files remain inside the active
  workspace and are removed after use.

PROFESSIONAL BASH TERMINAL
  Option 5 opens a normal unrestricted interactive Bash shell in the active workspace. It accepts any
  command the current user could enter in a normal Bash terminal, including pipelines, redirections,
  shell functions, interpreters, package managers, sudo and interactive tools. S.O.T does not parse,
  filter, rewrite, confirm or audit commands entered inside this shell. Type exit or press Ctrl-D to
  close it and return to S.O.T.

SAFETY AND TROUBLESHOOTING
  Run S.O.T as a normal user. Approved privileged operations request sudo or doas. High-risk actions
  require RUN; network/system changes require CHANGE. Templates are available in the mapped tool reference.
  If a tool is missing, use Install / Verify Tools. If a package is unavailable, the distro repository
  may not provide that mapped name. If monitor-mode restoration reports a failure, review its evidence
  log and restart the machine's normal network service manually. Run --check after copying or editing
  the script. Use SOT_SKIP_INTRO=1 only when intentionally skipping the animation.

ENVIRONMENT OPTIONS
  SOT_SKIP_INTRO=1        skip the animation
  SOT_INTRO_DELAY=0.075   seconds between animation frames; larger values make it slower
  NO_COLOR=1              disable ANSI colours
  SOT_HOME=/absolute/path use a different private S.O.T data directory
EOF
    view_text_file "$tmp"
    secure_remove "$tmp"
}

how_to_use() {
    local choice
    while true; do
        header
        printf '%b\n' "${WHITE}${BOLD}DETAILED HOW TO USE${RESET}"
        printf 'Current session: %s · workspace %s · mode %s\n\n' \
            "$(distro_display)" "$ACTIVE_WORKSPACE" "$ACTIVE_MODE"
        printf '0. Read the complete guide\n'
        printf '1. Main menu and quick workflow\n'
        printf '2. Running mapped tools and actions\n'
        printf '3. Installing and verifying tools\n'
        printf '4. Workspaces and project files\n'
        printf '5. Scope manager and profiles\n'
        printf '6. Wireless checks and monitor mode\n'
        printf '7. Reports, evidence and encrypted notes\n'
        printf '8. Professional Bash Terminal\n'
        printf '9. Safety, confirmations and troubleshooting\n'
        printf '10. Complete per-tool mapped reference\n'
        printf 'B/Q/X. Return to main menu\n\n'
        read -r -u 3 -p "Select an option: " choice || return
        case "$choice" in
            0) complete_how_to ;;
            1) help_page 'MAIN MENU AND QUICK WORKFLOW' <<EOF
You are already inside S.O.T. The header shows the selected distribution, active workspace and mode.

1. Start with Workspace / Projects and create or select the project you are working on.
2. Open Scope Manager and enter every authorised domain, IP, CIDR or MAC address.
3. Choose Profiles / Modes. Use Engagement only after the scope list is complete.
4. Open Tools by Category, select a tool and select one of its numbered mapped actions.
5. Enter the requested values and confirm the selected action.
6. Review Reports / Evidence after each stage and generate HTML or JSON when needed.
7. Use Status Report to see how many mapped tools are currently available.
8. Use Change selected distro only when the running system profile was selected incorrectly.
EOF
               ;;
            2) help_page 'RUNNING MAPPED TOOLS AND ACTIONS' <<'EOF'
Tools are arranged into ten categories. Select a category, then a tool. Each tool screen shows:
  • its purpose;
  • installed/found status;
  • every mapped action;
  • an install option using the current safe package policy.

After selecting an action, S.O.T asks only for placeholders used by that command. Passwords and tokens
are entered invisibly. Output-file placeholders are forced into the workspace loot directory. Targets,
URLs, CIDRs and wireless identifiers are validated before execution. In Lab mode, passive mapped actions
show the final rendered command before the y/N confirmation. Active or credential-testing commands
require RUN. Network or system-state changes require CHANGE.
When execution starts, the screen is cleared and a results-only view of the command's stdout/stderr is
shown. Known legal/terms boilerplate is hidden from the live screen. Command metadata, full redacted output
and return code are still saved in the workspace evidence log and history file.
EOF
               ;;
            3) help_page 'INSTALLING AND VERIFYING TOOLS' <<EOF
Open Install / Verify Tools to install, verify or refresh metadata.

Current package manager: $(effective_package_manager)
Current distribution: $(distro_display)

• Kali: isolated official kali-rolling APT source for S.O.T transactions.
• Parrot: isolated official Echo, Echo security and Echo backports APT sources.
• Exact Arch Linux: pacman only, using a separate configuration containing core, extra and multilib.
• Other APT systems use their APT mapping; DNF/Zypper/APK/XBPS use only an exact executable-name package candidate.
• Portage, Nix, unknown managers and pacman-based non-Arch systems: installed tools work, but automatic
  installation is disabled.

S.O.T never adds repositories, turns off package signature checking, removes packages, runs local
package builds or pipes downloaded scripts into a shell. If no permitted package is found, it stops.
EOF
               ;;
            4) help_page 'WORKSPACES AND PROJECT FILES' <<EOF
Use one workspace for each lab, CTF or authorised engagement. Creating or switching a workspace changes
where all later files are stored. The active path is:

  $(workspace_path)

Directories are private to your user. evidence contains command logs; reports contains HTML output;
exports contains JSON; notes contains encrypted notes; loot contains captures and output files; tmp
contains temporary files. scope.txt stores authorised targets and history.tsv stores command results.
Workspace names are cleaned to safe characters and path traversal or symbolic-link redirection is
rejected. Back up the workspace directory when you need to preserve engagement evidence.
EOF
               ;;
            5) help_page 'SCOPE MANAGER AND PROFILES' <<'EOF'
Add one authorised target per line. Accepted entries include exact domains, IPv4 addresses, IPv4 CIDRs,
IPv6 addresses and MAC addresses. A domain entry also allows its real subdomains, but not look-alike
names. An authorised CIDR allows single IPs or narrower CIDRs inside it; it does not allow broader ranges.

Lab mode: warnings and confirmations, strict scope off.
CTF mode: warnings and confirmations, strict scope off.
Engagement mode: strict scope automatically on and an existing scope list is required.

Strict scope blocks an action before execution when a target is outside the list. URL-list inputs are
checked line by line. Review the scope file whenever the authorised target set changes.
EOF
               ;;
            6) help_page 'WIRELESS CHECKS AND MONITOR MODE' <<'EOF'
Before monitor mode, confirm the adapter and interface with iw dev, ip link, lsusb and rfkill. The mapped
monitor ON workflow validates the selected managed wireless interface, records active network services,
requires MONITOR, runs airmon-ng check kill and starts monitor mode. It then prints iw verification. If
setup fails, it attempts to restart recorded services, unblock Wi-Fi and turn the radio back on.

For monitor OFF, enter the monitor interface shown by iw dev, confirm the managed interface to restore,
and type RESTORE. S.O.T stops monitor mode, waits for the managed interface, brings it up, restarts the
recorded network services, unblocks Wi-Fi and prints verification. Read the evidence log if any step
fails. Monitor mode cannot be guaranteed when the adapter, chipset or driver does not support it.
EOF
               ;;
            7) help_page 'REPORTS, EVIDENCE AND ENCRYPTED NOTES' <<'EOF'
Every executed mapped action creates a private evidence log containing time, distro, workspace, working
directory, redacted command preview, output and exit code. The history screen summarises these runs.
Generate HTML for a readable engagement report or JSON for structured export. Evidence-list filenames
sort newest first because they begin with timestamps.

Encrypted notes require GPG. Edit decrypts into a private workspace temporary file, opens your EDITOR
(or nano/vi), re-encrypts with GPG AES-256 and removes the plaintext temporary file. Viewing also uses a
private temporary file. Deleting encrypted notes requires confirmation and only removes that workspace's
notes file.
EOF
               ;;
            8) help_page 'PROFESSIONAL BASH TERMINAL' <<'EOF'
The Professional Bash Terminal opens a normal unrestricted interactive Bash shell in the active
workspace. It accepts the same commands, pipelines, redirections, shell functions, aliases, interpreters
and interactive programs available in the user's normal Bash environment. S.O.T does not parse, filter,
block, rewrite, confirm or audit commands entered inside this shell.

Type exit or press Ctrl-D to close the shell and return to S.O.T. Commands run with the current user's
normal permissions. The user may invoke sudo or other installed tools manually and is responsible for
reviewing commands before execution.
EOF
               ;;
            9) help_page 'SAFETY, CONFIRMATIONS AND TROUBLESHOOTING' <<'EOF'
Run the toolkit as your normal user, never as root. Approved privileged actions use sudo or doas. Keep
scope accurate and review mapped command previews before confirming them. Catastrophic disk formatting,
root deletion, shutdown/reboot and fork-bomb patterns are blocked for mapped actions only. Commands
entered in the Professional Bash Terminal are unrestricted and are the user's responsibility.

If a tool is missing, check Status Report and then Install / Verify Tools. If package lookup fails after a
metadata refresh, that repository probably does not carry the mapped package name. If a command exits
non-zero, open its evidence log. If Wi-Fi does not return, use the monitor OFF workflow, then restart your
normal network service manually. After editing or transferring S.O.T, run its --check option.
EOF
               ;;
            10) tool_reference_help ;;
            q|Q|b|B|x|X|back|Back|BACK|exit|Exit|EXIT|quit|Quit|QUIT) return ;;
            *) error "Invalid option."; sleep 1 ;;
        esac
    done
}

information_menu() {
    local choice
    while true; do
        header
        printf '%b\n\n' "${WHITE}${BOLD}INFORMATION / POLICIES${RESET}"
        printf '1. About S.O.T and current session\n'
        printf '2. Package and repository policy\n'
        printf '3. Execution, scope and confirmation information\n'
        printf '4. Clean output, evidence and privacy\n'
        printf '5. Complete mapped tool reference\n'
        printf 'B/Q/X. Back\n\n'
        read -r -u 3 -p "Select an option: " choice || return
        case "$choice" in
            1) help_page 'ABOUT S.O.T' <<EOF
S.O.T SpecOps Terminal v${VERSION}
Made by ${AUTHOR}

Current distribution: $(distro_display)
Detected system: ${DETECTED_DISTRO_NAME} (${DETECTED_DISTRO})
Package manager: $(effective_package_manager)
Workspace: ${ACTIVE_WORKSPACE}
Mode: ${ACTIVE_MODE}
Strict scope: ${STRICT_SCOPE}

S.O.T contains 93 mapped tool entries, 205 mapped actions and 10 categories. Tool screens contain only
technical purpose, installation status and mapped actions. Detailed operational information is kept in
How to use, Information and the complete mapped tool reference.
EOF
               ;;
            2) help_page 'PACKAGE AND REPOSITORY POLICY' <<EOF
Kali Linux uses S.O.T's isolated official kali-rolling APT source list.
Parrot OS uses S.O.T's isolated official stable, security and backports APT source list.
Exact Arch Linux uses pacman through a separate locked configuration containing core, extra and
multilib only. It does not import the user's pacman repository configuration.
Other supported distributions use their detected signed binary-package manager without adding a new
repository. Automatic installation is disabled for source-build managers, unknown managers and
pacman-based systems that are not exact Arch Linux.

S.O.T does not remove packages, disable package signature verification, perform local package builds or
execute downloaded installer scripts. Unavailable packages are refused rather than sourced elsewhere.
EOF
               ;;
            3) help_page 'EXECUTION, SCOPE AND CONFIRMATIONS' <<'EOF'
Use mapped actions only on systems and networks where you have permission. Scope entries can be exact
hosts, domains, IP addresses, IPv4 CIDRs or MAC addresses. Engagement mode enforces strict scope.

Passive mapped actions use a y/N confirmation. Active or credential-testing actions require RUN.
Network or system-state changes require CHANGE. Monitor-mode workflows use MONITOR and RESTORE.
Mapped actions block catastrophic disk formatting, root-filesystem deletion, shutdown/reboot and
fork-bomb patterns. The Professional Bash Terminal is unrestricted and does not apply mapped-action safeguards.
EOF
               ;;
            4) help_page 'CLEAN OUTPUT, EVIDENCE AND PRIVACY' <<'EOF'
After confirmation, a mapped action clears the terminal and displays a results-only view of that command's
stdout/stderr. S.O.T banners, policy text, command previews and completion notices are not mixed into
the live result. Known legal/terms boilerplate emitted by third-party tools is hidden from the live view.

A private evidence log still stores timestamp, distro, package manager, workspace, working directory,
redacted command metadata and the command output. Passwords and tokens entered through sensitive
placeholders are redacted from stored output. History records the exit code and evidence-log path.
EOF
               ;;
            5) tool_reference_help ;;
            q|Q|b|B|x|X|back|Back|BACK|exit|Exit|EXIT|quit|Quit|QUIT) return ;;
            *) error "Invalid option."; sleep 1 ;;
        esac
    done
}

main_menu() {
    local choice
    while true; do
        header
        printf '%b\n' "${WHITE}${BOLD}MAIN MENU${RESET}"
        printf '1. Tools by Category\n'
        printf '2. Install / Verify Tools\n'
        printf '3. Workspace / Projects\n'
        printf '4. Scope Manager\n'
        printf '5. Professional Bash Terminal\n'
        printf '6. Reports / Evidence\n'
        printf '7. Profiles / Modes\n'
        printf '8. Status Report\n'
        printf '9. Change selected distro\n'
        printf 'H. How to use\n'
        printf 'I. Information / Policies\n'
        printf 'Q. Exit\n\n'
        read -r -u 3 -p "Select an option: " choice
        case "$choice" in
            1) tools_by_category ;;
            2) install_remove_menu ;;
            3) workspace_menu ;;
            4) scope_menu ;;
            5) professional_terminal ;;
            6) reports_menu ;;
            7) profiles_menu ;;
            8) status_report ;;
            9) select_distro ;;
            h|H) how_to_use ;;
            i|I) information_menu ;;
            q|Q) clear_screen; printf '%b\n' "${NEON}S.O.T v${VERSION} · Session closed.${RESET}"; return ;;
            *) error "Invalid option."; sleep 1 ;;
        esac
    done
}

self_check() {
    local total=0 funcs=0 cat tool i failed=0 decoded syntax key replacement
    local -A seen_categories=() seen_tools=()
    [[ ${#CATEGORIES[@]} -eq 10 ]] || { error "Expected 10 categories."; failed=1; }
    for cat in "${CATEGORIES[@]}"; do
        [[ -z "${seen_categories["$cat"]+present}" ]] || { error "Duplicate category: $cat"; failed=1; }
        seen_categories["$cat"]=1
        while IFS= read -r tool; do
            [[ -n "$tool" ]] || continue
            ((total++))
            [[ -z "${seen_tools["$tool"]+present}" ]] || { error "Duplicate internal tool key: $tool"; failed=1; }
            seen_tools["$tool"]=1
            tool_exists "$tool" || { error "Missing tool data: $tool"; failed=1; }
            [[ -n "${TOOL_PKG_APT[$tool]:-}" && "${TOOL_PKG_APT[$tool]}" =~ ^[A-Za-z0-9@._+:-]+([[:space:]][A-Za-z0-9@._+:-]+)*$ ]] || {
                error "Invalid APT package mapping: $tool"; failed=1; }
            [[ -n "${TOOL_PKG_ARCH[$tool]:-}" && "${TOOL_PKG_ARCH[$tool]}" =~ ^[A-Za-z0-9@._+:-]+([[:space:]][A-Za-z0-9@._+:-]+)*$ ]] || {
                error "Invalid pacman package mapping: $tool"; failed=1; }
            [[ -z "${TOOL_BIN[$tool]:-}" || "${TOOL_BIN[$tool]}" =~ ^[A-Za-z0-9@._+:-]+$ ]] || {
                error "Invalid executable mapping: $tool"; failed=1; }
            (( ${TOOL_FUNC_COUNT[$tool]:-0} > 0 )) || { error "Tool has no mapped actions: $tool"; failed=1; }
            for ((i=1; i<=${TOOL_FUNC_COUNT[$tool]:-0}; i++)); do
                decoded=$(decode_b64 "${TOOL_FUNC_CMD_B64[$tool|$i]}") || { error "Bad command data: $tool/$i"; failed=1; continue; }
                [[ -n "$decoded" ]] || { error "Empty command data: $tool/$i"; failed=1; continue; }
                [[ "$decoded" != *'{command}'* ]] || { error "Arbitrary command placeholder found: $tool/$i"; failed=1; }
                if [[ "$decoded" != __monitor_on__ && "$decoded" != __monitor_off__ &&
                      "$decoded" != __theharvester_full__ && "$decoded" != __theharvester_quick__ &&
                      "$decoded" != __theharvester_deep__ && "$decoded" != __theharvester_resolve__ ]]; then
                    syntax=$decoded
                    while [[ "$syntax" =~ \{([A-Za-z0-9_]+)\} ]]; do
                        key=${BASH_REMATCH[1]}
                        replacement=test
                        syntax=${syntax//\{$key\}/$replacement}
                    done
                    bash -n -c "$syntax" 2>/dev/null || { error "Invalid mapped command syntax: $tool/$i"; failed=1; }
                    catastrophic_command "$syntax" && { error "Mapped action is destructively unsafe: $tool/$i"; failed=1; }
                    [[ ! "$syntax" =~ (^|[[:space:];|&])(apt|apt-get|pacman|dnf|dnf5|zypper|apk|xbps-install)([[:space:];|&]|$) ]] || {
                        error "Package-manager command found inside mapped actions: $tool/$i"; failed=1; }
                fi
                ((funcs++))
            done
        done <<< "${CATEGORY_TOOLS[$cat]}"
    done
    printf 'S.O.T Bash check · %d mapped entries · %d mapped actions · %d categories\n' "$total" "$funcs" "${#CATEGORIES[@]}"
    (( total == 93 )) || { error "Expected 93 mapped entries, found $total."; failed=1; }
    (( funcs == 205 )) || { error "Expected 205 mapped actions, found $funcs."; failed=1; }
    local pacman_policy
    pacman_policy=$(declare -f write_arch_pacman_config)
    [[ "$pacman_policy" == *'[core]'* && "$pacman_policy" == *'[extra]'* && "$pacman_policy" == *'[multilib]'* ]] || {
        error "Locked pacman repository policy is incomplete."; failed=1; }
    [[ "$pacman_policy" == *'HookDir = /etc/pacman.d/hooks'* ]] || {
        error "Locked pacman configuration does not preserve the standard administrator hook directory."; failed=1; }
    [[ "$pacman_policy" != *'/etc/pacman.conf'* ]] || {
        error "Locked pacman policy must not import the system repository configuration."; failed=1; }
    local harvester_policy
    harvester_policy=$(declare -f theharvester_workflow)
    [[ "$harvester_policy" == *'theharvester_run_pass "$domain" "$limit" all'* &&
       "$harvester_policy" == *'theharvester_supported_fallback_sources'* &&
       "$harvester_policy" == *'Command to execute:'* &&
       "$harvester_policy" == *'[[ "$ACTIVE_MODE" == lab ]]'* &&
       "$harvester_policy" == *'for source in "${fallback_sources[@]}"'* ]] || {
        error "theHarvester all-source fallback workflow is incomplete."; failed=1; }
    local source_text
    source_text=$(cat -- "${BASH_SOURCE[0]}")
    [[ ! "$source_text" =~ (apt-get|pacman|dnf|dnf5|zypper|apk|xbps-install)[[:space:]]+(-[^[:space:]]*[[:space:]]+)*(remove|-R|erase|del)([[:space:]]|$) ]] || {
        error "Package-removal execution is present in the safety build."; failed=1; }
    local forbidden
    forbidden='base64 --de''code'; [[ "$source_text" != *"$forbidden"* ]] || { error "Non-portable base64 decoding remains."; failed=1; }
    forbidden='mktemp --suf''fix'; [[ "$source_text" != *"$forbidden"* ]] || { error "Non-portable mktemp option remains."; failed=1; }
    forbidden='-pri''ntf'; [[ "$source_text" != *"$forbidden"* ]] || { error "Non-portable find output formatting remains."; failed=1; }
    forbidden='realpath -''m'; [[ "$source_text" != *"$forbidden"* ]] || { error "Non-portable path canonicalisation remains."; failed=1; }
    [[ "$source_text" == *'DETAILED HOW TO USE'* && "$source_text" == *'Complete per-tool mapped reference'* ]] || {
        error "Detailed in-app guide is incomplete."; failed=1; }
    [[ "$source_text" == *'B/Q/X. Return to main menu'* && "$source_text" == *'read -r -u 3 -p "Select an option: " choice || return'* ]] || {
        error "How-to guide exit handling is incomplete."; failed=1; }
    local plain_read plain_secret_read
    plain_read='read -r -''p '
    plain_secret_read='read -r -s -''p '
    [[ "$source_text" != *"$plain_read"* && "$source_text" != *"$plain_secret_read"* ]] || {
        error "An interactive prompt bypasses the preserved terminal descriptor."; failed=1; }
    local execute_policy
    execute_policy=$(declare -f execute_shell_command)
    [[ "$execute_policy" == *'tee -a -- "$logfile" | clean_result_stream'* &&
       "$execute_policy" == *'Command to execute:'* &&
       "$execute_policy" == *'[[ "$ACTIVE_MODE" == "lab" ]]'* &&
       "$execute_policy" != *'Command completed.'* ]] || {
        error "Mapped Lab command preview or clean result separation is incomplete."; failed=1; }
    local terminal_policy
    terminal_policy=$(declare -f professional_terminal)
    [[ "$terminal_policy" == *'exec bash -i'* && "$terminal_policy" == *'<&3'* &&
       "$terminal_policy" != *'catastrophic_command'* && "$terminal_policy" != *'high_risk_command'* &&
       "$terminal_policy" != *'system_change_command'* ]] || {
        error "Professional Bash Terminal is not an unrestricted interactive Bash shell."; failed=1; }
    local monitor_policy
    monitor_policy=$(declare -f monitor_on; declare -f monitor_off)
    [[ "$monitor_policy" == *'wireless_interface_type'* &&
       "$monitor_policy" == *'monitor_interface_on_phy'* &&
       "$monitor_policy" == *'Managed-mode verification failed'* ]] || {
        error "Monitor-mode verification or restoration checks are incomplete."; failed=1; }
    local result_filter
    result_filter=$(declare -f clean_result_stream)
    [[ "$result_filter" == *'legal disclaimer'* && "$result_filter" == *'terms of use'* ]] || {
        error "Known terms/disclaimer filtering is incomplete."; failed=1; }
    [[ "$(html_escape '<>&"')" == '&lt;&gt;&amp;&quot;' ]] || {
        error "HTML escaping is malformed."; failed=1; }
    local hint_text
    for tool in "${!TOOL_HINT[@]}"; do
        hint_text=${TOOL_HINT[$tool],,}
        [[ "$hint_text" != *authorised* && "$hint_text" != *authorized* && "$hint_text" != *'use only'* ]] || {
            error "Usage-policy wording remains in a tool description: $tool"; failed=1; }
    done
    local boot_policy
    boot_policy=$(declare -f boot_animation)
    [[ "$boot_policy" == *'1 2 3 4 5 6 7 8'* && "$boot_policy" == *'0.075'* ]] || {
        error "Boot animation timing policy is incomplete."; failed=1; }
    (( failed == 0 )) && { printf 'OVERALL: PASS\n'; return 0; }
    printf 'OVERALL: FAIL\n'; return 1
}

verify_runtime_dependencies() {
    local cmd missing=0
    for cmd in awk base64 chmod date find grep mkdir mktemp mv sed sort stat tee touch uname; do
        command -v "$cmd" >/dev/null 2>&1 || { error "Required command is missing: $cmd"; missing=1; }
    done
    command -v sudo >/dev/null 2>&1 || command -v doas >/dev/null 2>&1 || warn "Neither sudo nor doas is installed; privileged actions and package installs will not work."
    (( missing == 0 ))
}

main() {
    if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then error "Bash 4.3 or newer is required."; return 1; fi
    if [[ "$(uname -s)" != Linux ]]; then error "This program supports Linux only."; return 1; fi
    verify_runtime_dependencies || return 1
    [[ "${1:-}" == --version ]] && { printf 'S.O.T SpecOps Terminal v%s\n' "$VERSION"; return 0; }
    validate_storage_root || return 1
    if [[ "${1:-}" == --check ]]; then
        load_config
        self_check
        return
    fi
    if (( EUID == 0 )); then
        error "Do not run the whole toolkit as root. Run it as your normal user; individual approved actions use sudo or doas."
        return 1
    fi
    load_config
    boot_animation
    select_distro || return 1
    main_menu
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
