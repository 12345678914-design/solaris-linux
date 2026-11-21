#!/bin/sh
# Inti OS - Conmutacion inteligente Ethernet vs Wi-Fi
# Desactiva Wi-Fi al conectar el cable Ethernet y lo reactiva al desconectarlo.

IFACE="$1"
ACTION="$2"

case "$IFACE" in
    eth*|en*|eno*|enp*)
        if [ "$ACTION" = "up" ]; then
            nmcli radio wifi off 2>/dev/null || rfkill block wifi 2>/dev/null || true
        elif [ "$ACTION" = "down" ]; then
            nmcli radio wifi on 2>/dev/null || rfkill unblock wifi 2>/dev/null || true
        fi
        ;;
esac

