#!/bin/bash

# The DangleBat Chronicles
# IPFS Node Installer for Slax 11.6.0
# Version 20230812

# Set Hostname
: "${HOST:=ipfs}"
hostnamectl set-hostname "${HOST}"

# Set Time
ntpdate 0.debian.pool.ntp.org
timedatectl set-timezone UTC
timedatectl set-local-rtc 0
apt -y install systemd-timesyncd

# Install Firmware
apt -y install firmware-misc-nonfree

# Enable Automatic Updates
apt -y install unattended-upgrades
echo unattended-upgrades unattended-upgrades/enable_auto_updates boolean true | debconf-set-selections
dpkg-reconfigure -f noninteractive unattended-upgrades

# Install & Configure IPFS
: "${VER:=0.21.0}"
[ "$(uname -m)" = 'x86_64' ] && ARCH='amd64' || ARCH='386'
wget -qO- "https://dist.ipfs.tech/kubo/v${VER}/kubo_v${VER}_linux-${ARCH}.tar.gz" | tar -zxvf -

kubo/install.sh
rm -rv kubo

sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf

mkdir -v /ipfs /ipns
touch /ipfs/.placeholder /ipns/.placeholder
chown -v guest:guest /ipfs /ipns /ipfs/.placeholder /ipns/.placeholder

cat << EOF > /etc/systemd/system/ipfs.service
[Unit]
Description=InterPlanetary File System (IPFS) daemon
Documentation=https://docs.ipfs.tech/
After=network.target

[Service]
AmbientCapabilities=CAP_NET_BIND_SERVICE
LimitNOFILE=1000000
MemorySwapMax=0
TimeoutStartSec=infinity
Type=notify
User=guest
Group=guest
StateDirectory=ipfs
Environment=IPFS_PATH="/home/guest/.ipfs"
ExecStartPre=-/usr/bin/rm /ipfs/.placeholder /ipns/.placeholder /home/guest/.ipfs/config
ExecStartPre=-/usr/local/bin/ipfs init
ExecStartPre=/usr/local/bin/ipfs config Gateway.RootRedirect '/ipns/danglebat.com/'
ExecStartPre=/usr/local/bin/ipfs config --json Mounts.FuseAllowOther true
ExecStartPre=/usr/local/bin/ipfs config --json Addresses.Gateway '["/ip4/0.0.0.0/tcp/80","/ip4/0.0.0.0/tcp/8080","/ip6/::/tcp/80","/ip6/::/tcp/8080"]'
ExecStart=/usr/local/bin/ipfs daemon --mount --migrate --agent-version-suffix=DangleBat
Restart=on-failure
KillSignal=SIGINT

[Install]
WantedBy=default.target
EOF

systemctl enable ipfs.service

cat << EOF > /etc/systemd/system/ipfs-pinning.service
[Unit]
Description=IPFS Pinning for The DangleBat Chronicles

[Service]
User=guest
Group=guest
Type=oneshot
ExecStart=/usr/local/bin/ipfs pin add /ipns/danglebat.com
EOF

[ -n "$STAFF" ] && cat << EOF >> /etc/systemd/system/ipfs-pinning.service
ExecStart=/usr/local/bin/ipfs pin add /ipns/archive.danglebat.com
EOF

cat << EOF > /etc/systemd/system/ipfs-pinning.timer
[Unit]
Description=Periodic IPFS Pinning for The DangleBat Chronicles

[Timer]
OnBootSec=5m
OnUnitActiveSec=2h

[Install]
WantedBy=timers.target
EOF

systemctl enable ipfs-pinning.timer

# Install & Configure Samba
apt -y install samba
rm -vf /usr/share/applications/python*.desktop

cat << EOF > /etc/samba/smb.conf
[global]
server role = standalone
map to guest = Bad User

[ipfs]
comment = InterPlanetary File System
path = /ipfs
browsable = no
guest ok = yes
guest only = yes
read only = yes

[ipns]
comment = InterPlanetary Name System
path = /ipns
browsable = no
guest ok = yes
guest only = yes
read only = yes

[danglebat.com]
comment = The DangleBat Chronicles
path = /ipns/danglebat.com
browsable = yes
guest ok = yes
guest only = yes
read only = yes
EOF

[ -n "$STAFF" ] && cat << EOF >> /etc/samba/smb.conf

[archive.danglebat.com]
comment = The DangleBat Chronicles Staff Archive
path = /ipns/archive.danglebat.com
browsable = yes
guest ok = yes
guest only = yes
read only = yes
EOF

# Install & Configure Chromium
apt -y install chromium chromium-sandbox
rm -vf /usr/share/applications/chromium.desktop

cat << EOF > /usr/share/applications/0ipfs.desktop
[Desktop Entry]
Type=Application
Name=Server Admin
Exec=fbliveapp chromium http://127.0.0.1:5001/webui/
Icon=gnome_network_workgroup
Terminal=false
EOF

# Format & Mount Device
: "${DEV:=sda}"
: "${FS:=vfat}"
umount -v "/dev/${DEV}"*
[ -n "$WIPE" ] && dd if=/dev/zero of="/dev/${DEV}" bs=16M status=progress; sync
mkfs -t "${FS}" "/dev/${DEV}"
mount -v "/dev/${DEV}" /mnt

# Install Slax
cp -rv /run/initramfs/memory/data/slax /mnt
savechanges /mnt/slax/modules/05-danglebat.sb
/mnt/slax/boot/bootinst.sh

# Custom DynFileFS Settings
: "${SIZE:=$(( ($(cat "/sys/class/block/${DEV}/size") / 2097152 - 2) * 1024 ))}"
initramfs_unpack /mnt/slax/boot/initrfs.img
sed -i "s/16000/${SIZE}/" /mnt/slax/boot/initrfs.img/lib/livekitlib
[ "${SIZE}" -gt   36000 ] && [ "${SIZE}" -le  396000 ] && sed -i 's/changes.dat.0/changes.dat.00/'   /mnt/slax/boot/initrfs.img/lib/livekitlib
[ "${SIZE}" -gt  396000 ] && [ "${SIZE}" -le 3996000 ] && sed -i 's/changes.dat.0/changes.dat.000/'  /mnt/slax/boot/initrfs.img/lib/livekitlib
[ "${SIZE}" -gt 3996000 ]                              && sed -i 's/changes.dat.0/changes.dat.0000/' /mnt/slax/boot/initrfs.img/lib/livekitlib
initramfs_pack /mnt/slax/boot/initrfs.img
