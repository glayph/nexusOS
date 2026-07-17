#!/bin/bash
# ============================================================
#  TajaOS — Custom Startup Script
#  Initializes TajaOS system modules on boot
# ============================================================

# Initialize TajaOS core config
if [[ -x /usr/local/bin/tajados ]]; then
  tajados init 2>/dev/null || true
fi

# Install TajaOS built-in hooks
if [[ -x /usr/local/bin/tajahook ]]; then
  tajahook install-builtin 2>/dev/null || true
fi

# Load saved session
if [[ -f /var/lib/tajados/runtime/active_services ]]; then
  while read -r svc; do
    systemctl start "$svc" 2>/dev/null || true
  done < /var/lib/tajados/runtime/active_services
fi

# Check persistence
if [[ -f /persist.img ]]; then
  /usr/local/bin/tajados-persist mount 2>/dev/null || true
fi

echo "[TajaOS] System initialized"
echo "[TajaOS] Type 'os' for help, 'os setup' for configuration"