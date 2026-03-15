#!/usr/bin/env bash

# =============================================================================
# Mikrus Audit - Skrypt audytu bezpieczenstwa VPS
# Wersja: 1.0.0
#
# Fork projektu vps-audit (https://github.com/vernu/vps-audit) autorstwa
# vernu (https://github.com/vernu). Oryginalny projekt na licencji MIT.
#
# Ten fork dodaje:
#   - Pelne tlumaczenie na jezyk polski
#   - Adaptacje do srodowiska Mikr.us (kontenery LXC/Proxmox)
#   - Poprawki bledow z oryginalnego skryptu (parsowanie IPv6, journalctl)
#   - Dodatkowe sprawdzenia bezpieczenstwa (IPv6, Docker, uprawnienia plikow)
#
# Repozytorium forka: https://github.com/simplybychris/vps-audit
# Oryginal: https://github.com/vernu/vps-audit
# =============================================================================

# Kolory do wyswietlania
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

# Wykrywanie srodowiska LXC (Mikr.us uzywa kontenerow LXC na Proxmox)
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

# Rozpoczecie audytu
echo -e "${BLUE}${BOLD}Mikrus Audit - Audyt bezpieczenstwa VPS${NC}"
echo -e "${GRAY}Bazuje na: https://github.com/vernu/vps-audit${NC}"
echo -e "${GRAY}Rozpoczecie audytu: $(date)${NC}\n"

echo "Mikrus Audit - Audyt bezpieczenstwa VPS" > "$REPORT_FILE"
echo "Bazuje na: https://github.com/vernu/vps-audit" >> "$REPORT_FILE"
echo "Rozpoczecie audytu: $(date)" >> "$REPORT_FILE"
echo "================================" >> "$REPORT_FILE"

if [ "$IS_LXC" -eq 1 ]; then
    echo -e "${YELLOW}${BOLD}Wykryto kontener LXC (Mikr.us/Proxmox)${NC}"
    echo -e "${GRAY}Niektore wyniki moga sie roznic od standardowego VPS${NC}\n"
    echo "UWAGA: Wykryto srodowisko LXC (kontener Proxmox)" >> "$REPORT_FILE"
    echo "Wyniki zostaly dostosowane do specyfiki kontenerow." >> "$REPORT_FILE"
    echo "" >> "$REPORT_FILE"
fi

# Sekcja informacji o systemie
print_header "Informacje o systemie"

# Pobieranie informacji o systemie
OS_INFO=$(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2)
KERNEL_VERSION=$(uname -r)
CURRENT_HOSTNAME=$HOSTNAME
UPTIME_INFO=$(uptime -p 2>/dev/null || uptime)
UPTIME_SINCE=$(uptime -s 2>/dev/null || echo "niedostepne")
CPU_INFO=$(lscpu 2>/dev/null | grep "Model name" | cut -d':' -f2 | xargs)
CPU_CORES=$(nproc 2>/dev/null || echo "nieznane")
TOTAL_MEM=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}')
TOTAL_DISK=$(df -h / | awk 'NR==2 {print $2}')
PUBLIC_IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null || echo "niedostepny")
PUBLIC_IPV6=$(curl -s --max-time 5 https://api6.ipify.org 2>/dev/null || echo "niedostepny")
LOAD_AVERAGE=$(uptime | awk -F'load average:' '{print $2}' | xargs)

# Wyswietlanie informacji o systemie
print_info "Nazwa hosta" "$CURRENT_HOSTNAME"
print_info "System operacyjny" "$OS_INFO"
print_info "Wersja jadra" "$KERNEL_VERSION"
print_info "Czas pracy" "$UPTIME_INFO (od $UPTIME_SINCE)"
print_info "Model CPU" "$CPU_INFO"
print_info "Rdzenie CPU" "$CPU_CORES"
print_info "Pamiec RAM" "$TOTAL_MEM"
print_info "Przestrzen dyskowa" "$TOTAL_DISK"
print_info "Publiczny IP (IPv4)" "$PUBLIC_IP"
print_info "Publiczny IP (IPv6)" "$PUBLIC_IPV6"

if [ "$IS_LXC" -eq 1 ]; then
    print_info "Load Average" "$LOAD_AVERAGE (UWAGA: w LXC pokazuje obciazenie hosta Proxmox, nie kontenera)"
else
    print_info "Load Average" "$LOAD_AVERAGE"
fi

echo "" >> "$REPORT_FILE"

# Sekcja audytu bezpieczenstwa
print_header "Wyniki audytu bezpieczenstwa"

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
            echo -e "${RED}[BLAD]${NC} $test_name ${GRAY}- $message${NC}"
            echo "[BLAD] $test_name - $message" >> "$REPORT_FILE"
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
UPTIME_SINCE=$(uptime -s 2>/dev/null || echo "niedostepne")
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

# Sprawdzanie nadpisow konfiguracji SSH
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
    check_security "Logowanie root SSH" "PASS" "Logowanie jako root jest prawidlowo wylaczone w konfiguracji SSH"
elif [ "$SSH_ROOT" = "prohibit-password" ]; then
    check_security "Logowanie root SSH" "WARN" "Logowanie root dozwolone tylko kluczem SSH (prohibit-password). Rozważ calkowite wylaczenie w /etc/ssh/sshd_config"
else
    check_security "Logowanie root SSH" "FAIL" "Logowanie jako root jest dozwolone - to ryzyko bezpieczenstwa. Wylacz w /etc/ssh/sshd_config (PermitRootLogin no)"
fi

# Sprawdzanie uwierzytelniania haslem SSH
if [ -n "$SSH_CONFIG_OVERRIDES" ] && [ -d "$(dirname "$SSH_CONFIG_OVERRIDES")" ]; then
    SSH_PASSWORD=$(grep "^PasswordAuthentication" $SSH_CONFIG_OVERRIDES /etc/ssh/sshd_config 2>/dev/null | head -1 | awk '{print $2}')
else
    SSH_PASSWORD=$(grep "^PasswordAuthentication" /etc/ssh/sshd_config 2>/dev/null | head -1 | awk '{print $2}')
fi
if [ -z "$SSH_PASSWORD" ]; then
    SSH_PASSWORD="yes"
fi
if [ "$SSH_PASSWORD" = "no" ]; then
    check_security "Haslo SSH" "PASS" "Uwierzytelnianie haslem jest wylaczone - dozwolone tylko klucze SSH"
else
    check_security "Haslo SSH" "FAIL" "Uwierzytelnianie haslem jest wlaczone - rozważ wylaczenie i uzycie tylko kluczy SSH (PasswordAuthentication no)"
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
    # Na Mikrusie SSH slucha na porcie 22 wewnatrz kontenera,
    # ale jest dostepny z zewnatrz na porcie 10000+ID
    check_security "Port SSH" "INFO" "Port SSH: $SSH_PORT (wewnatrz kontenera). Na Mikrusie dostep z zewnatrz jest przez port 10000+ID - to jest normalne"
elif [ "$SSH_PORT" = "22" ]; then
    check_security "Port SSH" "WARN" "Uzyto domyslnego portu 22 - rozważ zmiane na niestandardowy port dla dodatkowej ochrony"
elif [ "$SSH_PORT" -ge "$UNPRIVILEGED_PORT_START" ] 2>/dev/null; then
    check_security "Port SSH" "FAIL" "Uzyto nieuprzywilejowanego portu $SSH_PORT - uzyj portu ponizej $UNPRIVILEGED_PORT_START dla lepszego bezpieczenstwa"
else
    check_security "Port SSH" "PASS" "Uzyto niestandardowego portu $SSH_PORT - utrudnia automatyczne ataki"
fi

# Sprawdzanie statusu zapory ogniowej
check_firewall_status() {
    if command -v ufw >/dev/null 2>&1; then
        if ufw status 2>/dev/null | grep -qw "active"; then
            check_security "Zapora ogniowa (UFW)" "PASS" "Zapora UFW jest aktywna i chroni system"
        else
            if [ "$IS_LXC" -eq 1 ]; then
                check_security "Zapora ogniowa (UFW)" "WARN" "Zapora UFW nie jest aktywna. W kontenerze LXC zapora moze byc zarzadzana na poziomie hosta Proxmox"
            else
                check_security "Zapora ogniowa (UFW)" "FAIL" "Zapora UFW nie jest aktywna - system jest narazony na ataki sieciowe"
            fi
        fi
    elif command -v firewall-cmd >/dev/null 2>&1; then
        if firewall-cmd --state 2>/dev/null | grep -q "running"; then
            check_security "Zapora ogniowa (firewalld)" "PASS" "Firewalld jest aktywny i chroni system"
        else
            check_security "Zapora ogniowa (firewalld)" "FAIL" "Firewalld nie jest aktywny - system jest narazony na ataki sieciowe"
        fi
    elif command -v iptables >/dev/null 2>&1; then
        if iptables -L -n 2>/dev/null | grep -q "Chain INPUT"; then
            check_security "Zapora ogniowa (iptables)" "PASS" "Reguly iptables sa aktywne i chronia system"
        else
            check_security "Zapora ogniowa (iptables)" "FAIL" "Brak aktywnych regul iptables - system moze byc narazony"
        fi
    elif command -v nft >/dev/null 2>&1; then
        if nft list ruleset 2>/dev/null | grep -q "table"; then
            check_security "Zapora ogniowa (nftables)" "PASS" "Reguly nftables sa aktywne i chronia system"
        else
            check_security "Zapora ogniowa (nftables)" "FAIL" "Brak aktywnych regul nftables - system moze byc narazony"
        fi
    else
        if [ "$IS_LXC" -eq 1 ]; then
            check_security "Zapora ogniowa" "WARN" "Brak zainstalowanego narzedzia zapory. W kontenerze LXC zapora moze byc zarzadzana przez hosta Proxmox"
        else
            check_security "Zapora ogniowa" "FAIL" "Brak zainstalowanego narzedzia zapory w systemie"
        fi
    fi
}

# Sprawdzenie zapory
check_firewall_status

# Sprawdzanie automatycznych aktualizacji
if command -v dpkg >/dev/null 2>&1; then
    if dpkg -l 2>/dev/null | grep -q "unattended-upgrades"; then
        check_security "Automatyczne aktualizacje" "PASS" "Automatyczne aktualizacje bezpieczenstwa sa skonfigurowane"
    else
        check_security "Automatyczne aktualizacje" "FAIL" "Automatyczne aktualizacje nie sa skonfigurowane - system moze pominac krytyczne poprawki. Zainstaluj: apt install unattended-upgrades"
    fi
elif command -v yum >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
    check_security "Automatyczne aktualizacje" "INFO" "System oparty na RPM - sprawdz konfiguracje dnf-automatic lub yum-cron"
fi

# Sprawdzanie systemow zapobiegania wlamaniom (Fail2ban lub CrowdSec)
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
    "11") check_security "Ochrona przed wlamaniami" "PASS" "Fail2ban lub CrowdSec jest zainstalowany i dziala" ;;
    "10") check_security "Ochrona przed wlamaniami" "WARN" "Fail2ban lub CrowdSec jest zainstalowany, ale nie dziala - uruchom usluge" ;;
    *)    check_security "Ochrona przed wlamaniami" "FAIL" "Brak systemu ochrony przed wlamaniami (Fail2ban/CrowdSec). Zainstaluj: apt install fail2ban" ;;
esac

# Sprawdzanie nieudanych prob logowania
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
    check_security "Log uwierzytelniania" "WARN" "Plik logu $LOG_FILE nie znaleziony. Przyjeto 0 nieudanych prob logowania."
fi

# Upewnienie sie, ze wartosc jest numeryczna
FAILED_LOGINS=$(echo "$FAILED_LOGINS" | tr -d '[:space:]')
FAILED_LOGINS=$((10#${FAILED_LOGINS:-0}))

if [ "$FAILED_LOGINS" -lt 10 ]; then
    check_security "Nieudane logowania" "PASS" "Wykryto tylko $FAILED_LOGINS nieudanych prob logowania - to w normie"
elif [ "$FAILED_LOGINS" -lt 50 ]; then
    check_security "Nieudane logowania" "WARN" "Wykryto $FAILED_LOGINS nieudanych prob logowania - moze wskazywac na proby wlamania"
else
    check_security "Nieudane logowania" "FAIL" "Wykryto $FAILED_LOGINS nieudanych prob logowania - mozliwy atak brute force. Rozważ zainstalowanie fail2ban"
fi

# Sprawdzanie aktualizacji systemu
if command -v apt-get >/dev/null 2>&1; then
    UPDATES=$(apt-get -s upgrade 2>/dev/null | grep -P '^\d+ upgraded' | cut -d" " -f1)
    if [ -z "$UPDATES" ]; then
        UPDATES=0
    fi
    if [ "$UPDATES" -eq 0 ]; then
        check_security "Aktualizacje systemu" "PASS" "Wszystkie pakiety systemowe sa aktualne"
    else
        check_security "Aktualizacje systemu" "FAIL" "Dostepnych $UPDATES aktualizacji - system jest podatny na znane zagrozenia. Uruchom: apt update && apt upgrade"
    fi
fi

# Sprawdzanie uruchomionych uslug
if command -v systemctl >/dev/null 2>&1; then
    SERVICES=$(systemctl list-units --type=service --state=running 2>/dev/null | grep -c "loaded active running")
    if [ "$IS_LXC" -eq 1 ]; then
        # W kontenerze LXC minimalny dobrze zabezpieczony system ma ~17 uslug
        # (systemd + ssh + fail2ban + unattended-upgrades + sesje uzytkownikow)
        if [ "$SERVICES" -lt 25 ]; then
            check_security "Uruchomione uslugi" "PASS" "Standardowa liczba uslug w kontenerze ($SERVICES)"
        elif [ "$SERVICES" -lt 40 ]; then
            check_security "Uruchomione uslugi" "WARN" "$SERVICES uslug uruchomionych - sprawdz czy wszystkie sa potrzebne (systemctl list-units --type=service --state=running)"
        else
            check_security "Uruchomione uslugi" "FAIL" "Zbyt wiele uslug uruchomionych ($SERVICES) - zwieksza powierzchnie ataku"
        fi
    else
        if [ "$SERVICES" -lt 20 ]; then
            check_security "Uruchomione uslugi" "PASS" "Minimalna liczba uslug ($SERVICES) - dobrze dla bezpieczenstwa"
        elif [ "$SERVICES" -lt 40 ]; then
            check_security "Uruchomione uslugi" "WARN" "$SERVICES uslug uruchomionych - rozważ ograniczenie powierzchni ataku"
        else
            check_security "Uruchomione uslugi" "FAIL" "Zbyt wiele uslug uruchomionych ($SERVICES) - zwieksza powierzchnie ataku"
        fi
    fi
else
    check_security "Uruchomione uslugi" "INFO" "systemctl niedostepny - pominieto sprawdzanie uslug"
fi

# Sprawdzanie portow za pomoca ss lub netstat
# UWAGA: Poprawiono parsowanie IPv6 wzgledem oryginalnego vps-audit
# (oryginalny skrypt uzywal awk -F':' co lamialo adresy IPv6 typu [::]:port)
if command -v ss >/dev/null 2>&1; then
    LISTENING_RAW=$(ss -tuln | grep LISTEN | awk '{print $5}')
elif command -v netstat >/dev/null 2>&1; then
    LISTENING_RAW=$(netstat -tuln | grep LISTEN | awk '{print $4}')
else
    check_security "Skanowanie portow" "FAIL" "Brak narzedzi 'ss' ani 'netstat' w systemie."
    LISTENING_RAW=""
fi

# Przetwarzanie portow - poprawna obsluga IPv6
# Format ss: [::]:port, [::1]:port, *:port, 0.0.0.0:port, 127.0.0.1:port
if [ -n "$LISTENING_RAW" ]; then
    PUBLIC_PORTS=$(echo "$LISTENING_RAW" | sed 's/.*://' | sort -n | uniq | tr '\n' ',' | sed 's/,$//')
    PORT_COUNT=$(echo "$PUBLIC_PORTS" | tr ',' '\n' | wc -w)
    INTERNET_PORTS=$(echo "$PUBLIC_PORTS" | tr ',' '\n' | wc -w)

    if [ "$IS_LXC" -eq 1 ]; then
        # Na Mikrusie porty sa ograniczone przez hosta - wiecej otwartych portow jest normalne
        if [ "$PORT_COUNT" -lt 15 ]; then
            check_security "Bezpieczenstwo portow" "PASS" "Dobra konfiguracja (Razem: $PORT_COUNT nasluchujacych portow): $PUBLIC_PORTS"
        elif [ "$PORT_COUNT" -lt 25 ]; then
            check_security "Bezpieczenstwo portow" "WARN" "Zalecany przeglad (Razem: $PORT_COUNT nasluchujacych portow): $PUBLIC_PORTS"
        else
            check_security "Bezpieczenstwo portow" "FAIL" "Wysoka ekspozycja (Razem: $PORT_COUNT nasluchujacych portow): $PUBLIC_PORTS"
        fi
        check_security "Porty Mikrus" "INFO" "Pamietaj: z zewnatrz dostepne sa tylko porty przekierowane przez Mikrusa (10000+ID, 20000+ID, 30000+ID). Porty IPv6 sa dostepne bez ograniczen"
    else
        if [ "$PORT_COUNT" -lt 10 ] && [ "$INTERNET_PORTS" -lt 3 ]; then
            check_security "Bezpieczenstwo portow" "PASS" "Dobra konfiguracja (Razem: $PORT_COUNT, Publicznych: $INTERNET_PORTS): $PUBLIC_PORTS"
        elif [ "$PORT_COUNT" -lt 20 ] && [ "$INTERNET_PORTS" -lt 5 ]; then
            check_security "Bezpieczenstwo portow" "WARN" "Zalecany przeglad (Razem: $PORT_COUNT, Publicznych: $INTERNET_PORTS): $PUBLIC_PORTS"
        else
            check_security "Bezpieczenstwo portow" "FAIL" "Wysoka ekspozycja (Razem: $PORT_COUNT, Publicznych: $INTERNET_PORTS): $PUBLIC_PORTS"
        fi
    fi
else
    check_security "Skanowanie portow" "WARN" "Skanowanie portow nie powiodlo sie - brak narzedzi. Zainstaluj 'ss' lub 'netstat'"
fi

# Sprawdzanie uzycia dysku
DISK_TOTAL=$(df -h / | awk 'NR==2 {print $2}')
DISK_USED=$(df -h / | awk 'NR==2 {print $3}')
DISK_AVAIL=$(df -h / | awk 'NR==2 {print $4}')
DISK_USAGE=$(df -h / | awk 'NR==2 {print int($5)}')
if [ "$DISK_USAGE" -lt 50 ]; then
    check_security "Uzycie dysku" "PASS" "Zdrowe uzycie dysku (${DISK_USAGE}% - Uzyte: ${DISK_USED} z ${DISK_TOTAL}, Dostepne: ${DISK_AVAIL})"
elif [ "$DISK_USAGE" -lt 80 ]; then
    check_security "Uzycie dysku" "WARN" "Umiarkowane uzycie dysku (${DISK_USAGE}% - Uzyte: ${DISK_USED} z ${DISK_TOTAL}, Dostepne: ${DISK_AVAIL})"
else
    check_security "Uzycie dysku" "FAIL" "Krytyczne uzycie dysku (${DISK_USAGE}% - Uzyte: ${DISK_USED} z ${DISK_TOTAL}, Dostepne: ${DISK_AVAIL}). Rozważ wyczyszczenie lub dokupienie Storage w panelu Mikrusa"
fi

# Sprawdzanie uzycia pamieci
MEM_TOTAL=$(free -h 2>/dev/null | awk '/^Mem:/ {print $2}')
MEM_USED=$(free -h 2>/dev/null | awk '/^Mem:/ {print $3}')
MEM_AVAIL=$(free -h 2>/dev/null | awk '/^Mem:/ {print $7}')
MEM_USAGE=$(free 2>/dev/null | awk '/^Mem:/ {printf "%.0f", $3/$2 * 100}')

if [ -n "$MEM_USAGE" ]; then
    if [ "$IS_LXC" -eq 1 ]; then
        # Na Mikrusie RAM jest ograniczony (384MB na 1.0, wiecej na wyzszych planach)
        if [ "$MEM_USAGE" -lt 60 ]; then
            check_security "Uzycie pamieci" "PASS" "Prawidlowe uzycie pamieci (${MEM_USAGE}% - Uzyte: ${MEM_USED} z ${MEM_TOTAL}, Dostepne: ${MEM_AVAIL})"
        elif [ "$MEM_USAGE" -lt 85 ]; then
            check_security "Uzycie pamieci" "WARN" "Podwyzszone uzycie pamieci (${MEM_USAGE}% - Uzyte: ${MEM_USED} z ${MEM_TOTAL}, Dostepne: ${MEM_AVAIL}). Na Mikrusie RAM jest ograniczony - rozważ optymalizacje uslug"
        else
            check_security "Uzycie pamieci" "FAIL" "Krytyczne uzycie pamieci (${MEM_USAGE}% - Uzyte: ${MEM_USED} z ${MEM_TOTAL}, Dostepne: ${MEM_AVAIL}). Uzywaj polecenia 'amfetamina' w panelu Mikrusa na tymczasowe zwiekszenie zasobow"
        fi
    else
        if [ "$MEM_USAGE" -lt 50 ]; then
            check_security "Uzycie pamieci" "PASS" "Zdrowe uzycie pamieci (${MEM_USAGE}% - Uzyte: ${MEM_USED} z ${MEM_TOTAL}, Dostepne: ${MEM_AVAIL})"
        elif [ "$MEM_USAGE" -lt 80 ]; then
            check_security "Uzycie pamieci" "WARN" "Umiarkowane uzycie pamieci (${MEM_USAGE}% - Uzyte: ${MEM_USED} z ${MEM_TOTAL}, Dostepne: ${MEM_AVAIL})"
        else
            check_security "Uzycie pamieci" "FAIL" "Krytyczne uzycie pamieci (${MEM_USAGE}% - Uzyte: ${MEM_USED} z ${MEM_TOTAL}, Dostepne: ${MEM_AVAIL})"
        fi
    fi
else
    check_security "Uzycie pamieci" "WARN" "Nie udalo sie odczytac uzycia pamieci"
fi

# Sprawdzanie uzycia CPU
CPU_CORES=$(nproc 2>/dev/null || echo "1")
CPU_USAGE=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print int($2)}')
CPU_IDLE=$(top -bn1 2>/dev/null | grep "Cpu(s)" | awk '{print int($8)}')
CPU_LOAD=$(uptime | awk -F'load average:' '{ print $2 }' | awk -F',' '{ print $1 }' | tr -d ' ')

if [ -n "$CPU_USAGE" ]; then
    if [ "$IS_LXC" -eq 1 ]; then
        check_security "Uzycie CPU" "INFO" "CPU: ${CPU_USAGE}% (Aktywne: ${CPU_USAGE}%, Bezczynne: ${CPU_IDLE}%, Rdzenie: ${CPU_CORES}). UWAGA: Load Average ($CPU_LOAD) w LXC odzwierciedla obciazenie calego serwera fizycznego, nie kontenera"
    else
        if [ "$CPU_USAGE" -lt 50 ]; then
            check_security "Uzycie CPU" "PASS" "Prawidlowe uzycie CPU (${CPU_USAGE}% - Aktywne: ${CPU_USAGE}%, Bezczynne: ${CPU_IDLE}%, Load: ${CPU_LOAD}, Rdzenie: ${CPU_CORES})"
        elif [ "$CPU_USAGE" -lt 80 ]; then
            check_security "Uzycie CPU" "WARN" "Umiarkowane uzycie CPU (${CPU_USAGE}% - Aktywne: ${CPU_USAGE}%, Bezczynne: ${CPU_IDLE}%, Load: ${CPU_LOAD}, Rdzenie: ${CPU_CORES})"
        else
            check_security "Uzycie CPU" "FAIL" "Krytyczne uzycie CPU (${CPU_USAGE}% - Aktywne: ${CPU_USAGE}%, Bezczynne: ${CPU_IDLE}%, Load: ${CPU_LOAD}, Rdzenie: ${CPU_CORES})"
        fi
    fi
else
    check_security "Uzycie CPU" "WARN" "Nie udalo sie odczytac uzycia CPU"
fi

# Sprawdzanie konfiguracji sudo
if [ -f /etc/sudoers ]; then
    if grep -q "^Defaults.*logfile" /etc/sudoers 2>/dev/null; then
        check_security "Logowanie sudo" "PASS" "Polecenia sudo sa logowane w celach audytu"
    else
        check_security "Logowanie sudo" "FAIL" "Polecenia sudo nie sa logowane - ogranicza mozliwosci audytu. Dodaj 'Defaults logfile=/var/log/sudo.log' do /etc/sudoers"
    fi
else
    check_security "Logowanie sudo" "INFO" "Plik /etc/sudoers nie znaleziony"
fi

# Sprawdzanie polityki hasel
# Jezeli SSH wymaga kluczy (haslo wylaczone), polityka hasel jest mniej krytyczna
if [ -f "/etc/security/pwquality.conf" ]; then
    if grep -q "minlen.*12" /etc/security/pwquality.conf; then
        check_security "Polityka hasel" "PASS" "Silna polityka hasel jest wymuszona"
    else
        if [ "$SSH_PASSWORD" = "no" ]; then
            check_security "Polityka hasel" "WARN" "Slaba polityka hasel, ale SSH wymaga kluczy - mniejsze ryzyko"
        else
            check_security "Polityka hasel" "FAIL" "Slaba polityka hasel - hasla moga byc zbyt proste. Ustaw minlen=12 w /etc/security/pwquality.conf"
        fi
    fi
else
    if [ "$SSH_PASSWORD" = "no" ]; then
        check_security "Polityka hasel" "WARN" "Brak polityki hasel, ale SSH wymaga kluczy - mniejsze ryzyko. Rozważ instalacje: apt install libpam-pwquality"
    else
        check_security "Polityka hasel" "FAIL" "Brak skonfigurowanej polityki hasel - system akceptuje slabe hasla. Zainstaluj: apt install libpam-pwquality"
    fi
fi

# Sprawdzanie podejrzanych plikow SUID (z timeoutem - w LXC moze trwac dlugo)
COMMON_SUID_PATHS='^/usr/bin/|^/bin/|^/sbin/|^/usr/sbin/|^/usr/lib|^/usr/libexec'
KNOWN_SUID_BINS='ping$|sudo$|mount$|umount$|su$|passwd$|chsh$|newgrp$|gpasswd$|chfn$'

if [ "$IS_LXC" -eq 1 ]; then
    # W kontenerze LXC ograniczamy skanowanie do /usr i /tmp (szybsze, mniej falszywie pozytywnych)
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
    check_security "Pliki SUID" "PASS" "Nie znaleziono podejrzanych plikow SUID"
else
    check_security "Pliki SUID" "WARN" "Znaleziono $SUID_FILES plikow SUID poza standardowymi lokalizacjami - sprawdz czy sa uzasadnione"
fi

# =============================================================================
# Dodatkowe sprawdzenia specyficzne dla Mikrusa
# =============================================================================

print_header "Sprawdzenia specyficzne dla Mikrusa"

# Sprawdzanie dostepnosci SSH
SSH_CHECK_PORT=$(grep "^Port" /etc/ssh/sshd_config 2>/dev/null | head -1 | awk '{print $2}')
SSH_CHECK_PORT=${SSH_CHECK_PORT:-22}
if timeout 3 bash -c "echo > /dev/tcp/localhost/$SSH_CHECK_PORT" 2>/dev/null; then
    check_security "Dostepnosc SSH" "PASS" "SSH odpowiada na porcie $SSH_CHECK_PORT"
else
    check_security "Dostepnosc SSH" "FAIL" "SSH nie odpowiada na porcie $SSH_CHECK_PORT - ryzyko utraty dostepu!"
fi

# Sprawdzanie IPv6
# UWAGA: grep -v "::1" z oryginalu filtrowal tez adresy typu ::178 (::1 jest podciagiem)
# Poprawiono na dokladne dopasowanie ::1/128 (loopback)
IPV6_ADDR=$(ip -6 addr show 2>/dev/null | grep "inet6" | grep -v "fe80" | grep -v " ::1/128" | awk '{print $2}' | head -1)
if [ -n "$IPV6_ADDR" ]; then
    check_security "Adres IPv6" "PASS" "Przydzielony adres IPv6: $IPV6_ADDR (kluczowy dla Mikrusa)"
else
    check_security "Adres IPv6" "WARN" "Nie wykryto globalnego adresu IPv6 - na Mikrusie IPv6 jest podstawa dzialania"
fi

# Sprawdzanie czy uslugi nasluchuja na IPv6
if command -v ss >/dev/null 2>&1; then
    IPV6_SERVICES=$(ss -tuln 2>/dev/null | grep -c "\[::\]")
    IPV4_ONLY=$(ss -tuln 2>/dev/null | grep "LISTEN" | grep -c "127.0.0.1\|0.0.0.0" )
    if [ "$IPV6_SERVICES" -gt 0 ]; then
        check_security "Uslugi IPv6" "PASS" "Znaleziono $IPV6_SERVICES uslug nasluchujacych na IPv6"
    else
        check_security "Uslugi IPv6" "WARN" "Brak uslug nasluchujacych na IPv6 - na Mikrusie uslugi musza sluchac na [::] lub 0.0.0.0 aby byc dostepne"
    fi
fi

# Sprawdzanie Dockera
if command -v docker >/dev/null 2>&1; then
    if docker info >/dev/null 2>&1; then
        DOCKER_CONTAINERS=$(docker ps -q 2>/dev/null | wc -l)
        DOCKER_ALL=$(docker ps -aq 2>/dev/null | wc -l)
        DOCKER_IMAGES=$(docker images -q 2>/dev/null | wc -l)
        check_security "Docker" "INFO" "Docker aktywny - Kontenery: $DOCKER_CONTAINERS uruchomionych / $DOCKER_ALL wszystkich, Obrazy: $DOCKER_IMAGES"

        # Sprawdzanie czy kontenery Docker nasluchuja na odpowiednich portach
        DOCKER_PORTS=$(docker ps --format '{{.Ports}}' 2>/dev/null | grep -oP '\d+\.\d+\.\d+\.\d+:\d+' | sort -u)
        if [ -n "$DOCKER_PORTS" ]; then
            check_security "Porty Docker" "INFO" "Kontenery nasluchuja na: $DOCKER_PORTS"
        fi

        # Sprawdzanie zatrzymanych/uszkodzonych kontenerow
        EXITED_CONTAINERS=$(docker ps -a --filter "status=exited" -q 2>/dev/null | wc -l)
        if [ "$EXITED_CONTAINERS" -gt 0 ]; then
            EXITED_NAMES=$(docker ps -a --filter "status=exited" --format '{{.Names}}' 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
            check_security "Kontenery Docker" "WARN" "Znaleziono $EXITED_CONTAINERS zatrzymanych kontenerow: $EXITED_NAMES. Sprawdz logi: docker logs <nazwa>"
        fi

        # Sprawdzanie nieuzywanych obrazow Docker
        DANGLING=$(docker images -f "dangling=true" -q 2>/dev/null | wc -l)
        if [ "$DANGLING" -gt 0 ]; then
            check_security "Obrazy Docker" "WARN" "Znaleziono $DANGLING nieuzywanych obrazow Docker - zajmuja miejsce. Wyczysic: docker image prune"
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

# Sprawdzanie uprawnien waznych plikow
SENSITIVE_FILES="/etc/shadow /etc/gshadow /etc/passwd /etc/ssh/sshd_config"
PERM_ISSUES=0
for f in $SENSITIVE_FILES; do
    if [ -f "$f" ]; then
        PERMS=$(stat -c %a "$f" 2>/dev/null || stat -f %Lp "$f" 2>/dev/null)
        case "$f" in
            /etc/shadow|/etc/gshadow)
                if [ "$PERMS" != "640" ] && [ "$PERMS" != "600" ] && [ "$PERMS" != "0" ]; then
                    PERM_ISSUES=$((PERM_ISSUES + 1))
                    check_security "Uprawnienia plikow" "FAIL" "$f ma uprawnienia $PERMS (powinno byc 640 lub mniej)"
                fi
                ;;
            /etc/passwd)
                if [ "$PERMS" != "644" ]; then
                    PERM_ISSUES=$((PERM_ISSUES + 1))
                    check_security "Uprawnienia plikow" "WARN" "$f ma uprawnienia $PERMS (powinno byc 644)"
                fi
                ;;
        esac
    fi
done
if [ "$PERM_ISSUES" -eq 0 ]; then
    check_security "Uprawnienia plikow" "PASS" "Uprawnienia waznych plikow systemowych sa prawidlowe"
fi

# Sprawdzanie czy sa uzytkownicy z pustym haslem
# UWAGA: konta z "!" lub "!!" to konta CELOWO ZABLOKOWANE (np. sshd, messagebus) - to jest OK
# Szukamy tylko kont z naprawde pustym polem hasla (brak jakiejkolwiek wartosci)
EMPTY_PASS=$(awk -F: '($2 == "") {print $1}' /etc/shadow 2>/dev/null | grep -v "^$" | wc -l)
if [ "$EMPTY_PASS" -gt 0 ]; then
    EMPTY_USERS=$(awk -F: '($2 == "") {print $1}' /etc/shadow 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
    check_security "Puste hasla" "FAIL" "Znaleziono $EMPTY_PASS kont z pustym haslem (brak zabezpieczenia!): $EMPTY_USERS"
else
    check_security "Puste hasla" "PASS" "Brak kont z pustymi haslami"
fi

# Sprawdzanie kont z zablokowanym logowaniem (informacyjnie)
LOCKED_PASS=$(awk -F: '($2 == "!" || $2 == "!!" || $2 == "*") {print $1}' /etc/shadow 2>/dev/null | grep -v "^$" | wc -l)
if [ "$LOCKED_PASS" -gt 0 ]; then
    check_security "Zablokowane konta" "INFO" "$LOCKED_PASS kont z zablokowanym logowaniem haslem (to jest poprawne zabezpieczenie)"
fi

# Podsumowanie informacji o systemie w raporcie
echo "================================" >> "$REPORT_FILE"
echo "Podsumowanie systemu:" >> "$REPORT_FILE"
echo "Nazwa hosta: $(hostname)" >> "$REPORT_FILE"
echo "Jadro: $(uname -r)" >> "$REPORT_FILE"
echo "System: $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d'"' -f2)" >> "$REPORT_FILE"
echo "Rdzenie CPU: $(nproc 2>/dev/null)" >> "$REPORT_FILE"
echo "Pamiec RAM: $(free -h 2>/dev/null | awk '/^Mem:/ {print $2}')" >> "$REPORT_FILE"
echo "Przestrzen dyskowa: $(df -h / | awk 'NR==2 {print $2}')" >> "$REPORT_FILE"
if [ "$IS_LXC" -eq 1 ]; then
    echo "Srodowisko: Kontener LXC (Mikr.us/Proxmox)" >> "$REPORT_FILE"
fi
echo "================================" >> "$REPORT_FILE"

echo -e "\n${GREEN}${BOLD}Audyt zakonczony.${NC} Pelny raport zapisany do ${BOLD}$REPORT_FILE${NC}"
echo -e "Przejrzyj raport i wdroż zalecane poprawki."
if [ "$IS_LXC" -eq 1 ]; then
    echo -e "\n${YELLOW}Wskazowki dla Mikrusa:${NC}"
    echo -e "  - Dokumentacja: ${BLUE}https://wiki.mikr.us/${NC}"
    echo -e "  - Panel zarzadzania: ${BLUE}https://mikr.us/panel/${NC}"
    echo -e "  - Porady dot. SSH: uzyj kluczy SSH zamiast hasel"
    echo -e "  - IPv6 jest podstawa - upewnij sie ze uslugi sluchaja na [::]:port"
fi

# Zakonczenie raportu
echo "================================" >> "$REPORT_FILE"
echo "Koniec raportu audytu VPS" >> "$REPORT_FILE"
echo "Przejrzyj wszystkie nieudane testy i wdroż zalecane poprawki." >> "$REPORT_FILE"
if [ "$IS_LXC" -eq 1 ]; then
    echo "" >> "$REPORT_FILE"
    echo "Wskazowki dla Mikrusa:" >> "$REPORT_FILE"
    echo "- Dokumentacja: https://wiki.mikr.us/" >> "$REPORT_FILE"
    echo "- Panel: https://mikr.us/panel/" >> "$REPORT_FILE"
    echo "- Uzywaj kluczy SSH zamiast hasel" >> "$REPORT_FILE"
    echo "- Uslugi musza sluchac na IPv6 ([::]:port lub 0.0.0.0:port)" >> "$REPORT_FILE"
    echo "- Load Average w kontenerze LXC pokazuje obciazenie hosta, nie kontenera" >> "$REPORT_FILE"
fi
