# --- WSL → Windows ssh-agent bridge (YubiKey via npiperelay) ---
# Deployed only on WSL (see .chezmoiignore). Requires:
#   • Windows ssh-agent service running (Get-Service ssh-agent → StartupType Automatic)
#   • YubiKey plugged in (holds the sk-ssh-ed25519 credential)
#   • npiperelay.exe on Windows (path below; windows/setup-windows.ps1 installs it)
# The bridge exposes a Unix socket at $SSH_AUTH_SOCK backed by the named pipe
# \\.\pipe\openssh-ssh-agent; ssh(1) then transparently talks to the Win agent.

set -l npiperelay /mnt/c/Tools/npiperelay.exe

# Only take over SSH_AUTH_SOCK when the bridge can actually be served —
# otherwise leave any native agent alone.
if test -x $npiperelay
    set -gx SSH_AUTH_SOCK $HOME/.ssh/agent.sock
    # Spawn only if nothing is currently listening on the socket
    if not ss -xlnp 2>/dev/null | string match -q "*$SSH_AUTH_SOCK*"
        rm -f $SSH_AUTH_SOCK
        setsid -f socat UNIX-LISTEN:$SSH_AUTH_SOCK,fork \
            EXEC:"$npiperelay -ei -s //./pipe/openssh-ssh-agent",nofork \
            > /dev/null 2>&1 &
        disown 2>/dev/null; or true
    end
end
