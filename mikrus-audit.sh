#!/usr/bin/env bash

# =============================================================================
# Mikrus Audit - Skrypt audytu bezpieczeństwa VPS
# Wersja: 1.0.0
#
# Fork projektu vps-audit (https://github.com/vernu/vps-audit) autorstwa
# vernu (https://github.com/vernu). Oryginalny projekt na licencji MIT.
#
# Ten fork dodaje:
#   - Pełne tłumaczenie na język polski
#   - Adaptację do środowiska Mikr.us (kontenery LXC/Proxmox)
#   - Poprawki błędów z oryginalnego skryptu (parsowanie IPv6, journalctl)
#   - Dodatkowe sprawdzenia bezpieczeństwa (IPv6, Docker, uprawnienia plików)
#
# Repozytorium forka: https://github.com/simplybychris/vps-audit
# Oryginał: https://github.com/vernu/vps-audit
# =============================================================================

# Kolory do wyświetlania
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
GRAY='\033[0;90m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # Brak koloru

# Znacznik czasu dla nazwy raportu
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
REPORT_FILE="mikrus-audit-raport-${TIMESTAMP}.txt"

# Wykrywanie środowiska LXC (Mikr.us używa kontenerów LXC na Proxmox)
IS_LXC=0
if grep -qa "lxc" /proc/1/environ 2>/dev/null || \
   grep -q "container=lxc" /proc/1/environ 2>/dev/null || \
   [ -f /run/container_type ] || \
   grep -q "lxc" /proc/self/cgroup 2>/dev/null || \
   [ -d /proc/vz ] || \
   systemd-detect-virt 2>/dev/null | grep -qi "lxc"; then
    IS_LXC=1
fi

print_header() {
    local header="$1"
    echo -e "\n${BLUE}${BOLD}$header${NC}"
    echo -e "\n$header" >> "$REPORT_FILE"
    echo "================================" >> "$REPORT_FILE"
}

print_info() {
    local label="$1"
    local value="$2"
    echo -e "${BOLD}$label:${NC} $value"
    echo "$label: $value" >> "$REPORT_FILE"
}

# Rozpoczęcie audytu
echo -e "${BLUE}${BOLD}Mikrus Audit - Audyt bezpieczeństwa VPS${NC}"
echo -e "${GRAY}Bazuje na: https://github.com/vernu/vps-audit${NC}"
echo -e "${GRAY}Rozpoczęcie audytu: $(date)${NC}\n"

echo "Mikrus Audit - Audyt bezpieczeństwa VPS" > "$REPORT_FILE"
echo "Bazuje na: https://github.com/vernu/vps-audit" >> "$REPORT_FILE"
echo "Rozpoczęcie audytu: $(date)" >> "$REPORT_FILE"
echo "================================" >> "$REPORT_FILE"

if [ "$IS_LXC" -eq 1 ]; then
    echo -e "${YELLOW}${BOLD}Wykryto kontener LXC (Mikr.us/Proxmox)${NC}"
    echo -e "${GRAY}Niektóre wyniki mogą się różnić od standardowego VPS${NC}\n"
    echo "UWAGA: Wykryto środowisko LXC (kontener Proxmox)" >> "$REPORT_FILE"
    echo "Wyniki zostały dostosowane do specyfiki kontenerów." >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
fi

# Sekcja informacji o systemie
print_header "Informacje o systemie"

# Pobieranie informacji o systemie
OS_INFO=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2)
KERNEL_VERSION=$(uname -r)
CURRENT_HOSTNAME=$HOSTNAME
UPTIME_INFO=$(uptime -p 2>/dev/null || uptime)
UPTIME_SINCE=$(uptime -s 2>/dev/null || echo "niedostępne")
CPU_INFO=$(lscpu 2>/dev/null | grep "Model name" | cut -d':' -f2 | xargs)
CPU_CORES=$(nproc 2>/dev/null || echo "nieznane")
TOTAL_MEM=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}')
TOTAL_DISK=$(df -h / | awk 'NR==2 {print $2}')
PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "niedostępny")
PUBLIC_IPV6=$(curl -s --max-time 5 https://api6.ipify.org 2>/dev/null || echo "niedostępny")
LOAD_AVERAGE=$(uptime | awk -F'load average:' '{print $2}' | xargs)

# Wyświetlanie informacji o systemie
print_info "Nazwa hosta" "$CURRENT_HOSTNAME"
print_info "System operacyjny" "$OS_INFO"
print_info "Wersja jądra" "$KERNEL_VERSION"
print_info "Czas pracy" "$UPTIME_INFO (od $UPTIME_SINCE)"
print_info "Model CPU" "$CPU_INFO"
print_info "Rdzenie CPU" "$CPU_CORES"
print_info "Pamięć RAM" "$TOTAL_MEM"
print_info "Przestrzeń dyskowa" "$TOTAL_DISK"
print_info "Publiczny IP (IPv4)" "$PUBLIC_IP"
print_info "Publiczny IP (IPv6)" "$PUBLIC_IPV6"

if [ "$IS_LXC" -eq 1 ]; then
    print_info "Load Average" "$LOAD_AVERAGE (UWAGA: w LXC pokazuje obciążenie hosta Proxmox, nie kontenera)"
else
    print_info "Load Average" "$LOAD_AVERAGE"
fi

echo "" >> "$REPORT_FILE"

# Sekcja audytu bezpieczeństwa
print_header "Wyniki audytu bezpieczeństwa"

# Funkcja sprawdzania z trzema stanami
check_security() {
    local test_name="$1"
    local status="$2"
    local message="$3"

    case $status in
        "PASS")
            echo -e "${GREEN}[OK]${NC} $test_name ${GRAY}- $message${NC}"
            echo "[OK] $test_name - $message" >> "$REPORT_FILE"
            ;;
        "WARN")
            echo -e "${YELLOW}[UWAGA]${NC} $test_name ${GRAY}- $message${NC}"
            echo "[UWAGA] $test_name - $message" >> "$REPORT_FILE"
            ;;
        "FAIL")
            echo -e "${RED}[BŁĄD]${NC} $test_name ${GRAY}- $message${NC}"
            echo "[BŁĄD] $test_name - $message" >> "$REPORT_FILE"
            ;;
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $test_name ${GRAY}- $message${NC}"
            echo "[INFO] $test_name - $message" >> "$REPORT_FILE"
            ;;
    esac
    echo "" >> "$REPORT_FILE"
}

# Sprawdzanie czasu pracy systemu
UPTIME_INFO=$(uptime -p 2>/dev/null || uptime)
UPTIME_SINCE=$(uptime -s 2>/dev/null || echo "niedostępne")
echo -e "\nInformacje o czasie pracy systemu:" >> "$REPORT_FILE"
echo "Aktualny czas pracy: $UPTIME_INFO" >> "$REPORT_FILE"
echo "System uruchomiony od: $UPTIME_SINCE" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"
echo -e "Czas pracy systemu: $UPTIME_INFO (od $UPTIME_SINCE)"

# Sprawdzanie czy system wymaga restartu
if [ -f /var/run/reboot-required ]; then
    check_security "Restart systemu" "WARN" "System wymaga restartu w celu zastosowania aktualizacji"
else
    check_security "Restart systemu" "PASS" "Restart nie jest wymagany"
fi

# Sprawdzanie nadpisów konfiguracji SSH
SSH_CONFIG_OVERRIDES=$(grep "^Include" /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}')

# Sprawdzanie logowania root przez SSH
if [ -n "$SSH_CONFIG_OVERRIDES" ] && [ -d "$(dirname "$SSH_CONFIG_OVERRIDES")" ]; then
    SSH_ROOT=$(grep "^PermitRootLogin" $SSH_CONFIG_OVERRIDES /etc/ssh/sshd_config 2>/dev/null | head -1 | awk '{print $2}')
else
    SSH_ROOT=$(grep "^PermitRootLogin" /etc/ssh/sshd_config 2>/dev/null | head -1 | awk '{print $2}')
fi
if [ -z "$SSH_ROOT" ]; then
    SSH_ROOT="prohibit-password"
fi
if [ "$SSH_ROOT" = "no" ]; then
    check_security "Logowanie root SSH" "PASS" "Logowanie jako root jest prawidłowo wyłączone w konfiguracji SSH"
elif [ "$SSH_ROOT" = "prohibit-password" ]; then
    check_security "Logowanie root SSH" "WARN" "Logowanie root dozwolone tylko kluczem SSH (prohibit-password). Rozważ całkowite wyłączenie w /etc/ssh/sshd_config"
else
    check_security "Logowanie root SSH" "FAIL" "Logowanie jako root jest dozwolone - to ryzyko bezpieczeństwa. Wyłącz w /etc/ssh/sshd_config (PermitRootLogin no)"
fi

# Sprawdzanie uwierzytelniania hasłem SSH
if [ -n "$SSH_CONFIG_OVERRIDES" ] && [ -d "$(dirname "$SSH_CONFIG_OVERRIDES")" ]; then
    SSH_PASSWORD=$(grep "^PasswordAuthentication" $SSH_CONFIG_OVERRIDES /etc/ssh/sshd_config 2>/dev/null | head -1 | awk '{print $2}')
else
    SSH_PASSWORD=$(grep "^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null | head -1 | awk '{print $2}')
fi
if [ -z "$SSH_PASSWORD" ]; then
    SSH_PASSWORD="yes"
fi
if [ "$SSH_PASSWORD" = "no" ]; then
    check_security "Hasło SSH" "PASS" "Uwierzytelnianie hasłem jest wyłączone - dozwolone tylko klucze SSH"
else
    check_security "Hasło SSH" "FAIL" "Uwierzytelnianie hasłem jest włączone - rozważ wyłączenie i użycie tylko kluczy SSH (PasswordAuthentication no)"
fi

# Sprawdzanie portu SSH
UNPRIVILEGED_PORT_START=$(sysctl -n net.ipv4.ip_unprivileged_port_start 2>/dev/null || echo "1024")
SSH_PORT=""
if [ -n "$SSH_CONFIG_OVERRIDES" ] && [ -d "$(dirname "$SSH_CONFIG_OVERRIDES")" ]; then
    SSH_PORT=$(grep "^Port" $SSH_CONFIG_OVERRIDES /etc/ssh/sshd_config 2>/dev/null | head -1 | awk '{print $2}')
else
    SSH_PORT=$(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | head -1 | awk '{print $2}')
fi
if [ -z "$SSH_PORT" ]; then
    SSH_PORT="22"
fi

if [ "$IS_LXC" -eq 1 ] && [ "$SSH_PORT" = "22" ]; then
    # Na Mikrusie SSH słucha na porcie 22 wewnątrz kontenera,
    # ale jest dostępny z zewnątrz na porcie 10000+ID
    check_security "Port SSH" "INFO" "Port SSH: $SSH_PORT (wewnątrz kontenera). Na Mikrusie dostęp z zewnątrz jest przez port 10000+ID - to jest normalne"
elif [ "$SSH_PORT" = "22" ]; then
    check_security "Port SSH" "WARN" "Użyto domyślnego portu 22 - rozważ zmianę na niestandardowy port dla dodatkowej ochrony"
elif [ "$SSH_PORT" -ge "$UNPRIVILEGED_PORT_START" ] 2>/dev/null; then
    check_security "Port SSH" "FAIL" "Użyto nieuprzywilejowanego portu $SSH_PORT - użyj portu poniżej $UNPRIVILEGED_PORT_START dla lepszego bezpieczeństwa"
else
    check_security "Port SSH" "PASS" "Użyto niestandardowego portu $SSH_PORT - utrudnia automatyczne ataki"
fi

# Sprawdzanie statusu zapory sieciowej
check_firewall_status() {
    if command -v ufw >/dev/null 2>&1; then
        if ufw status 2>/dev/null | grep -qw "active"; then
            check_security "Zapora sieciowa (UFW)" "PASS" "Zapora UFW jest aktywna i chroni system"
        else
            if [ "$IS_LXC" -eq 1 ]; then
                check_security "Zapora sieciowa (UFW)" "WARN" "Zapora UFW nie jest aktywna. W kontenerze LXC zapora może być zarządzana na poziomie hosta Proxmox"
            else
                check_security "Zapora sieciowa (UFW)" "FAIL" "Zapora UFW nie jest aktywna - system jest narażony na ataki sieciowe"
            fi
        fi
    elif command -v firewall-cmd >/dev/null 2>&1; then
        if firewall-cmd --state 2>/dev/null | grep -q "running"; then
            check_security "Zapora sieciowa (firewalld)" "PASS" "Firewalld jest aktywny i chroni system"
        else
            check_security "Zapora sieciowa (firewalld)" "FAIL" "Firewalld nie jest aktywny - system jest narażony na ataki sieciowe"
        fi
    elif command -v iptables >/dev/null 2>&1; then
        if iptables -L -n 2>/dev/null | grep -q "Chain INPUT"; then
            check_security "Zapora sieciowa (iptables)" "PASS" "Reguły iptables są aktywne i chronią system"
        else
            check_security "Zapora sieciowa (iptables)" "FAIL" "Brak aktywnych reguł iptables - system może być narażony"
        fi
    elif command -v nft >/dev/null 2>&1; then
        if nft list ruleset 2>/dev/null | grep -q "table"; then
            check_security "Zapora sieciowa (nftables)" "PASS" "Reguły nftables są aktywne i chronią system"
        else
            check_security "Zapora sieciowa (nftables)" "FAIL" "Brak aktywnych reguł nftables - system może być narażony"
        fi
    else
        if [ "$IS_LXC" -eq 1 ]; then
            check_security "Zapora sieciowa" "WARN" "Brak zainstalowanego narzędzia zapory. W kontenerze LXC zapora może być zarządzana przez hosta Proxmox"
        else
            check_security "Zapora sieciowa" "FAIL" "Brak zainstalowanego narzędzia zapory w systemie"
        fi
    fi
}

# Sprawdzenie zapory
check_firewall_status

# Sprawdzanie automatycznych aktualizacji
if command -v dpkg >/dev/null 2>&1; then
    if dpkg -l 2>/dev/null | grep -q "unattended-upgrades"; then
        check_security "Automatyczne aktualizacje" "PASS" "Automatyczne aktualizacje bezpieczeństwa są skonfigurowane"
    else
        check_security "Automatyczne aktualizacje" "FAIL" "Automatyczne aktualizacje nie są skonfigurowane - system może pominąć krytyczne poprawki. Zainstaluj: apt install unattended-upgrades"
    fi
elif command -v yum >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
    check_security "Automatyczne aktualizacje" "INFO" "System oparty na RPM - sprawdź konfigurację dnf-automatic lub yum-cron"
fi

# Sprawdzanie systemów zapobiegania włamaniom (Fail2ban lub CrowdSec)
IPS_INSTALLED=0
IPS_ACTIVE=0

if command -v dpkg >/dev/null 2>&1 && dpkg -l 2>/dev/null | grep -q "fail2ban"; then
    IPS_INSTALLED=1
    systemctl is-active fail2ban >/dev/null 2>&1 && IPS_ACTIVE=1
fi

# Sprawdzanie kontenera Docker z fail2ban
if command -v docker >/dev/null 2>&1; then
    if systemctl is-active --quiet docker 2>/dev/null || docker info >/dev/null 2>&1; then
        if docker ps -a 2>/dev/null | awk '{print $2}' | grep "fail2ban" >/dev/null 2>&1; then
            IPS_INSTALLED=1
            docker ps 2>/dev/null | grep -q "fail2ban" && IPS_ACTIVE=1
        fi
    fi
fi

if command -v dpkg >/dev/null 2>&1 && dpkg -l 2>/dev/null | grep -q "crowdsec"; then
    IPS_INSTALLED=1
    systemctl is-active crowdsec >/dev/null 2>&1 && IPS_ACTIVE=1
fi

# Sprawdzanie kontenera Docker z CrowdSec
if command -v docker >/dev/null 2>&1; then
    if systemctl is-active --quiet docker 2>/dev/null || docker info >/dev/null 2>&1; then
        if docker ps -a 2>/dev/null | awk '{print $2}' | grep "crowdsec" >/dev/null 2>&1; then
            IPS_INSTALLED=1
            docker ps 2>/dev/null | grep -q "crowdsec" && IPS_ACTIVE=1
        fi
    fi
fi

case "$IPS_INSTALLED$IPS_ACTIVE" in
    "11") check_security "Ochrona przed włamaniami" "PASS" "Fail2ban lub CrowdSec jest zainstalowany i działa" ;;
    "10") check_security "Ochrona przed włamaniami" "WARN" "Fail2ban lub CrowdSec jest zainstalowany, ale nie działa - uruchom usługę" ;;
    *)    check_security "Ochrona przed włamaniami" "FAIL" "Brak systemu ochrony przed włamaniami (Fail2ban/CrowdSec). Zainstaluj: apt install fail2ban" ;;
esac

# Sprawdzanie nieudanych prób logowania
LOG_FILE="/var/log/auth.log"

if [ -f "$LOG_FILE" ]; then
    FAILED_LOGINS=$(grep -c "Failed password" "$LOG_FILE" 2>/dev/null || echo 0)
elif [ -f "/etc/debian_version" ]; then
    DEB_VERSION=$(cut -d'.' -f1 /etc/debian_version 2>/dev/null)
    if [ -n "$DEB_VERSION" ] && [ "$DEB_VERSION" -gt 10 ] 2>/dev/null; then
        FAILED_LOGINS=$(journalctl -u ssh --since "24 hours ago" 2>/dev/null | grep -c "Failed password" || echo 0)
    else
        FAILED_LOGINS=0
    fi
else
    FAILED_LOGINS=0
    check_security "Log uwierzytelniania" "WARN" "Plik logu $LOG_FILE nie znaleziony. Przyjęto 0 nieudanych prób logowania."
fi

# Upewnienie się, że wartość jest numeryczna
FAILED_LOGINS=$(echo "$FAILED_LOGINS" | tr -d '[:space:]')
FAILED_LOGINS=$((10#${FAILED_LOGINS:-0}))

if [ "$FAILED_LOGINS" -lt 10 ]; then
    check_security "Nieudane logowania" "PASS" "Wykryto tylko $FAILED_LOGINS nieudanych prób logowania - to w normie"
elif [ "$FAILED_LOGINS" -lt 50 ]; then
    check_security "Nieudane logowania" "WARN" "Wykryto $FAILED_LOGINS nieudanych prób logowania - może wskazywać na próby włamania"
else
    check_security "Nieudane logowania" "FAIL" "Wykryto $FAILED_LOGINS nieudanych prób logowania - możliwy atak brute force. Rozważ zainstalowanie fail2ban"
fi

# Sprawdzanie aktualizacji systemu
if command -v apt-get >/dev/null 2>&1; then
    UPDATES=$(apt-get -s upgrade 2>/dev/null | grep -P '^\d+ upgraded' | cut -d" " -f1)
    if [ -z "$UPDATES" ]; then
        UPDATES=0
    fi
    if [ "$UPDATES" -eq 0 ]; then
        check_security "Aktualizacje systemu" "PASS" "Wszystkie pakiety systemowe są aktualne"
    else
        check_security "Aktualizacje systemu" "FAIL" "Dostępnych $UPDATES aktualizacji - system jest podatny na znane zagrożenia. Uruchom: apt update && apt upgrade"
    fi
fi

# Sprawdzanie uruchomionych usług
if command -v systemctl >/dev/null 2>&1; then
    SERVICES=$(systemctl list-units --type=service --state=running 2>/dev/null | grep -c "loaded active running")
    if [ "$IS_LXC" -eq 1 ]; then
        # W kontenerze LXC minimalny dobrze zabezpieczony system ma ~17 usług
        # (systemd + ssh + fail2ban + unattended-upgrades + sesje użytkowników)
        if [ "$SERVICES" -lt 25 ]; then
            check_security "Uruchomione usługi" "PASS" "Standardowa liczba usług w kontenerze ($SERVICES)"
        elif [ "$SERVICES" -lt 40 ]; then
            check_security "Uruchomione usługi" "WARN" "$SERVICES usług uruchomionych - sprawdź czy wszystkie są potrzebne (systemctl list-units --type=service --state=running)"
        else
            check_security "Uruchomione usługi" "FAIL" "Zbyt wiele usług uruchomionych ($SERVICES) - zwiększa powierzchnię ataku"
        fi
    else
        if [ "$SERVICES" -lt 20 ]; then
            check_security "Uruchomione usługi" "PASS" "Minimalna liczba usług ($SERVICES) - dobrze dla bezpieczeństwa"
        elif [ "$SERVICES" -lt 40 ]; then
            check_security "Uruchomione usługi" "WARN" "$SERVICES usług uruchomionych - rozważ ograniczenie powierzchni ataku"
        else
            check_security "Uruchomione usługi" "FAIL" "Zbyt wiele usług uruchomionych ($SERVICES) - zwiększa powierzchnię ataku"
        fi
    fi
else
    check_security "Uruchomione usługi" "INFO" "systemctl niedostępny - pominięto sprawdzanie usług"
fi

# Sprawdzanie portów za pomocą ss lub netstat
# UWAGA: Poprawiono parsowanie IPv6 względem oryginalnego vps-audit
# (oryginalny skrypt używał awk -F':' co łamało adresy IPv6 typu [::]:port)
if command -v ss >/dev/null 2>&1; then
    LISTENING_RAW=$(ss -tuln | grep LISTEN | awk '{print $5}')
elif command -v netstat >/dev/null 2>&1; then
    LISTENING_RAW=$(netstat -tuln | grep LISTEN | awk '{print $4}')
else
    check_security "Skanowanie portów" "FAIL" "Brak narzędzi 'ss' ani 'netstat' w systemie."
    LISTENING_RAW=""
fi

# Przetwarzanie portów - poprawna obsługa IPv6
# Format ss: [::]:port, [::1]:port, *:port, 0.0.0.0:port, 127.0.0.1:port
if [ -n "$LISTENING_RAW" ]; then
    PUBLIC_PORTS=$(echo "$LISTENING_RAW" | sed 's/.*://' | sort -n | uniq | tr '\n' ',' | sed 's/,$//')
    PORT_COUNT=$(echo "$PUBLIC_PORTS" | tr ',' '\n' | wc -w)
    INTERNET_PORTS=$(echo "$PUBLIC_PORTS" | tr ',' '\n' | wc -w)

    if [ "$IS_LXC" -eq 1 ]; then
        # Na Mikrusie porty są ograniczone przez hosta - więcej otwartych portów jest normalne
        if [ "$PORT_COUNT" -lt 15 ]; then
            check_security "Bezpieczeństwo portów" "PASS" "Dobra konfiguracja (Razem: $PORT_COUNT nasłuchujących portów): $PUBLIC_PORTS"
        elif [ "$PORT_COUNT" -lt 25 ]; then
            check_security "Bezpieczeństwo portów" "WARN" "Zalecany przegląd (Razem: $PORT_COUNT nasłuchujących portów): $PUBLIC_PORTS"
        else
            check_security "Bezpieczeństwo portów" "FAIL" "Wysoka ekspozycja (Razem: $PORT_COUNT nasłuchujących portów): $PUBLIC_PORTS"
        fi
        check_security "Porty Mikrus" "INFO" "Pamiętaj: z zewnątrz dostępne są tylko porty przekierowane przez Mikrusa (10000+ID, 20000+ID, 30000+ID). Porty IPv6 są dostępne bez ograniczeń"
    else
        if [ "$PORT_COUNT" -lt 10 ] && [ "$INTERNET_PORTS" -lt 3 ]; then
            check_security "Bezpieczeństwo portów" "PASS" "Dobra konfiguracja (Razem: $PORT_COUNT, Publicznych: $INTERNET_PORTS): $PUBLIC_PORTS"
        elif [ "$PORT_COUNT" -lt 20 ] && [ "$INTERNET_PORTS" -lt 5 ]; then
            check_security "Bezpieczeństwo portów" "WARN" "Zalecany przegląd (Razem: $PORT_COUNT, Publicznych: $INTERNET_PORTS): $PUBLIC_PORTS"
        else
            check_security "Bezpieczeństwo portów" "FAIL" "Wysoka ekspozycja (Razem: $PORT_COUNT, Publicznych: $INTERNET_PORTS): $PUBLIC_PORTS"
        fi
    fi
else
    check_security "Skanowanie portów" "WARN" "Skanowanie portów nie powiodło się - brak narzędzi. Zainstaluj 'ss' lub 'netstat'"
fi

# Sprawdzanie użycia dysku
DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
DISK_AVAIL=$(df -h / | awk 'NR==2 {print $4}')
DISK_USAGE=$(df -h / | awk 'NR==2 {print int($5)}')
if [ "$DISK_USAGE" -lt 50 ]; then
    check_security "Użycie dysku" "PASS" "Zdrowe użycie dysku (${DISK_USAGE}% - Użyte: ${DISK_USED} z ${DISK_TOTAL}, Dostępne: ${DISK_AVAIL})"
elif [ "$DISK_USAGE" -lt 80 ]; then
    check_security "Użycie dysku" "WARN" "Umiarkowane użycie dysku (${DISK_USAGE}% - Użyte: ${DISK_USED} z ${DISK_TOTAL}, Dostępne: ${DISK_AVAIL})"
else
    check_security "Użycie dysku" "FAIL" "Krytyczne użycie dysku (${DISK_USAGE}% - Użyte: ${DISK_USED} z ${DISK_TOTAL}, Dostępne: ${DISK_AVAIL}). Rozważ wyczyszczenie lub dokupienie Storage w panelu Mikrusa"
fi

# Sprawdzanie użycia pamięci
MEM_TOTAL=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}')
MEM_USED=$(free -h 2>/dev/null | awk '/^Mem:/ {print $3}')
MEM_AVAIL=$(free -h 2>/dev/null | awk '/^Mem:/ {print $7}')
MEM_USAGE=$(free 2>/dev/null | awk '/^Mem:/ {printf "%.0f", $3/$2 * 100}')

if [ -n "$MEM_USAGE" ]; then
    if [ "$IS_LXC" -eq 1 ]; then
        # Na Mikrusie RAM jest ograniczony (384MB na 1.0, więcej na wyższych planach)
        if [ "$MEM_USAGE" -lt 60 ]; then
            check_security "Użycie pamięci" "PASS" "Prawidłowe użycie pamięci (${MEM_USAGE}% - Użyte: ${MEM_USED} z ${MEM_TOTAL}, Dostępne: ${MEM_AVAIL})"
        elif [ "$MEM_USAGE" -lt 85 ]; then
            check_security "Użycie pamięci" "WARN" "Podwyższone użycie pamięci (${MEM_USAGE}% - Użyte: ${MEM_USED} z ${MEM_TOTAL}, Dostępne: ${MEM_AVAIL}). Na Mikrusie RAM jest ograniczony - rozważ optymalizację usług"
        else
            check_security "Użycie pamięci" "FAIL" "Krytyczne użycie pamięci (${MEM_USAGE}% - Użyte: ${MEM_USED} z ${MEM_TOTAL}, Dostępne: ${MEM_AVAIL}). Używaj polecenia 'amfetamina' w panelu Mikrusa na tymczasowe zwiększenie zasobów"
        fi
    else
        if [ "$MEM_USAGE" -lt 50 ]; then
            check_security "Użycie pamięci" "PASS" "Zdrowe użycie pamięci (${MEM_USAGE}% - Użyte: ${MEM_USED} z ${MEM_TOTAL}, Dostępne: ${MEM_AVAIL})"
        elif [ "$MEM_USAGE" -lt 80 ]; then
            check_security "Użycie pamięci" "WARN" "Umiarkowane użycie pamięci (${MEM_USAGE}% - Użyte: ${MEM_USED} z ${MEM_TOTAL}, Dostępne: ${MEM_AVAIL})"
        else
            check_security "Użycie pamięci" "FAIL" "Krytyczne użycie pamięci (${MEM_USAGE}% - Użyte: ${MEM_USED} z ${MEM_TOTAL}, Dostępne: ${MEM_AVAIL})"
        fi
    fi
else
    check_security "Użycie pamięci" "WARN" "Nie udało się odczytać użycia pamięci"
fi

# Sprawdzanie użycia CPU
CPU_CORES=$(nproc 2>/dev/null || echo "1")
CPU_USAGE=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print int($2)}')
CPU_IDLE=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print int($8)}')
CPU_LOAD=$(uptime | awk -F'load average:' '{ print $2 }' | awk -F',' '{ print $1 }' | tr -d ' ')

if [ -n "$CPU_USAGE" ]; then
    if [ "$IS_LXC" -eq 1 ]; then
        check_security "Użycie CPU" "INFO" "CPU: ${CPU_USAGE}% (Aktywne: ${CPU_USAGE}%, Bezczynne: ${CPU_IDLE}%, Rdzenie: ${CPU_CORES}). UWAGA: Load Average ($CPU_LOAD) w LXC odzwierciedla obciążenie całego serwera fizycznego, nie kontenera"
    else
        if [ "$CPU_USAGE" -lt 50 ]; then
            check_security "Użycie CPU" "PASS" "Prawidłowe użycie CPU (${CPU_USAGE}% - Aktywne: ${CPU_USAGE}%, Bezczynne: ${CPU_IDLE}%, Load: ${CPU_LOAD}, Rdzenie: ${CPU_CORES})"
        elif [ "$CPU_USAGE" -lt 80 ]; then
            check_security "Użycie CPU" "WARN" "Umiarkowane użycie CPU (${CPU_USAGE}% - Aktywne: ${CPU_USAGE}%, Bezczynne: ${CPU_IDLE}%, Load: ${CPU_LOAD}, Rdzenie: ${CPU_CORES})"
        else
            check_security "Użycie CPU" "FAIL" "Krytyczne użycie CPU (${CPU_USAGE}% - Aktywne: ${CPU_USAGE}%, Bezczynne: ${CPU_IDLE}%, Load: ${CPU_LOAD}, Rdzenie: ${CPU_CORES})"
        fi
    fi
else
    check_security "Użycie CPU" "WARN" "Nie udało się odczytać użycia CPU"
fi

# Sprawdzanie konfiguracji sudo
if [ -f /etc/sudoers ]; then
    if grep -q "^Defaults.*logfile" /etc/sudoers 2>/dev/null; then
        check_security "Logowanie sudo" "PASS" "Polecenia sudo są logowane w celach audytu"
    else
        check_security "Logowanie sudo" "FAIL" "Polecenia sudo nie są logowane - ogranicza możliwości audytu. Dodaj 'Defaults logfile=/var/log/sudo.log' do /etc/sudoers"
    fi
else
    check_security "Logowanie sudo" "INFO" "Plik /etc/sudoers nie znaleziony"
fi

# Sprawdzanie polityki haseł
# Jeżeli SSH wymaga kluczy (hasło wyłączone), polityka haseł jest mniej krytyczna
if [ -f "/etc/security/pwquality.conf" ]; then
    if grep -q "minlen.*12" /etc/security/pwquality.conf; then
        check_security "Polityka haseł" "PASS" "Silna polityka haseł jest wymuszona"
    else
        if [ "$SSH_PASSWORD" = "no" ]; then
            check_security "Polityka haseł" "WARN" "Słaba polityka haseł, ale SSH wymaga kluczy - mniejsze ryzyko"
        else
            check_security "Polityka haseł" "FAIL" "Słaba polityka haseł - hasła mogą być zbyt proste. Ustaw minlen=12 w /etc/security/pwquality.conf"
        fi
    fi
else
    if [ "$SSH_PASSWORD" = "no" ]; then
        check_security "Polityka haseł" "WARN" "Brak polityki haseł, ale SSH wymaga kluczy - mniejsze ryzyko. Rozważ instalację: apt install libpam-pwquality"
    else
        check_security "Polityka haseł" "FAIL" "Brak skonfigurowanej polityki haseł - system akceptuje słabe hasła. Zainstaluj: apt install libpam-pwquality"
    fi
fi

# Sprawdzanie podejrzanych plików SUID (z timeoutem - w LXC może trwać długo)
COMMON_SUID_PATHS='^/usr/bin/|^/bin/|^/sbin/|^/usr/sbin/|^/usr/lib|^/usr/libexec'
KNOWN_SUID_BINS='ping$|sudo$|mount$|umount$|su$|passwd$|chsh$|newgrp$|gpasswd$|chfn$'

if [ "$IS_LXC" -eq 1 ]; then
    # W kontenerze LXC ograniczamy skanowanie do /usr i /tmp (szybsze, mniej fałszywie pozytywnych)
    SUID_FILES=$(timeout 15 find /usr /tmp /home -type f -perm -4000 2>/dev/null | \
        grep -v -E "$COMMON_SUID_PATHS" | \
        grep -v -E "$KNOWN_SUID_BINS" | \
        wc -l)
else
    SUID_FILES=$(timeout 30 find / -type f -perm -4000 2>/dev/null | \
        grep -v -E "$COMMON_SUID_PATHS" | \
        grep -v -E "$KNOWN_SUID_BINS" | \
        wc -l)
fi

if [ "$SUID_FILES" -eq 0 ]; then
    check_security "Pliki SUID" "PASS" "Nie znaleziono podejrzanych plików SUID"
else
    check_security "Pliki SUID" "WARN" "Znaleziono $SUID_FILES plików SUID poza standardowymi lokalizacjami - sprawdź czy są uzasadnione"
fi

# =============================================================================
# Dodatkowe sprawdzenia specyficzne dla Mikrusa
# =============================================================================

print_header "Sprawdzenia specyficzne dla Mikrusa"

# Sprawdzanie dostępności SSH
SSH_CHECK_PORT=$(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | head -1 | awk '{print $2}')
SSH_CHECK_PORT=${SSH_CHECK_PORT:-22}
if timeout 3 bash -c "echo > /dev/tcp/localhost/$SSH_CHECK_PORT" 2>/dev/null; then
    check_security "Dostępność SSH" "PASS" "SSH odpowiada na porcie $SSH_CHECK_PORT"
else
    check_security "Dostępność SSH" "FAIL" "SSH nie odpowiada na porcie $SSH_CHECK_PORT - ryzyko utraty dostępu!"
fi

# Sprawdzanie IPv6
# UWAGA: grep -v "::1" z oryginału filtrował też adresy typu ::178 (::1 jest podciągiem)
# Poprawiono na dokładne dopasowanie ::1/128 (loopback)
IPV6_ADDR=$(ip -6 addr show 2>/dev/null | grep "inet6" | grep -v "fe80" | grep -v " ::1/128" | awk '{print $2}' | head -1)
if [ -n "$IPV6_ADDR" ]; then
    check_security "Adres IPv6" "PASS" "Przydzielony adres IPv6: $IPV6_ADDR (kluczowy dla Mikrusa)"
else
    check_security "Adres IPv6" "WARN" "Nie wykryto globalnego adresu IPv6 - na Mikrusie IPv6 jest podstawą działania"
fi

# Sprawdzanie czy usługi nasłuchują na IPv6
if command -v ss >/dev/null 2>&1; then
    IPV6_SERVICES=$(ss -tuln 2>/dev/null | grep -c "\[::\]")
    IPV4_ONLY=$(ss -tuln 2>/dev/null | grep "LISTEN" | grep -c "127.0.0.1\|0.0.0.0" )
    if [ "$IPV6_SERVICES" -gt 0 ]; then
        check_security "Usługi IPv6" "PASS" "Znaleziono $IPV6_SERVICES usług nasłuchujących na IPv6"
    else
        check_security "Usługi IPv6" "WARN" "Brak usług nasłuchujących na IPv6 - na Mikrusie usługi muszą słuchać na [::] lub 0.0.0.0 aby być dostępne"
    fi
fi

# Sprawdzanie Dockera
if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
        DOCKER_CONTAINERS=$(docker ps -q 2>/dev/null | wc -l)
        DOCKER_ALL=$(docker ps -aq 2>/dev/null | wc -l)
        DOCKER_IMAGES=$(docker images -q 2>/dev/null | wc -l)
        check_security "Docker" "INFO" "Docker aktywny - Kontenery: $DOCKER_CONTAINERS uruchomionych / $DOCKER_ALL wszystkich, Obrazy: $DOCKER_IMAGES"

        # Sprawdzanie czy kontenery Docker nasłuchują na odpowiednich portach
        DOCKER_PORTS=$(docker ps --format '{{.Ports}}' 2>/dev/null | grep -oP '\d+\.\d+\.\d+\.\d+:\d+' | sort -u)
        if [ -n "$DOCKER_PORTS" ]; then
            check_security "Porty Docker" "INFO" "Kontenery nasłuchują na: $DOCKER_PORTS"
        fi

        # Sprawdzanie zatrzymanych/uszkodzonych kontenerów
        EXITED_CONTAINERS=$(docker ps -a --filter "status=exited" -q 2>/dev/null | wc -l)
        if [ "$EXITED_CONTAINERS" -gt 0 ]; then
            EXITED_NAMES=$(docker ps -a --filter "status=exited" --format '{{.Names}}' 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
            check_security "Kontenery Docker" "WARN" "Znaleziono $EXITED_CONTAINERS zatrzymanych kontenerów: $EXITED_NAMES. Sprawdź logi: docker logs <nazwa>"
        fi

        # Sprawdzanie nieużywanych obrazów Docker
        DANGLING=$(docker images -f "dangling=true" -q 2>/dev/null | wc -l)
        if [ "$DANGLING" -gt 0 ]; then
            check_security "Obrazy Docker" "WARN" "Znaleziono $DANGLING nieużywanych obrazów Docker - zajmują miejsce. Wyczyść: docker image prune"
        fi
    else
        check_security "Docker" "INFO" "Docker zainstalowany, ale nieaktywny"
    fi
else
    check_security "Docker" "INFO" "Docker nie jest zainstalowany"
fi

# Sprawdzanie konfiguracji DNS
if [ -f /etc/resolv.conf ]; then
    DNS_SERVERS=$(grep "^nameserver" /etc/resolv.conf | awk '{print $2}' | tr '\n' ', ' | sed 's/,$//')
    check_security "Serwery DNS" "INFO" "Skonfigurowane serwery DNS: $DNS_SERVERS"
fi

# Sprawdzanie uprawnień ważnych plików
SENSITIVE_FILES="/etc/shadow /etc/gshadow /etc/passwd /etc/ssh/sshd_config"
PERM_ISSUES=0
for f in $SENSITIVE_FILES; do
    if [ -f "$f" ]; then
        PERMS=$(stat -c %a "$f" 2>/dev/null || stat -f %Lp "$f" 2>/dev/null)
        case "$f" in
            /etc/shadow|/etc/gshadow)
                if [ "$PERMS" != "640" ] && [ "$PERMS" != "600" ] && [ "$PERMS" != "0" ]; then
                    PERM_ISSUES=$((PERM_ISSUES + 1))
                    check_security "Uprawnienia plików" "FAIL" "$f ma uprawnienia $PERMS (powinno być 640 lub mniej)"
                fi
                ;;
            /etc/passwd)
                if [ "$PERMS" != "644" ]; then
                    PERM_ISSUES=$((PERM_ISSUES + 1))
                    check_security "Uprawnienia plików" "WARN" "$f ma uprawnienia $PERMS (powinno być 644)"
                fi
                ;;
        esac
    fi
done
if [ "$PERM_ISSUES" -eq 0 ]; then
    check_security "Uprawnienia plików" "PASS" "Uprawnienia ważnych plików systemowych są prawidłowe"
fi

# Sprawdzanie czy są użytkownicy z pustym hasłem
# UWAGA: konta z "!" lub "!!" to konta CELOWO ZABLOKOWANE (np. sshd, messagebus) - to jest OK
# Szukamy tylko kont z naprawdę pustym polem hasła (brak jakiejkolwiek wartości)
EMPTY_PASS=$(awk -F: '($2 == "") {print $1}' /etc/shadow 2>/dev/null | grep -v "^$" | wc -l)
if [ "$EMPTY_PASS" -gt 0 ]; then
    EMPTY_USERS=$(awk -F: '($2 == "") {print $1}' /etc/shadow 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
    check_security "Puste hasła" "FAIL" "Znaleziono $EMPTY_PASS kont z pustym hasłem (brak zabezpieczenia!): $EMPTY_USERS"
else
    check_security "Puste hasła" "PASS" "Brak kont z pustymi hasłami"
fi

# Sprawdzanie kont z zablokowanym logowaniem (informacyjnie)
LOCKED_PASS=$(awk -F: '($2 == "!" || $2 == "!!" || $2 == "*") {print $1}' /etc/shadow 2>/dev/null | grep -v "^$" | wc -l)
if [ "$LOCKED_PASS" -gt 0 ]; then
    check_security "Zablokowane konta" "INFO" "$LOCKED_PASS kont z zablokowanym logowaniem hasłem (to jest poprawne zabezpieczenie)"
fi

# Podsumowanie informacji o systemie w raporcie
echo "================================" >> "$REPORT_FILE"
echo "Podsumowanie systemu:" >> "$REPORT_FILE"
echo "Nazwa hosta: $(hostname)" >> "$REPORT_FILE"
echo "Jądro: $(uname -r)" >> "$REPORT_FILE"
echo "System: $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2)" >> "$REPORT_FILE"
echo "Rdzenie CPU: $(nproc 2>/dev/null)" >> "$REPORT_FILE"
echo "Pamięć RAM: $(free -h 2>/dev/null | awk '/^Mem:/ {print $2}')" >> "$REPORT_FILE"
echo "Przestrzeń dyskowa: $(df -h / | awk 'NR==2 {print $2}')" >> "$REPORT_FILE"
if [ "$IS_LXC" -eq 1 ]; then
    echo "Środowisko: Kontener LXC (Mikr.us/Proxmox)" >> "$REPORT_FILE"
fi
echo "================================" >> "$REPORT_FILE"

echo -e "\n${GREEN}${BOLD}Audyt zakończony.${NC} Pełny raport zapisany do ${BOLD}$REPORT_FILE${NC}"
echo -e "Przejrzyj raport i wdróż zalecane poprawki."
if [ "$IS_LXC" -eq 1 ]; then
    echo -e "\n${YELLOW}Wskazówki dla Mikrusa:${NC}"
    echo -e "  - Dokumentacja: ${BLUE}https://wiki.mikr.us/${NC}"
    echo -e "  - Panel zarządzania: ${BLUE}https://mikr.us/panel/${NC}"
    echo -e "  - Porady dot. SSH: użyj kluczy SSH zamiast haseł"
    echo -e "  - IPv6 jest podstawą - upewnij się że usługi słuchają na [::]:port"
fi

# Zakończenie raportu
echo "================================" >> "$REPORT_FILE"
echo "Koniec raportu audytu VPS" >> "$REPORT_FILE"
echo "Przejrzyj wszystkie nieudane testy i wdróż zalecane poprawki." >> "$REPORT_FILE"
if [ "$IS_LXC" -eq 1 ]; then
    echo "" >> "$REPORT_FILE"
    echo "Wskazówki dla Mikrusa:" >> "$REPORT_FILE"
    echo "- Dokumentacja: https://wiki.mikr.us/" >> "$REPORT_FILE"
    echo "- Panel: https://mikr.us/panel/" >> "$REPORT_FILE"
    echo "- Używaj kluczy SSH zamiast haseł" >> "$REPORT_FILE"
    echo "- Usługi muszą słuchać na IPv6 ([::]:port lub 0.0.0.0:port)" >> "$REPORT_FILE"
    echo "- Load Average w kontenerze LXC pokazuje obciążenie hosta, nie kontenera" >> "$REPORT_FILE"
fi
