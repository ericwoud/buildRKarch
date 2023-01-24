#!/bin/bash

# Choose one of the following targets:
# ----------------
#TARGET="rk3288"
#RKDEVICE="openhour"
# or one of: evb firefly miqi openhour phycore popmetal rock-pi-n8 tinker tinker vyasa
# ----------------
TARGET="rk3588"
RKDEVICE="rock-5b"
ATFDEVICE="sdmmc"
#ATFDEVICE="nvme"
# ----------------

# https://github.com/bradfa/flashbench.git, running multiple times:
# sudo ./flashbench -a --count=64 --blocksize=1024 /dev/sda
# Shows me that times increase at alignment of 8k
# On f2fs it is used for wanted-sector-size, but sector size is stuck at 512
SD_BLOCK_SIZE_KB=8                   # in kilo bytes
# When the SD card was brand new, formatted by the manufacturer, parted shows partition start at 4MiB
# 1      4,00MiB  29872MiB  29868MiB  primary  fat32        lba
# Also, once runnig on rk3288 execute:
# bc -l <<<"$(cat /sys/block/mmcblk1/device/preferred_erase_size) /1024 /1024"
# bc -l <<<"$(cat /sys/block/mmcblk1/queue/discard_granularity) /1024 /1024"
SD_ERASE_SIZE_MB=4                   # in Mega bytes, align all partitions with this number

MINIMAL_SIZE_UBOOT_MB=15             # Minimal size of uboot partition
SPL_START_KB=32                      # Start of uboot partition
MINIMAL_SIZE_BOOT_MB=150             # Minimal size of boot partition
ROOT_END_MB=100%                     # Size of root partition
#ROOT_END_MB=$(( 256*1024  ))        # Size 256GiB 


case $TARGET in
  rk3288)
    INTERFACENAME="end0"
    PARTLABELROOT="$TARGET-root"
    PARTLABELBOOT=""
    PARTLABELUBOOT="$TARGET-${RKDEVICE}-uboot"
    NEEDED_PACKAGES="linux-armv7"
    PREBUILT_PACKAGES="$TARGET-uboot"
    RKARCH="armv7h"
    FSTABBOOT=""
    FSTABROOT="PARTLABEL=$PARTLABELROOT /     auto   defaults,noatime,nodiratime 0      1"
    ;;
  rk3588)
    INTERFACENAME="enP4p65s0"
    PARTLABELROOT="$TARGET@${ATFDEVICE}-root"
    PARTLABELBOOT="$TARGET@${ATFDEVICE}-boot"
    PARTLABELUBOOT="$TARGET-${RKDEVICE}@${ATFDEVICE}-uboot"
    NEEDED_PACKAGES="linux-rockchip-rk3588-bin"
    PREBUILT_PACKAGES="$TARGET-uboot-git"
    RKARCH="aarch64"
    FSTABBOOT="PARTLABEL=$PARTLABELBOOT /boot vfat   defaults                    0      2"
    FSTABROOT="PARTLABEL=$PARTLABELROOT /     auto   defaults,noatime,nodiratime 0      0"
    # If the root file system is btrfs or XFS, the fsck order should be set to 0 instead of 1.
    ;;
esac  
NEEDED_PACKAGES+=" base openssh wireless-regdb iproute2 f2fs-tools dtc mkinitcpio patch sudo"
NEEDED_PACKAGES+=" linux-firmware networkmanager"
EXTRA_PACKAGES="vim nano screen"
SCRIPT_PACKAGES="wget ca-certificates udisks2 parted gzip bc f2fs-tools btrfs-progs dosfstools"
SCRIPT_PACKAGES_ARCHLX="base-devel      uboot-tools  ncurses        openssl"
SCRIPT_PACKAGES_DEBIAN="build-essential u-boot-tools libncurses-dev libssl-dev flex bison"

LC="en_US.UTF-8"                     # Locale
TIMEZONE="Europe/Paris"              # Timezone
USERNAME="user"                      # User account name that is created
USERPWD="admin"                      # User password
ROOTPWD="admin"                      # Root password

ALARM_MIRROR="http://de.mirror.archlinuxarm.org"

QEMU_ARM="https://github.com/multiarch/qemu-user-static/releases/download/v5.2.0-11/x86_64_qemu-arm-static.tar.gz"
QEMU_AARCH64="https://github.com/multiarch/qemu-user-static/releases/download/v5.2.0-11/x86_64_qemu-aarch64-static.tar.gz"

ARCHBOOTSTRAP="https://raw.githubusercontent.com/tokland/arch-bootstrap/master/arch-bootstrap.sh"

REPOKEY="DD73724DCA27796790D33E98798137154FE1474C"
REPOURL='ftp://ftp.woudstra.mywire.org/repo/$arch'
BACKUPREPOURL='https://github.com/ericwoud/buildRKarch/releases/download/repo-$arch'

[ -f "./override.sh" ] && source ./override.sh

export LC_ALL=C
export LANG=C
export LANGUAGE=C

function finish {
  if [ -v rootfsdir ] && [ ! -z $rootfsdir ]; then
    $sudo sync
    echo Running exit function to clean up...
    $sudo sync
    echo $(mountpoint $rootfsdir)
    while [[ $(mountpoint $rootfsdir) =~  (is a mountpoint) ]]; do
      echo "Unmounting...DO NOT REMOVE!"
      $sudo umount -R $rootfsdir
      sleep 0.1
    done
    $sudo rm -rf $rootfsdir
    $sudo sync
    echo -e "Done. You can remove the card now.\n"
  fi
  unset rootfsdir
  [ -v sudoPID ] && kill -TERM $sudoPID
}

function waitdevlink {
  while [ ! -L "$1" ]; do
    echo "WAIT!"
    sleep 0.1
  done
}

function formatsd {
  echo ROOTDEV: $rootdev
  realrootdev=$(lsblk -prno pkname $rootdev)
  [ -z $realrootdev ] && exit
  [ "$l" = true ] && skip="" || skip='\|^loop'
  readarray -t options < <(lsblk --nodeps -no name,serial,size \
                    | grep -v "^"${realrootdev/"/dev/"/}$skip \
                    | grep -v 'boot0 \|boot1 \|boot2 ')
  PS3="Choose device to format: "
  select dev in "${options[@]}" "Quit" ; do
    if (( REPLY > 0 && REPLY <= ${#options[@]} )) ; then
      break
    else exit
    fi
  done
  device="/dev/"${dev%% *}
  for PART in `df -k | awk '{ print $1 }' | grep "${device}"` ; do $sudo umount $PART; done
  $sudo parted -s "${device}" unit MiB print
  echo -e "\nAre you sure you want to format "$device"???"
  read -p "Type <format> to format: " prompt
  [[ $prompt != "format" ]] && exit
  minimalbootstart=$(( $SPL_START_KB + ($MINIMAL_SIZE_UBOOT_MB * 1024) ))
  bootstart=0
  while [[ $bootstart -lt $minimalbootstart ]]; do
    bootstart=$(( $bootstart + ($SD_ERASE_SIZE_MB * 1024) ))
  done
  minimalrootstart=$(( $bootstart + ($MINIMAL_SIZE_BOOT_MB * 1024) ))
  rootstart=0
  while [[ $rootstart -lt $minimalrootstart ]]; do
    rootstart=$(( $rootstart + ($SD_ERASE_SIZE_MB * 1024) ))
  done
  if [[ "$ROOT_END_MB" =~ "%" ]]; then
    root_end_kb=$ROOT_END_MB
  else
    root_end_kb=$(( ($ROOT_END_MB/$SD_ERASE_SIZE_MB*$SD_ERASE_SIZE_MB)*1024))
    echo $root_end_kb
  fi
  case $TARGET in
    rk3288) formatsd_rk3288 $device ;;
    rk3588) formatsd_rk3588 $device ;;
  esac  
  $sudo sync
  $sudo lsblk -o name,mountpoint,label,partlabel,size,uuid "${device}"
}

function formatsd_rk3288 {
  device=$1
  $sudo dd of="${device}" if=/dev/zero bs=1024 count=$bootstart
  $sudo sync
  $sudo partprobe "${device}"
  $sudo parted -s -- "${device}" unit kiB \
    mklabel gpt \
    mkpart primary $bootstart $root_end_kb \
    mkpart primary $SPL_START_KB $bootstart \
    name 1 $PARTLABELROOT \
    name 2 $PARTLABELUBOOT \
    print
  $sudo sync
  $sudo partprobe "${device}"
  waitdevlink "/dev/disk/by-partlabel/$PARTLABELROOT"
  $sudo blkdiscard -fv "/dev/disk/by-partlabel/$PARTLABELROOT"
  waitdevlink "/dev/disk/by-partlabel/$PARTLABELROOT"
  [[ $SD_BLOCK_SIZE_KB -lt 4 ]] && blksize=$SD_BLOCK_SIZE_KB || blksize=4
  stride=$(( $SD_BLOCK_SIZE_KB / $blksize ))
  stripe=$(( ($SD_ERASE_SIZE_MB * 1024) / $SD_BLOCK_SIZE_KB ))
  $sudo mkfs.ext4 -v -b $(( $blksize * 1024 ))  -L "${TARGET^^}-ROOT" \
    -E stride=$stride,stripe-width=$stripe "/dev/disk/by-partlabel/$PARTLABELROOT"
}

function formatsd_rk3588 {
  echo FORMAT OTHER
  device=$1
  $sudo dd of="${device}" if=/dev/zero bs=1024 count=$bootstart
  $sudo sync
  $sudo partprobe "${device}"
  $sudo parted -s -- "${device}" unit kiB \
    mklabel gpt \
    mkpart primary $rootstart $root_end_kb \
    mkpart primary fat32 $bootstart $rootstart \
    mkpart primary $SPL_START_KB $bootstart \
    name 1 $PARTLABELROOT \
    name 2 $PARTLABELBOOT \
    name 3 $PARTLABELUBOOT \
    set 2 boot on \
    print
  $sudo sync
  $sudo partprobe "${device}"
  waitdevlink "/dev/disk/by-partlabel/$PARTLABELROOT"
  waitdevlink "/dev/disk/by-partlabel/$PARTLABELBOOT"
  $sudo mkfs.vfat -n "${TARGET^^}-BOOT" "/dev/disk/by-partlabel/$PARTLABELBOOT"
  $sudo mkfs.btrfs -f -L "${TARGET^^}-ROOT" "/dev/disk/by-partlabel/$PARTLABELROOT"
}

function bootstrap {
  if [ ! -d "$rootfsdir/etc" ]; then
    rm -f /tmp/downloads/$(basename $ARCHBOOTSTRAP)
    wget --no-verbose $ARCHBOOTSTRAP --no-clobber -P /tmp/downloads/
    $sudo bash /tmp/downloads/$(basename $ARCHBOOTSTRAP) -q -a $RKARCH -r $ALARM_MIRROR $rootfsdir
    ls $rootfsdir
  fi
}

function rootfs {
  $sudo cp -rf --dereference -v ./rootfs/boot $rootfsdir
  echo "--- Following packages are installed:"
  $schroot pacman -Qe
  echo "--- End of package list"
  $schroot pacman-key --init
  $schroot pacman-key --populate archlinuxarm
  $schroot pacman-key --recv-keys $REPOKEY
  $schroot pacman-key --finger     $REPOKEY
  $schroot pacman-key --lsign-key $REPOKEY
  if [ -z "$(cat $rootfsdir/etc/pacman.conf | grep -oP '^\[ericwoud\]')" ]; then
    serv="[ericwoud]\nServer = $REPOURL\nServer = $BACKUPREPOURL\nSigLevel = Optional\n"
    $sudo sed -i '/^\[core\].*/i'" ${serv}"'' $rootfsdir/etc/pacman.conf
  fi
  $schroot pacman -Syu --needed --noconfirm $NEEDED_PACKAGES $EXTRA_PACKAGES $PREBUILT_PACKAGES
  $schroot useradd --create-home --user-group \
               --groups audio,games,log,lp,optical,power,scanner,storage,video,wheel \
               -s /bin/bash $USERNAME
  echo $USERNAME:$USERPWD | $schroot chpasswd
  echo      root:$ROOTPWD | $schroot chpasswd
  [ ! -d $rootfsdir/etc/sudoers.d ] && $sudo mkdir -p $rootfsdir/etc/sudoers.d
  echo "%wheel ALL=(ALL) ALL" | $sudo tee $rootfsdir/etc/sudoers.d/wheel
  $schroot ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
  $sudo sed -i 's/.*PermitRootLogin.*/PermitRootLogin yes/' $rootfsdir/etc/ssh/sshd_config
  $sudo sed -i 's/.*UsePAM.*/UsePAM no/' $rootfsdir/etc/ssh/sshd_config
  # prevent login from tty gets broken:
  $sudo sed -i '/^-account.*pam_systemd_home.so.*/ s/./#&/' $rootfsdir/etc/pam.d/system-auth
  $sudo sed -i '/'$LC'/s/^#//g' $rootfsdir/etc/locale.gen           # Remove leading #
  $sudo sed -i '/.*'$LC'.*/{x;/^$/!d;g;}' $rootfsdir/etc/locale.gen # Only leave one match
  [ -z $($schroot localectl list-locales | grep --ignore-case $LC) ] && $schroot locale-gen
  echo "LANG=$LC" | $sudo tee $rootfsdir/etc/locale.conf
  echo "$TARGET" | $sudo tee $rootfsdir/etc/hostname
  echo -e "# <device> <dir> <type> <options> <dump> <fsck>\n$FSTABROOT\n$FSTABBOOT" | \
    $sudo tee $rootfsdir/etc/fstab
  $sudo cp -rfv --dereference rootfs/. $rootfsdir
  $sudo sed -i 's/.*interface-name.*/interface-name='"${INTERFACENAME}"'/' \
        "$rootfsdir/etc/NetworkManager/system-connections/Wired connection 1.nmconnection"
  $sudo chmod 0600 -R $rootfsdir/etc/NetworkManager/system-connections
  $sudo chmod 0700    $rootfsdir/etc/NetworkManager/system-connections
  $schroot systemctl reenable systemd-timesyncd.service
  $schroot systemctl reenable sshd.service
  $schroot systemctl reenable NetworkManager
  find -L "rootfs/etc/systemd/system" -name "*.service"| while read service ; do
    $schroot systemctl reenable $(basename $service)
  done
}

function chrootfs {
  echo "Entering chroot on image. Enter commands as if running on the target:"
  echo "Type <exit> to exit from the chroot environment."
  $schroot
}

function installscript {
  if [ ! -f "/etc/arch-release" ]; then ### Ubuntu / Debian
    $sudo apt-get install --yes         $SCRIPT_PACKAGES $SCRIPT_PACKAGES_DEBIAN
  else
    $sudo pacman -Syu --needed --noconfirm $SCRIPT_PACKAGES $SCRIPT_PACKAGES_ARCHLX
  fi
  # On all linux's
  if [ $runontarget != "true" ]; then # Not running on TARGET
    wget --no-verbose $QEMU_ARM          --no-clobber -P ./
    $sudo tar -xf $(basename $QEMU_ARM) -C /usr/local/bin
    wget --no-verbose $QEMU_AARCH64          --no-clobber -P ./
    $sudo tar -xf $(basename $QEMU_AARCH64) -C /usr/local/bin
    S1=':qemu-arm:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00'
    S2=':\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/local/bin/qemu-arm-static:CF'
    echo -n $S1$S2| $sudo tee /lib/binfmt.d/05-local-qemu-arm-static.conf
    S1=':qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7'
    S2=':\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/usr/local/bin/qemu-aarch64-static:CF'
    echo -n $S1$S2| $sudo tee /lib/binfmt.d/05-local-qemu-aarch64-static.conf
    $sudo systemctl restart systemd-binfmt.service
  fi
  exit
}
function removescript {
  # On all linux's
  if [ $runontarget != "true" ]; then # Not running on TARGET
    $sudo rm -f /usr/local/bin/qemu-arm-static
    $sudo rm -f /usr/local/bin/qemu-aarch64-static
    $sudo rm -f /lib/binfmt.d/05-local-qemu-arm-static.conf
    $sudo rm -f /lib/binfmt.d/05-local-qemu-aarch64-static.conf
    $sudo systemctl restart systemd-binfmt.service
  fi
  exit
}

[ $USER = "root" ] && sudo="" || sudo="sudo"
[[ $# == 0 ]] && args="-c"|| args=$@
cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
while getopts ":rcpalRSDA" opt $args; do declare "${opt}=true" ; done
echo OPTIONS: rootfs=$r postinst=$p chroot=$c apt=$a loopdev=$l
trap finish EXIT
shopt -s extglob

echo -e "Target="$TARGET"\nTargetDevice="$RKDEVICE
echo -e "Change target in first lines of script if necessairy..."

if [ -n "$sudo" ]; then
  sudo -v
  ( while true; do sudo -v; sleep 40; done ) &
  sudoPID=$!
fi

if [[ "$(tr -d '\0' 2>/dev/null </proc/device-tree/compatible)" == *"$TARGET"* ]]; then
  echo "Running on $TARGET"
  runontarget="true"
else
  echo "Not running on $TARGET"
  runontarget="false"
fi

[ "$a" = true ] && installscript
[ "$A" = true ] && removescript

rootdev=$(lsblk -pilno name,type,mountpoint | grep -G 'part /$' |  head -n1 | cut -d " " -f1)

if [ "$S" = true ] && [ "$D" = true ]; then formatsd; exit; fi

if [ -L "/dev/disk/by-partlabel/$PARTLABELROOT" ]; then
  mountdev=$(realpath "/dev/disk/by-partlabel/$PARTLABELROOT")
else
  echo "Not inserted! (Maybe not matching the target device on the card)"
  exit
fi

if [ "$rootdev" == "$mountdev" ];then
  rootfsdir="" ; r="" ; R=""     # Protect root when running from it!
  schroot=""
else
  rootfsdir="/mnt/rkrootfs"
  schroot="$sudo unshare --mount --fork --kill-child --pid --root=$rootfsdir"
fi

if [ "$R" = true ] ; then
  echo Removing rootfs...
  $sudo rm -rf $rootfsdir/*
  exit
fi
echo "Rootfsdir="$rootfsdir
echo "Mountdev="$mountdev

if [ ! -z $rootfsdir ]; then
  $sudo umount $mountdev
  [ -d $rootfsdir ] || $sudo mkdir $rootfsdir
  $sudo mount --source $mountdev --target $rootfsdir -o exec,dev,noatime,nodiratime
  [[ $? != 0 ]] && exit
  [ "$r" = true ] && bootstrap
  $sudo mount -t proc               /proc $rootfsdir/proc
  [[ $? != 0 ]] && exit
  $sudo mount --rbind --make-rslave /sys  $rootfsdir/sys
  [[ $? != 0 ]] && exit
  $sudo mount --rbind --make-rslave /dev  $rootfsdir/dev
  [[ $? != 0 ]] && exit
  $sudo mount --rbind --make-rslave /run  $rootfsdir/run
  [[ $? != 0 ]] && exit
  if [ -L "/dev/disk/by-partlabel/$PARTLABELBOOT" ]; then
    $sudo mkdir -p $rootfsdir/boot
    $sudo mount "/dev/disk/by-partlabel/$PARTLABELBOOT" $rootfsdir/boot
  fi
  [ "$r" = true ] && rootfs
  [ "$p" = true ] && $schroot rockchip-postinstall
  [ "$c" = true ] && chrootfs
fi

finish
exit

# sudo dd if=/dev/zero of=~/rock-5b-sdmmc.img bs=16M count=128 status=progress
# sudo udisksctl loop-setup -f ~/rock-5b-sdmmc.img
# ./build.sh -lSD
# ./build.sh -r
# ./build.sh
# rm -vrf /tmp/*
# pacman -Scc
# exit
# sudo udisksctl loop-delete --block-device /dev/loop0
# xz --keep --force --verbose ~/miqi-sdmmc.img
