#!/bin/bash
# ============================================================
#  NEXUS OS — Custom Startup Script
#  Boot হওয়ার পর, Nexus agent চালু হওয়ার আগে run হবে
#  এখানে তোমার custom commands লেখো
# ============================================================

# Example: network interface চেক করো
# ip link set eth0 up 2>/dev/null || true

# Example: কোনো service চালু করো
# systemctl start ssh 2>/dev/null || true

# Example: environment variable set করো
# export MY_PROJECT="/opt/myproject"

echo "[Nexus] Custom startup complete."
