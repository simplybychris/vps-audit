#!/bin/bash
# ============================================
# Zabezpieczenie VPS — AI Ninjas
# Działa na: Ubuntu 22.04 / 24.04
# Uruchom jako: root (przy pierwszym logowaniu)
# ============================================
#
# Co robi ten skrypt:
#   1. Aktualizuje system
#   2. Zmienia hasło root na losowe (logowanie tylko kluczem SSH)
#   3. Tworzy Twoje konto administracyjne
#   4. Kopiuje klucze SSH na nowe konto
#   5. Blokuje logowanie jako root i logowanie hasłem
#   6. Instaluje fail2ban (banuje IP po nieudanych próbach SSH)
#   7. Instaluje firewall UFW (blokuje niepotrzebne porty)
#   8. Włącza automatyczne aktualizacje bezpieczeństwa
#
# Skrypt sprawdza co już jest zrobione i pomija ukończone kroki.
#
# ============================================

set -e  # Przerwij przy pierwszym błędzie

# Sprawdzenie: czy uruchomiono jako root?
if [ "$(id -u)" -ne 0 ]; then
    echo "Ten skrypt musi być uruchomiony jako root."
    echo "Użyj: sudo bash secure-vps.sh"
    exit 1
fi

# Sprawdzenie: czy klucz SSH jest na serwerze?
if [ ! -f /root/.ssh/authorized_keys ] || [ ! -s /root/.ssh/authorized_keys ]; then
    echo "BŁĄD: Brak klucza SSH w /root/.ssh/authorized_keys"
    echo ""
    echo "Najpierw dodaj klucz SSH w panelu Mikr.us:"
    echo "  Zarządzanie VPSem -> Klucz SSH"
    echo ""
    echo "Dopiero potem uruchom ten skrypt."
    exit 1
fi

# Pytanie o nazwę użytkownika
echo ""
echo "============================================"
echo "  Zabezpieczanie VPS"
echo "============================================"
echo ""
read -p "Podaj nazwę użytkownika (np. jan, beata, user123): " ADMIN_USER

# Walidacja nazwy
if [ -z "$ADMIN_USER" ]; then
    echo "BŁĄD: Nazwa użytkownika nie może być pusta."
    exit 1
fi
if [ "$ADMIN_USER" = "root" ]; then
    echo "BŁĄD: Nie możesz użyć 'root' — właśnie od niego uciekamy!"
    exit 1
fi

echo ""
echo "  Konto admin: $ADMIN_USER"
echo ""

# ── 1. Aktualizacja systemu ──────────────────────────────────────────────────
# Instaluje najnowsze poprawki bezpieczeństwa i aktualizuje pakiety.
echo "=== [1/7] Aktualizacja systemu ==="
apt update -qq && apt upgrade -y -qq
echo "System zaktualizowany."

# ── 2. Zmiana hasła root ─────────────────────────────────────────────────────
# Generuje losowe hasło i ustawia je dla root.
# Celowo nie zapisujemy tego hasła — od teraz logowanie jest tylko kluczem SSH.
# Gdybyś potrzebował dostępu awaryjnego, mikr.us ma panel WebSSH.
echo "=== [2/7] Zmiana hasła root ==="
NEW_PASS=$(openssl rand -base64 24)
echo "root:${NEW_PASS}" | chpasswd
echo "Hasło root zmienione na losowe (nie jest nigdzie zapisane)."

# ── 3. Tworzenie użytkownika ─────────────────────────────────────────────────
# Dlaczego nie root? Root to domyślne konto na każdym Linuksie.
# Boty w internecie non-stop próbują się logować jako root.
# Własne konto o nieoczywistej nazwie to dodatkowa bariera.
echo "=== [3/7] Tworzenie użytkownika ==="

if id "$ADMIN_USER" &>/dev/null; then
    echo "  $ADMIN_USER już istnieje — pomijam."
else
    adduser --disabled-password --gecos "" $ADMIN_USER
    echo "  Utworzono konto: $ADMIN_USER"
fi
usermod -aG sudo $ADMIN_USER
echo "$ADMIN_USER ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/$ADMIN_USER
chmod 440 /etc/sudoers.d/$ADMIN_USER
echo "Użytkownik $ADMIN_USER gotowy (sudo bez hasła)."

# ── 4. Kopiowanie kluczy SSH ─────────────────────────────────────────────────
# Kopiujemy klucz publiczny z root na oba nowe konta.
# Dzięki temu możesz się logować na nowe konta tym samym kluczem.
echo "=== [4/7] Kopiowanie kluczy SSH ==="
mkdir -p /home/$ADMIN_USER/.ssh
cp /root/.ssh/authorized_keys /home/$ADMIN_USER/.ssh/
chown -R $ADMIN_USER:$ADMIN_USER /home/$ADMIN_USER/.ssh
chmod 700 /home/$ADMIN_USER/.ssh
chmod 600 /home/$ADMIN_USER/.ssh/authorized_keys
echo "Klucze SSH skopiowane na konto $ADMIN_USER."

# ── 5. SSH Hardening ─────────────────────────────────────────────────────────
# Tworzymy plik konfiguracyjny w /etc/ssh/sshd_config.d/ (drop-in).
# Nie edytujemy głównego pliku — łatwiej zarządzać, łatwiej wycofać.
#
# Co robimy:
#   PermitRootLogin no          — root nie może się logować
#   PasswordAuthentication no   — hasła wyłączone, tylko klucze SSH
#   KbdInteractiveAuthentication no — zamykamy "tylne drzwi" dla haseł
#   MaxAuthTries 3              — max 3 próby na połączenie
#   LoginGraceTime 20           — 20 sekund na uwierzytelnienie
#   AllowUsers                  — tylko wymienieni użytkownicy mogą się logować
echo "=== [5/7] SSH Hardening ==="
cat > /etc/ssh/sshd_config.d/hardening.conf << SSHEOF
PermitRootLogin no
PasswordAuthentication no
KbdInteractiveAuthentication no
PubkeyAuthentication yes
MaxAuthTries 3
LoginGraceTime 20
X11Forwarding no
AllowUsers $ADMIN_USER
SSHEOF

# Walidacja — jeśli jest błąd w configu, NIE restartujemy SSH
sshd -t || { echo "BŁĄD w konfiguracji SSH! Przerywam."; rm /etc/ssh/sshd_config.d/hardening.conf; exit 1; }
systemctl restart ssh
echo "SSH: root zablokowany, hasła wyłączone, tylko klucze."

# ── 6. fail2ban ──────────────────────────────────────────────────────────────
# Monitoruje logi SSH i banuje IP po zbyt wielu nieudanych próbach.
# 3 nieudane próby w ciągu godziny = ban na 24 godziny.
# backend=systemd — Ubuntu 24.04 używa journald, nie klasycznych logów.
echo "=== [6/7] fail2ban ==="
if command -v fail2ban-client &>/dev/null; then
    echo "  fail2ban już zainstalowany — aktualizuję konfigurację."
else
    apt install -y fail2ban -qq > /dev/null 2>&1
fi

cat > /etc/fail2ban/jail.local << "F2BEOF"
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5
backend = systemd

[sshd]
enabled = true
port = 22
filter = sshd
maxretry = 3
bantime = 24h
findtime = 1h
F2BEOF

systemctl enable fail2ban > /dev/null 2>&1
systemctl restart fail2ban
echo "fail2ban: ban 24h po 3 nieudanych próbach SSH."

# ── 7. Firewall (UFW) + automatyczne aktualizacje ───────────────────────────
# UFW blokuje cały ruch przychodzący oprócz SSH (22), HTTP (80), HTTPS (443).
# Na mikr.us UFW chroni przede wszystkim stronę IPv6 — tam wszystkie porty
# są bezpośrednio dostępne z internetu (IPv4 jest za NAT).
#
# unattended-upgrades automatycznie instaluje poprawki bezpieczeństwa Ubuntu.
echo "=== [7/7] Firewall + auto-aktualizacje ==="
if command -v ufw &>/dev/null; then
    echo "  UFW już zainstalowany."
else
    apt install -y ufw -qq > /dev/null 2>&1
fi
apt install -y unattended-upgrades -qq > /dev/null 2>&1

ufw default deny incoming > /dev/null 2>&1
ufw default allow outgoing > /dev/null 2>&1
ufw allow 22/tcp > /dev/null 2>&1
ufw allow 80/tcp > /dev/null 2>&1
ufw allow 443/tcp > /dev/null 2>&1
ufw limit 22/tcp > /dev/null 2>&1
ufw --force enable > /dev/null 2>&1

cat > /etc/apt/apt.conf.d/20auto-upgrades << "AUTOEOF"
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
AUTOEOF
dpkg-reconfigure -f noninteractive unattended-upgrades 2>/dev/null

echo "Firewall: deny all, allow SSH/HTTP/HTTPS + rate limit."
echo "Auto-aktualizacje: włączone."

# ── GOTOWE ───────────────────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  SERWER ZABEZPIECZONY"
echo "============================================"
echo ""
echo "  Konto admin:    $ADMIN_USER"
echo "  Root login:     ZABLOKOWANY"
echo "  Hasła:          WYŁĄCZONE (tylko klucz SSH)"
echo "  Firewall:       WŁĄCZONY (SSH/HTTP/HTTPS)"
echo "  fail2ban:       AKTYWNY (ban 24h po 3 próbach)"
echo "  Auto-update:    WŁĄCZONY"
echo ""
echo "  Zaloguj się teraz na swoje konto:"
echo "    ssh -p PORT $ADMIN_USER@SERWER"
echo "============================================"
