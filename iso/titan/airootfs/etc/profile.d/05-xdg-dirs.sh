#!/bin/sh
export XDG_DATA_DIRS="/var/lib/flatpak/exports/share:${HOME}/.local/share/flatpak/exports/share:${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
