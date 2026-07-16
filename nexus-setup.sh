#!/bin/bash

C=$(printf '\033[96m'); G=$(printf '\033[92m'); Y=$(printf '\033[93m')
R=$(printf '\033[91m'); B=$(printf '\033[1m'); D=$(printf '\033[2m')
N=$(printf '\033[0m')
A_ERR=0; A_GUI=0; A_DM=""; A_USER=""

PRE_INSTALLED="alsa-utils pulseaudio wireless-tools wpasupplicant iw bluez bluez-tools"

menu() {
  whiptail --title "Nexus OS Setup" --menu "$1" 20 60 "$2" "${@:3}" 3>&1 1>&2 2>&3
}

yesno() {
  whiptail --title "$1" --yesno "$2" 10 60
}

msg() {
  whiptail --title "$1" --msgbox "$2" 10 60
}

input() {
  whiptail --title "$1" --inputbox "$2" 10 60 3>&1 1>&2 2>&3
}

password_input() {
  whiptail --title "$1" --passwordbox "$2" 10 60 3>&1 1>&2 2>&3
}

run() {
  echo -e "${C}▸${N} $*"
  "$@" 2>&1 | while IFS= read -r line; do echo "  $line"; done
  return ${PIPESTATUS[0]}
}

apt_install() {
  run apt-get install -y --no-install-recommends "$@" 2>&1 | tail -5
  return ${PIPESTATUS[0]}
}

apt_remove() {
  run apt-get purge -y "$@" 2>&1 | tail -5
  run apt-get autoremove -y --purge 2>&1 | tail -3
}

is_installed() {
  dpkg -s "$1" 2>/dev/null | grep -q "Status: install ok"
}

drivers_menu() {
  local choices
  choices=$(whiptail --title "Drivers & Hardware" --checklist "Toggle drivers (already installed=ON, uncheck to remove):" 18 64 6 \
    "1" "Audio (ALSA + PulseAudio)" ON \
    "2" "GPU (mesa + vulkan)" OFF \
    "3" "Wi-Fi firmware (iwlwifi, realtek, brcm)" OFF \
    "4" "Firmware (misc-nonfree, for real GPUs)" OFF \
    "5" "Remove ALL pre-installed drivers" OFF \
    "6" "Re-install kernel (restore modules)" ON \
    3>&1 1>&2 2>&3)

  [[ -z "$choices" ]] && return

  if [[ "$choices" == *"5"* ]]; then
    if yesno "Remove Drivers" "Remove all pre-installed drivers (audio, wifi, bluetooth)?"; then
      msg "Removing" "Removing pre-installed drivers..."
      apt_remove $PRE_INSTALLED
      pm-cmd cache --purge 2>/dev/null || true
      msg "Done" "Pre-installed drivers removed."
    fi
    return
  fi

  if [[ "$choices" == *"6"* ]]; then
    msg "Restoring" "Restoring kernel modules..."
    run apt-get install --reinstall -y linux-image-virtual 2>&1 | tail -3
    msg "Done" "Kernel modules restored."
  fi

  local install=""
  [[ "$choices" == *"1"* ]] && install+=" alsa-utils pulseaudio"
  [[ "$choices" == *"2"* ]] && install+=" mesa-utils mesa-vulkan-drivers xserver-xorg-video-all libgl1-mesa-dri"
  [[ "$choices" == *"3"* ]] && install+=" firmware-brcm80211 firmware-iwlwifi firmware-realtek"
  [[ "$choices" == *"4"* ]] && install+=" firmware-misc-nonfree"

  if [[ -n "$install" ]]; then
    msg "Installing" "Installing selected drivers..."
    apt_install $install
    msg "Done" "Additional drivers installed."
  fi

}

remove_drivers() {
  whiptail --title "Remove Drivers" --checklist "Select what to remove:" 16 64 5 \
    "1" "Audio (alsa-utils, pulseaudio)" ON \
    "2" "Wi-Fi (wireless-tools, wpasupplicant, iw)" OFF \
    "3" "Bluetooth (bluez, bluez-tools)" OFF \
    "4" "GPU drivers & firmware" OFF \
    "5" "ALL pre-installed drivers" OFF \
    3>&1 1>&2 2>&3

  [[ -z "$choices" ]] && return

  local rm_pkgs=""
  [[ "$choices" == *"1"* ]] && rm_pkgs+=" alsa-utils pulseaudio"
  [[ "$choices" == *"2"* ]] && rm_pkgs+=" wireless-tools wpasupplicant iw"
  [[ "$choices" == *"3"* ]] && rm_pkgs+=" bluez bluez-tools"
  [[ "$choices" == *"4"* ]] && rm_pkgs+=" mesa-utils mesa-vulkan-drivers xserver-xorg-video-all libgl1-mesa-dri firmware-misc-nonfree"
  [[ "$choices" == *"5"* ]] && rm_pkgs="$PRE_INSTALLED"

  if [[ -z "$rm_pkgs" ]]; then
    msg "Nothing" "No packages selected."
    return
  fi

  if yesno "Confirm Remove" "Remove:\n$rm_pkgs\n\nThis will free up space."; then
    apt_remove $rm_pkgs
    msg "Done" "Selected drivers removed."
  fi
}

de_menu() {
  local sel
  sel=$(menu "Choose Desktop Environment:" 4 \
    "1" "XFCE (lightweight)" \
    "2" "MATE" \
    "3" "GNOME (heavy)" \
    "4" "KDE Plasma (heavy)")

  [[ -z "$sel" ]] && return

  local pkgs=""
  case "$sel" in
    1) pkgs="xfce4 xfce4-terminal thunar";;
    2) pkgs="mate-desktop-environment mate-terminal";;
    3) pkgs="ubuntu-gnome-desktop";;
    4) pkgs="kde-plasma-desktop konsole";;
  esac

  msg "Desktop" "Installing $sel... this may take a while."
  apt_install $pkgs
  A_GUI=1

  case "$sel" in
    1) echo "exec startxfce4" > /root/.xinitrc;;
    2) echo "exec mate-session" > /root/.xinitrc;;
    3) echo "exec gnome-session" > /root/.xinitrc;;
    4) echo "exec startplasma-x11" > /root/.xinitrc;;
  esac

  msg "Done" "$sel installed. Run: startx"
}

dm_menu() {
  local sel
  sel=$(menu "Choose Display Manager:" 4 \
    "1" "LightDM (lightweight)" \
    "2" "GDM (GNOME)" \
    "3" "SDDM (KDE)")

  [[ -z "$sel" ]] && return

  local pkgs=""
  case "$sel" in
    1) pkgs="lightdm lightdm-gtk-greeter"; A_DM="lightdm";;
    2) pkgs="gdm3"; A_DM="gdm3";;
    3) pkgs="sddm"; A_DM="sddm";;
  esac

  msg "Display Manager" "Installing $sel..."
  apt_install $pkgs
  msg "Done" "$sel installed. Auto-starts on next boot."
}

create_user() {
  local username password
  username=$(input "Create User" "Enter username:")
  [[ -z "$username" ]] && return
  password=$(password_input "Create User" "Enter password for $username:")
  [[ -z "$password" ]] && return

  run useradd -m -G sudo -s /bin/bash "$username" 2>&1
  echo "$username:$password" | chpasswd
  A_USER="$username"
  msg "Done" "User $username created. Type: su - $username"
}

persistence_setup() {
  whiptail --title "Persistence" --yesno "Create persistent overlay file?\n\nFile: /persist.img (512 MB)\nChanges survive reboots." 10 60
  [[ $? -ne 0 ]] && return

  run dd if=/dev/zero of=/persist.img bs=1M count=512 2>&1
  run mkfs.ext4 -F -L persistence /persist.img 2>&1
  run mkdir -p /mnt/persist 2>&1
  echo "/persist.img /mnt/persist ext4 loop,defaults 0 0" >> /etc/fstab
  run mount /mnt/persist 2>&1
  run mkdir -p /mnt/persist/{upper,work} 2>&1
  # Create persistence.conf so live-boot can use this too
  echo "/ union" > /mnt/persist/persistence.conf

  cat > /etc/systemd/system/persist-overlay.service << 'SVC'
[Unit]
Description=Persistence overlay
DefaultDependencies=no
After=local-fs.target
Before=sysinit.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/persist-overlay
ExecStop=/usr/bin/persist-overlay stop

[Install]
WantedBy=local-fs.target
SVC

  cat > /usr/bin/persist-overlay << 'OVL'
#!/bin/bash
PERSIST=/mnt/persist
UPPER=$PERSIST/upper
WORK=$PERSIST/work
SNAP=$PERSIST/session

case "$1" in
  stop)
    mkdir -p $SNAP
    snap=$(date +%Y%m%d-%H%M%S)
    mkdir -p $SNAP/$snap
    mount --bind $UPPER $SNAP/$snap 2>/dev/null || true
    ;;
  *)
    mkdir -p $UPPER $WORK
    # Restore last snapshot if exists
    mkdir -p $SNAP 2>/dev/null
    last=$(ls -t $SNAP 2>/dev/null | head -1)
    if [ -n "$last" ] && [ -z "$(ls -A $UPPER 2>/dev/null)" ]; then
      cp -a $SNAP/$last/* $UPPER/ 2>/dev/null || true
    fi
    # Overlay persistent storage on top of root
    mkdir -p /mnt/root
    mount -t overlay overlay -o lowerdir=/,upperdir=$UPPER,workdir=$WORK /mnt/root 2>/dev/null
    mount --bind /mnt/root / 2>/dev/null || true
    ;;
esac
OVL
  chmod +x /usr/bin/persist-overlay
  run systemctl enable persist-overlay.service 2>&1
  msg "Done" "Persistence enabled. Changes survive reboots."
}

install_all() {
  whiptail --title "Install All" --yesno "Install:\n- Full GPU drivers + firmware\n- Wi-Fi firmware\n- XFCE Desktop\n- LightDM\n- Create user 'nexus'\n- Persistence" 14 50
  [[ $? -ne 0 ]] && return

  msg "Install All" "Full installation in progress..."
  apt_install mesa-utils mesa-vulkan-drivers xserver-xorg-video-all \
    libgl1-mesa-dri firmware-brcm80211 firmware-iwlwifi firmware-realtek
  apt_install xfce4 xfce4-terminal thunar lightdm lightdm-gtk-greeter
  echo "exec startxfce4" > /root/.xinitrc
  run useradd -m -G sudo -s /bin/bash nexus 2>&1 || true
  echo "nexus:nexus" | chpasswd
  A_GUI=1; A_DM="lightdm"; A_USER="nexus"
  run systemctl enable lightdm 2>&1

  msg "All Done" "Reboot to use full desktop."
  if yesno "Reboot?" "Reboot now?"; then reboot; fi
}

main_menu() {
  while true; do
    local sel
    sel=$(menu "Configure your system" 10 \
      "1" "Drivers & Hardware (install/remove audio, wifi, bt, gpu)" \
      "2" "Desktop Environment (XFCE, MATE, GNOME, KDE)" \
      "3" "Display Manager (LightDM, GDM, SDDM)" \
      "4" "Create User Account" \
      "5" "Setup Persistence (save across reboots)" \
      "6" "Install ALL — Full Desktop" \
      "7" "Uninstall Drivers & Rollback" \
      "8" "Exit")

    case "$sel" in
      1) drivers_menu;;
      2) de_menu;;
      3) dm_menu;;
      4) create_user;;
      5) persistence_setup;;
      6) install_all;;
      7) remove_drivers;;
      8) break;;
      *) break;;
    esac
  done

  echo -e "\n${G}Setup complete.${N}"
  echo -e "${D}  startx              Launch desktop${N}"
  [[ -n "$A_USER" ]] && echo -e "${D}  su - $A_USER      Switch user${N}"
  [[ -n "$A_DM" ]] && echo -e "${D}  systemctl start $A_DM${N}"
}

command -v whiptail >/dev/null || {
  echo -e "${R}whiptail not found. Run: apt install whiptail${N}"; exit 1
}
[[ $EUID -ne 0 ]] && echo -e "${R}Run as root: nexus-setup${N}" && exit 1

main_menu
