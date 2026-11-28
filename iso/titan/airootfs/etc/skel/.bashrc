# ~/.bashrc: ejecutado por bash(1) para shells no de login.

# Si no es interactivo, salir
[[ $- != *i* ]] && return

# Alias comunes
alias ls='ls --color=auto'
alias ll='ls -lah --color=auto'
alias grep='grep --color=auto'

# Cargar perfil de Inti OS si existe
[[ -f /etc/profile.d/10-titan.sh ]] && . /etc/profile.d/10-titan.sh

# Banner de bienvenida al abrir la consola interactiva
echo "titan shell 1.8.0"
