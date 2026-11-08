# ~/.bashrc: ejecutado por bash(1) para shells no de login.

# Si no es interactivo, salir
[[ $- != *i* ]] && return

# Alias comunes
alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias grep='grep --color=auto'

# Cargar perfil de Solaris si existe
[[ -f /etc/profile.d/10-titan.sh ]] && . /etc/profile.d/10-titan.sh

# Mostrar el logo de Solaris al abrir la consola interactiva
if command -v fastfetch >/dev/null 2>&1; then
    if [[ -r /usr/share/fastfetch/presets/solaris.jsonc ]]; then
        fastfetch --config /usr/share/fastfetch/presets/solaris.jsonc
    else
        fastfetch
    fi
elif [[ -r /usr/share/titan/solaris.logo ]]; then
    cat /usr/share/titan/solaris.logo
fi
