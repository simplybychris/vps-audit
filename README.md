# Mikrus Audit - Skrypt audytu bezpieczeństwa VPS

> **Fork projektu [vps-audit](https://github.com/vernu/vps-audit)** autorstwa [vernu](https://github.com/vernu) - świetnego narzędzia do audytu bezpieczeństwa VPS.
>
> Ten fork dodaje pełne tłumaczenie na język polski, adaptację do środowiska **[Mikr.us](https://mikr.us)** (kontenery LXC/Proxmox) oraz poprawki błędów z oryginalnego skryptu.
> Oryginalny skrypt (angielski, uniwersalny) jest nadal dostępny jako `vps-audit.sh`.

![Fragment wyników audytu na serwerze Mikr.us (sekcja bezpieczeństwa)](./screenshot.jpg)

*Powyżej: fragment audytu - sekcja sprawdzeń bezpieczeństwa. Pełna lista sprawdzeń poniżej.*

## Co sprawdza

### Bezpieczeństwo

- **Konfiguracja SSH**
  - Status logowania root
  - Uwierzytelnianie hasłem
  - Niestandardowy port SSH
- **Zapora sieciowa** (UFW, firewalld, iptables, nftables)
- **Ochrona przed włamaniami** (Fail2ban, CrowdSec) - także w kontenerach Docker
- **Nieudane próby logowania** - wykrywanie ataków brute force
- **Aktualizacje systemu** - sprawdzanie dostępnych poprawek
- **Uruchomione usługi** - analiza powierzchni ataku
- **Otwarte porty** - wykrywanie nasłuchujących usług
- **Logowanie sudo** - sprawdzanie audytu poleceń
- **Polityka haseł** - weryfikacja wymagań złożoności
- **Pliki SUID** - wykrywanie podejrzanych plików
- **Automatyczne aktualizacje** (unattended-upgrades)
- **Uprawnienia plików systemowych** (/etc/shadow, /etc/passwd itp.)
- **Konta z pustymi hasłami**

### Wydajność

- Użycie dysku
- Użycie pamięci RAM
- Użycie CPU
- Otwarte połączenia sieciowe

### Specyficzne dla Mikr.us

- **Wykrywanie kontenera LXC** - automatyczne dostosowanie wyników
- **Sprawdzanie IPv6** - kluczowe dla Mikrusa (IPv6-first)
- **Weryfikacja nasłuchiwania na IPv6** - czy usługi słuchają na `[::]`
- **Kontekst portów Mikrusa** - informacja o schemacie 10000+ID / 20000+ID / 30000+ID
- **Load Average** - ostrzeżenie że w LXC pokazuje obciążenie hosta, nie kontenera
- **Status Dockera** - kontenery, obrazy, nieużywane zasoby
- **Dostosowane progi** - inne limity dla kontenerów LXC (RAM, liczba usług)
- **Linki do dokumentacji Mikrusa** w wynikach

## Wymagania

- System Linux (Ubuntu/Debian zalecany)
- Dostęp root lub uprawnienia sudo
- Podstawowe pakiety (zwykle preinstalowane): `ss`, `grep`, `awk`, `curl`

## Instalacja

### Szybka instalacja (jednolinijkowa)

```bash
curl -sL https://raw.githubusercontent.com/simplybychris/vps-audit/main/mikrus-audit.sh | sudo bash
```

### Standardowa instalacja

1. Pobierz skrypt:

```bash
wget https://raw.githubusercontent.com/simplybychris/vps-audit/main/mikrus-audit.sh
# lub
curl -O https://raw.githubusercontent.com/simplybychris/vps-audit/main/mikrus-audit.sh
```

2. Nadaj uprawnienia do uruchomienia:

```bash
chmod +x mikrus-audit.sh
```

## Użycie

Uruchom skrypt z uprawnieniami root:

```bash
sudo ./mikrus-audit.sh
```

Skrypt:

1. Wykona wszystkie sprawdzenia bezpieczeństwa
2. Wyświetli wyniki na bieżąco z kolorowaniem:
   - `[OK]` - Test przeszedł pomyślnie
   - `[UWAGA]` - Wykryto potencjalne problemy
   - `[BŁĄD]` - Znaleziono krytyczne problemy
   - `[INFO]` - Informacja kontekstowa (specyficzna dla Mikrusa)
3. Wygeneruje raport: `mikrus-audit-raport-[ZNACZNIK_CZASU].txt`

## Format wyników

Skrypt generuje dwa rodzaje wyników:

1. Wyniki na żywo w konsoli z kolorowaniem:

```
[OK] Logowanie root SSH - Logowanie jako root jest prawidłowo wyłączone
[UWAGA] Port SSH - Użyto domyślnego portu 22 - rozważ zmianę
[BŁĄD] Zapora sieciowa - Zapora UFW nie jest aktywna - system narażony
[INFO] Porty Mikrus - Z zewnątrz dostępne są tylko porty przekierowane
```

2. Plik raportu zawierający:
   - Wyniki wszystkich testów
   - Konkretne zalecenia dla nieudanych testów
   - Statystyki zasobów systemowych
   - Znacznik czasu audytu

## Progi

### Zasoby systemowe

| Zasób | OK | UWAGA | BŁĄD |
|-------|--------|---------|-------|
| Dysk | < 50% | 50-80% | > 80% |
| Pamięć (VPS) | < 50% | 50-80% | > 80% |
| Pamięć (LXC/Mikrus) | < 60% | 60-85% | > 85% |
| CPU | < 50% | 50-80% | > 80% |

### Bezpieczeństwo

| Test | OK | UWAGA | BŁĄD |
|------|--------|---------|-------|
| Nieudane logowania | < 10 | 10-50 | > 50 |
| Uruchomione usługi (VPS) | < 20 | 20-40 | > 40 |
| Uruchomione usługi (LXC) | < 25 | 25-40 | > 40 |
| Otwarte porty (VPS) | < 10 | 10-20 | > 20 |
| Otwarte porty (LXC) | < 15 | 15-25 | > 25 |

## Różnice względem oryginalnego vps-audit

| Cecha | vps-audit | mikrus-audit |
|-------|-----------|--------------|
| Język | angielski | polski |
| Środowisko | standardowy VPS | VPS + LXC/Proxmox (Mikr.us) |
| Statusy | PASS/WARN/FAIL | OK/UWAGA/BŁĄD + INFO |
| IPv6 | brak | sprawdzanie adresu i usług |
| Docker | częściowo | pełne sprawdzenie + czyszczenie |
| Progi LXC | brak | dostosowane do kontenerów |
| Load Average | standardowy | z ostrzeżeniem o LXC |
| Uprawnienia plików | brak | sprawdzanie /etc/shadow itp. |
| Puste hasła | brak | wykrywanie kont bez haseł |
| Porty Mikrus | brak | kontekst schematu portów |
| Parsowanie IPv6 | błąd w awk -F':' | poprawione (sed) |
| SUID timeout | brak (może wisieć) | timeout 15/30s |
| Test SSH | brak | test dostępności portu |
| Kontenery Docker | tylko fail2ban/crowdsec | pełny status + awarie |
| Polityka haseł | zawsze FAIL bez pwquality | kontekstowa (uwzględnia klucze SSH) |
| Wskazówki | brak | linki do dokumentacji Mikrusa |

## Dobre praktyki

1. Uruchamiaj audyt regularnie (np. co tydzień)
2. Przeglądaj wygenerowany raport dokładnie
3. Napraw natychmiast wszystkie testy ze statusem `[BŁĄD]`
4. Zbadaj testy ze statusem `[UWAGA]` podczas konserwacji
5. Na Mikrusie zwracaj szczególną uwagę na:
   - Konfigurację SSH (klucze zamiast haseł!)
   - Nasłuchiwanie usług na IPv6
   - Użycie pamięci RAM (ograniczona w kontenerach)

## Ograniczenia

- Zaprojektowany głównie dla systemów Debian/Ubuntu
- Wymaga dostępu root/sudo
- Niektóre testy mogą wymagać dostosowania do specyficznego środowiska
- Nie zastępuje profesjonalnego audytu bezpieczeństwa
- W kontenerach LXC niektóre polecenia systemowe mogą być ograniczone

## Podziękowania i atrybucja

Ten projekt jest forkiem **[vps-audit](https://github.com/vernu/vps-audit)** autorstwa **[vernu](https://github.com/vernu)**.

Oryginalny skrypt to świetne, proste narzędzie do audytu bezpieczeństwa VPS.
Ten fork rozszerza go o polskie tłumaczenie i adaptację do środowiska Mikr.us,
zachowując oryginalny skrypt (`vps-audit.sh`) w niezmienionej formie.

**Poprawki błędów w tym forku** (względem oryginału):
- Parsowanie portów IPv6 (`awk -F':'` łamał adresy IPv6 typu `[::]:port`)
- Polecenie journalctl było przekazywane jako string do grep zamiast wykonywane
- Brak timeoutu na skanowaniu SUID (`find /` mógł wisieć minutami w LXC)

## Licencja

Projekt na licencji MIT - szczegóły w pliku LICENSE.

## Bezpieczeństwo

Ten skrypt pomaga zidentyfikować typowe problemy bezpieczeństwa, ale nie powinien być jedynym środkiem ochrony. Zawsze:

- Aktualizuj system regularnie (`apt update && apt upgrade`)
- Monitoruj logi systemowe
- Stosuj dobre praktyki bezpieczeństwa
- Używaj kluczy SSH zamiast haseł
- Na Mikrusie korzystaj z dokumentacji: https://wiki.mikr.us/

## Skrypty pomocnicze

W katalogu `scripts/` znajdziesz gotowe skrypty do konfiguracji serwera:

### ssh_setup.sh — generowanie klucza SSH

Generuje klucz Ed25519, wyświetla go i kopiuje do schowka. Uruchom na swoim komputerze (nie na serwerze):

```bash
curl -sL https://raw.githubusercontent.com/simplybychris/vps-audit/main/scripts/ssh_setup.sh | bash
```

Po uruchomieniu wklej klucz w panelu Mikr.us: **Zarządzanie VPSem -> Klucz SSH**.

### secure-vps.sh — zabezpieczenie serwera

Pełny hardening VPS w jednym skrypcie. Pobierz i uruchom na serwerze jako root:

```bash
curl -sL https://raw.githubusercontent.com/simplybychris/vps-audit/main/scripts/secure-vps.sh -o secure-vps.sh && bash secure-vps.sh
```

Co robi:
- Tworzy Twoje konto (pyta o nazwę) i wyłącza roota
- Kopiuje klucze SSH na nowe konto
- Instaluje fail2ban (ban 24h po 3 nieudanych próbach)
- Włącza firewall UFW (SSH/HTTP/HTTPS)
- Włącza automatyczne aktualizacje bezpieczeństwa

### Zalecana kolejność

1. `ssh_setup.sh` (na Macu/PC) → klucz w schowku
2. Panel Mikr.us → wklej klucz SSH
3. Poczekaj 3-4 minuty
4. `mikrus-audit.sh` (na serwerze) → zobacz co jest do naprawy
5. `secure-vps.sh` (na serwerze) → napraw automatycznie
6. `mikrus-audit.sh` ponownie → sprawdź że wszystko zielone

## Przydatne linki (Mikr.us)

- Panel Mikrusa: https://mikr.us/panel/
- Wiki Mikrusa: https://wiki.mikr.us/
- Discord: https://mikr.us/discord
- Facebook: https://mikr.us/facebook
