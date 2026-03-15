#!/bin/bash
# Konfiguracja klucza SSH dla Mikr.us
# Generuje klucz Ed25519 i wyświetla go do skopiowania

KLUCZ="$HOME/.ssh/id_ed25519"

# Utwórz katalog .ssh jeśli nie istnieje
mkdir -p ~/.ssh && chmod 700 ~/.ssh

# Sprawdź czy klucz już istnieje
if [ -f "$KLUCZ.pub" ]; then
    echo "Klucz SSH już istnieje!"
    echo ""
    echo "Twój klucz publiczny (skopiuj go):"
    echo "==================================="
    cat "$KLUCZ.pub"
    echo ""
    echo "Aby skopiować do schowka:"
    if command -v pbcopy &>/dev/null; then
        echo "  cat $KLUCZ.pub | pbcopy"
    elif command -v xclip &>/dev/null; then
        echo "  cat $KLUCZ.pub | xclip -selection clipboard"
    fi
    exit 0
fi

# Generuj nowy klucz Ed25519 (szybszy i bezpieczniejszy niż RSA)
echo "Generowanie klucza SSH..."
echo ""
ssh-keygen -t ed25519 -f "$KLUCZ" -N "" -C "mikrus"

echo ""
echo "Klucz wygenerowany!"
echo ""
echo "Twój klucz publiczny (skopiuj go i wklej w panelu Mikr.us):"
echo "============================================================"
cat "$KLUCZ.pub"
echo ""

# Automatyczne kopiowanie do schowka (macOS)
if command -v pbcopy &>/dev/null; then
    cat "$KLUCZ.pub" | pbcopy
    echo ">> Klucz skopiowany do schowka!"
    echo ""
fi

echo "Następne kroki:"
echo "1. Wklej klucz w panelu Mikr.us (Zarządzanie VPSem -> Klucz SSH)"
echo "2. Połącz się: ssh root@sXX.mikr.us -p 10XXX -i $KLUCZ"
