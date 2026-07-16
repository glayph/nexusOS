#!/bin/bash

C=$(printf '\033[96m'); G=$(printf '\033[92m'); Y=$(printf '\033[93m')
R=$(printf '\033[91m'); B=$(printf '\033[1m'); D=$(printf '\033[2m')
N=$(printf '\033[0m')
A_ERR=0
A_GUI=0
A_DM=""
A_USER=""

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

run() {
  echo -e "${C}▸${N} $*"
  "$@" 2>&1 | while IFS= read -r line; do
    echo "  $line"
  done
  return ${PIPESTATUS[0]}
}

apt_install() {
  run apt-get install -y --no-install-recommends "$@" 2>&1 | tail -5
  return ${PIPESTATUS[0]}
}

drivers_menu() {
  local choices
  choices=$(whiptail --title "Drivers & Hardware" --checklist "Select drivers to install:" 16 60 5 \
    "1" "Audio (ALSA + PulseAudio)" OFF \
    "2" "GPU (mesa + firmware)" ON \
    "3" "Wi-Fi firmware" OFF \
    "4" "Bluetooth" OFF \
    "5" "Restore all kernel modules" ON \
    3>&1 1>&2 2>&3)

  [[ -z "$choices" ]] && return

  msg "Drivers" "Installing selected drivers..."

  if [[ "$choices" == *"5"* ]]; then
    echo -e "${Y}▸ Restoring kernel modules...${N}"
    run apt-get install --reinstall -y linux-image-virtual 2>&1 | tail -3
  fi

  local pkgs=""
  [[ "$choices" == *"1"* ]] && pkgs+=" alsa-utils pulseaudio"
  [[ "$choices" == *"2"* ]] && pkgs+=" mesa-utils mesa-vulkan-drivers xserver-xorg-video-all libgl1-mesa-dri firmware-misc-nonfree"
  [[ "$choices" == *"3"* ]] && pkgs+=" wireless-tools firmware-brcm80211 firmware-iwlwifi firmware-realtek"
  [[ "$choices" == *"4"* ]] && pkgs+=" bluez bluez-tools"

  if [[ -n "$pkgs" ]]; then
    apt_install $pkgs
  fi

  A_ERR=1
  msg "Done" "Drivers installed.${choices} might need a reboot."
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

  if [[ "$sel" == "1" ]]; then
    cat > /root/.xinitrc << 'EOF'
exec startxfce4
EOF
  elif [[ "$sel" == "2" ]]; then
    echo "exec mate-session" > /root/.xinitrc
  elif [[ "$sel" == "3" ]]; then
    echo "exec gnome-session" > /root/.xinitrc
  elif [[ "$sel" == "4" ]]; then
    echo "exec startplasma-x11" > /root/.xinitrc
  fi

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

  msg "Display Manager" "Installing $sel... makes GUI start on boot."
  apt_install $pkgs
  msg "Done" "$sel installed. It auto-starts on next boot."
}

create_user() {
  local username password

  username=$(input "Create User" "Enter username:")
  [[ -z "$username" ]] && return

  password=$(input "Create User" "Enter password for $username:")
  [[ -z "$password" ]] && return

  run useradd -m -G sudo -s /bin/bash "$username" 2>&1
  echo "$username:$password" | chpasswd
  A_USER="$username"
  msg "Done" "User $username created. Login: su - $username"
}

persistence_setup() {
  msg "Persistence" "Setup persistence to save changes across reboots\n\nRequires a writable partition or USB with spare space."

  local dev target
  dev=$(lsblk -ndo NAME,SIZE,TYPE | grep -v loop | grep disk | head -5)

  msg "Persistence" "Detected drives:\n$dev\n\nChoose partition in next step..."

  local parts
  parts=$(lsblk -ndo NAME,SIZE,MOUNTPOINT | grep -v loop | grep -v swap)

  whiptail --title "Persistence" --yesno "Create persistent overlay file on current drive?\n\nFile will be: /persist.img (512 MB)" 12 60
  if [[ $? -eq 0 ]]; then
    run dd if=/dev/zero of=/persist.img bs=1M count=512 2>&1
    run mkfs.ext4 -F /persist.img 2>&1
    run mkdir -p /mnt/persist 2>&1
    echo "/persist.img /mnt/persist ext4 loop,defaults 0 0" >> /etc/fstab
    run mount /mnt/persist 2>&1
    run mkdir -p /mnt/persist/upper /mnt/persist/work /mnt/persist/session 2>&1

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
    direnv=$(ls -t $SNAP 2>/dev/null | head -1)
    [ -n "$direnv" ] && mount --bind $SNAP/$direnv $UPPER 2>/dev/null
    ;;
  *)
    mkdir -p $UPPER $WORK $SNAP
    snap=$(date +%Y%m%d-%H%M%S)
    mkdir -p $SNAP/$snap
    mount --bind $SNAP/$snap $UPPER 2>/dev/null
    mount -t overlay overlay -o lowerdir=/,upperdir=$UPPER,workdir=$WORK /mnt/overlay 2>/dev/null
    ;;
esac
OVL
    chmod +x /usr/bin/persist-overlay
    run systemctl enable persist-overlay.service 2>&1
    msg "Done" "Persistence enabled. Changes will survive reboots."
  fi
}

install_all() {
  whiptail --title "Install All" --yesno "This will install:\n- Audio + GPU + Wi-Fi drivers\n- XFCE Desktop\n- LightDM\n- Create user 'nexus'\n- Persistence\n\nProceed?" 14 60
  [[ $? -ne 0 ]] && return

  msg "Install All" "Full installation in progress..."

  run apt-get install --reinstall -y linux-image-virtual 2>&1 | tail -3
  apt_install alsa-utils pulseaudio mesa-utils mesa-vulkan-drivers \
    xserver-xorg-video-all libgl1-mesa-dri firmware-misc-nonfree \
    wireless-tools

  apt_install xfce4 xfce4-terminal thunar lightdm lightdm-gtk-greeter
  echo "exec startxfce4" > /root/.xinitrc

  run useradd -m -G sudo -s /bin/bash nexus 2>&1 || true
  echo "nexus:nexus" | chpasswd

  A_ERR=1; A_GUI=1; A_DM="lightdm"; A_USER="nexus"

  msg "All Done" "Reboot now to use the full desktop."

  if yesno "Reboot?" "Reboot now?"; then
    reboot
  fi
}

main_menu() {
  while true; do
    local sel
    sel=$(menu "Configure your system\nArrow keys to navigate, Enter to select" 9 \
      "1" "Drivers & Audio (ALSA, GPU, Wi-Fi, Bluetooth)" \
      "2" "Desktop Environment (XFCE, MATE, GNOME, KDE)" \
      "3" "Display Manager (auto-start GUI on boot)" \
      "4" "Create User Account" \
      "5" "Setup Persistence (save changes)" \
      "6" "Install ALL — Full Desktop Setup" \
      "7" "Exit")

    case "$sel" in
      1) drivers_menu;;
      2) de_menu;;
      3) dm_menu;;
      4) create_user;;
      5) persistence_setup;;
      6) install_all;;
      7) break;;
      *) break;;
    esac
  done

  echo -e "\n${G}Setup complete.${N}"
  echo -e "${D}  Commands:${N}"
  echo -e "${D}    startx              Launch desktop${N}"
  [[ -n "$A_USER" ]] && echo -e "${D}    su - $A_USER      Switch to user${N}"
  [[ -n "$A_DM" ]] && echo -e "${D}    systemctl start $A_DM  Start DM${N}"
  echo -e "${D}  Boot again and setup stays if persistence is on${N}\n"
}

command -v whiptail >/dev/null || {
  echo -e "${R}Error: whiptail not found.${N}"
  echo -e "${Y}Run: sudo apt-get install whiptail${N}"
  exit 1
}

[[ $EUID -ne 0 ]] && echo -e "${R}Run as root:${N} nexus-setup" && exit 1

main_menu
