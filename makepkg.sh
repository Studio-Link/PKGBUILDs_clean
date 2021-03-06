#!/bin/bash -ex
qemu="/opt/qemu-2.2.0/arm-softmmu/qemu-system-arm"
ssh="ssh  -o StrictHostKeyChecking=no root@127.0.0.1 -p2222"
scp="scp -P2222 -r root@127.0.0.1:"
pacman="pacman --noconfirm --force --needed"
version="15.5.0-beta"
pkgbuilds="
opus
jack2
libre
librem
baresip
jack_capture
aj-snapshot
jack_gaudio
darkice
studio-webapp
"
export QEMU_AUDIO_DRV=none
$qemu -daemonize -M vexpress-a9 -kernel zImage \
	-drive file=root_pkgbuild.img,if=sd,cache=none -append "root=/dev/mmcblk0p2 rw" \
	-m 512 -net nic -net user,hostfwd=tcp::2222-:22 -snapshot
sleep 20

$ssh "echo 'Server = http://mirror.studio-connect.de/$version/armv7h/\$repo' > /etc/pacman.d/mirrorlist"

echo "### Install requirements ###"
$ssh "$pacman -Syu"
$ssh "pacman-db-upgrade"
$ssh "$pacman -S git vim ntp nginx aiccu python2 python2-distribute avahi wget"
$ssh "$pacman -S python2-virtualenv alsa-plugins alsa-utils gcc make redis sudo fake-hwclock"
$ssh "$pacman -S python2-numpy ngrep tcpdump lldpd"
$ssh "$pacman -S spandsp gsm celt"
$ssh "$pacman -S hiredis libmicrohttpd openvpn dosfstools"
$ssh "yes | pacman --needed -S linux-am33x"

echo "### Install build requirements and tools ###"
$ssh "$pacman -S base-devel distcc cpufrequtils"

echo "### Download all packages ###"
$ssh "yes | pacman -Scc"
$ssh "pacman -Qq > /tmp/packages"
$ssh "bash -c \"pacman --noconfirm --force -Sw \$(cat /tmp/packages|tr '\n' ' ')\""

echo "### Build ###"
$ssh "systemctl start distccd"
$ssh "useradd -m build"
$ssh "sed -i s/\!distcc/distcc/ /etc/makepkg.conf"
$ssh "echo 'DISTCC_HOSTS=\"10.0.2.2\"' >> /etc/makepkg.conf"
$ssh "echo 'MAKEFLAGS=\"-j4\"' >> /etc/makepkg.conf"

$ssh "git clone https://github.com/Studio-Link/PKGBUILDs_clean.git /tmp/PKGBUILDs"
$ssh "chown -R build /tmp/PKGBUILDs"
$ssh "echo -e 'root ALL=(ALL) ALL\nbuild ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers"
makepkg="sudo -u build makepkg --install --noconfirm --syncdeps"
$ssh "pump --shutdown" #bugfix distcc client error
for pkg in $pkgbuilds; do
    scp -P2222 /var/www/$version/armv7h/studio/$pkg-*.tar.xz \
        root@127.0.0.1:/tmp/PKGBUILDs/$pkg/ || true
    $ssh "cd /tmp/PKGBUILDs/$pkg; $makepkg"
done

$ssh "cp -a /tmp/PKGBUILDs/*/*armv7h.pkg.tar.xz /var/cache/pacman/pkg/"

$ssh "repo-add /root/studio.db.tar.gz /var/cache/pacman/pkg/*.pkg.tar.xz"

mkdir -p /var/www/$version/armv7h/studio
rm -f /var/www/$version/armv7h/studio/*
$scp/var/cache/pacman/pkg/*.pkg.tar.xz /var/www/$version/armv7h/studio/
$scp/root/studio.db.tar.gz /var/www/$version/armv7h/studio/
ln -s /var/www/$version/armv7h/studio/studio.db.tar.gz /var/www/$version/armv7h/studio/studio.db
