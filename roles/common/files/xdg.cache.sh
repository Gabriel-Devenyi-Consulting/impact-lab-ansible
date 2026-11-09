# Desktop sessions get the local cache redirect from
# /etc/environment.d/60-xdg-cache.conf via the systemd user manager; ssh and
# console logins do not go through it, so pick up the same file here. Only when
# the directory exists and is ours (xdg-cache-dir creates it at login), and
# never over a value the user or the session already set.
if [ -z "${XDG_CACHE_HOME:-}" ] && [ -n "${USER:-}" ] && [ "$USER" != "root" ] \
    && [ -O "/var/tmp/xdg-cache/$USER" ] && [ -r /etc/environment.d/60-xdg-cache.conf ]; then
    set -a
    . /etc/environment.d/60-xdg-cache.conf
    set +a
fi
