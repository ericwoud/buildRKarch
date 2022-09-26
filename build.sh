#!/bin/bash

ALARM_MIRROR="http://de.mirror.archlinuxarm.org"

QEMU="https://github.com/multiarch/qemu-user-static/releases/download/v5.2.0-11/x86_64_qemu-arm-static.tar.gz"

ARCHBOOTSTRAP="https://raw.githubusercontent.com/tokland/arch-bootstrap/master/arch-bootstrap.sh"

REPOKEY="BCF574990829687185CC072BD41842407A2A5FA2"
REPOURL='ftp://ftp.woudstra.mywire.org/repo/$arch'
BACKUPREPOURL="https://github.com/ericwoud/buildRKarch/releases/download/packages"

TARGET="rk3288"
RKDEVICE="openhour"
# evb firefly miqi openhour phycore popmetal rock-pi-n8 tinker tinker vyasa

KERNELDTB="$TARGET-$RKDEVICE"

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
SD_ERASE_SIZE_MB=4                   # in Mega bytes

SD_BLOCK_SIZE_KB=8                   # in kilo bytes
SD_ERASE_SIZE_MB=4                   # in Mega bytes
MINIMAL_SIZE_UBOOT_MB=15             # Minimal size of uboot partition
SPL_START_KB=32                    # Start of uboot partition

ROOTFS_LABEL="${TARGET^^}-ROOT"

# linux-firmware here?
NEEDED_PACKAGES="base openssh wireless-regdb iproute2 f2fs-tools dtc mkinitcpio patch sudo"
NEEDED_PACKAGES+=" linux-armv7 linux-firmware networkmanager"
EXTRA_PACKAGES="vim nano screen"
PREBUILT_PACKAGES="$TARGET-uboot"
SCRIPT_PACKAGES="wget ca-certificates udisks2 parted gzip bc f2fs-tools"
SCRIPT_PACKAGES_ARCHLX="base-devel      uboot-tools  ncurses        openssl"
SCRIPT_PACKAGES_DEBIAN="build-essential u-boot-tools libncurses-dev libssl-dev flex bison "

LC="en_US.utf8"                      # Locale
TIMEZONE="Europe/Paris"              # Timezone
USERNAME="user"
USERPWD="admin"
ROOTPWD="admin"                      # Root password

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
}

function waitdevlink {
  while [ ! -L "$1" ]; do
    echo "WAIT!"
    sleep 0.1
  done
}

function formatsd {
  echo ROOTDEV: $rootdev
  lsblkrootdev=($(lsblk -prno name,pkname,partlabel | grep $rootdev))
  [ -z $lsblkrootdev ] && exit
  realrootdev=${lsblkrootdev[1]}
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
  minimalrootstart=$(( $SPL_START_KB + ($MINIMAL_SIZE_UBOOT_MB * 1024) ))
  rootstart=0
  while [[ $rootstart -lt $minimalrootstart ]]; do
    rootstart=$(( $rootstart + ($SD_ERASE_SIZE_MB * 1024) ))
  done
  $sudo dd of="${device}" if=/dev/zero bs=1024 count=$rootstart
  $sudo parted -s -- "${device}" unit kiB \
    mklabel gpt \
    mkpart primary $rootstart 100% \
    mkpart primary $SPL_START_KB $rootstart \
    name 1 $TARGET-root \
    name 2 $TARGET-${RKDEVICE}-uboot \
    print
  $sudo partprobe "${device}"
  lsblkdev=""
  waitdevlink "/dev/disk/by-partlabel/$TARGET-root"
  $sudo blkdiscard -fv "/dev/disk/by-partlabel/$TARGET-root"
  waitdevlink "/dev/disk/by-partlabel/$TARGET-root"
  [[ $SD_BLOCK_SIZE_KB -lt 4 ]] && blksize=$SD_BLOCK_SIZE_KB || blksize=4
  stride=$(( $SD_BLOCK_SIZE_KB / $blksize ))
  stripe=$(( ($SD_ERASE_SIZE_MB * 1024) / $SD_BLOCK_SIZE_KB ))
  $sudo mkfs.ext4 -v -b $(( $blksize * 1024 ))  -L $ROOTFS_LABEL \
    -E stride=$stride,stripe-width=$stripe "/dev/disk/by-partlabel/$TARGET-root"
  $sudo sync
  $sudo lsblk -o name,mountpoint,label,size,uuid "${device}"
}

function bootstrap {
  if [ ! -d "$rootfsdir/etc" ]; then
    rm -f /tmp/downloads/$(basename $ARCHBOOTSTRAP)
    wget --no-verbose $ARCHBOOTSTRAP --no-clobber -P /tmp/downloads/
    $sudo bash /tmp/downloads/$(basename $ARCHBOOTSTRAP) -q -a armv7h -r $ALARM_MIRROR $rootfsdir
    ls $rootfsdir
    $sudo cp -vf /usr/local/bin/qemu-aarch64-static $rootfsdir/usr/local/bin/qemu-aarch64-static
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
  $sudo sed -i '/'$LC'/s/^#//g' $rootfsdir/etc/locale.gen
  [ -z $($schroot localectl list-locales | grep --ignore-case $LC) ] && $schroot locale-gen
  $schroot localectl set-locale LANG=en_US.UTF-8
  $sudo cp -rfv --dereference rootfs/. $rootfsdir
  $sudo chmod 0600 -R $rootfsdir/etc/NetworkManager/system-connections
  $sudo chmod 0700    $rootfsdir/etc/NetworkManager/system-connections
  $schroot systemctl reenable systemd-timesyncd.service
  $schroot systemctl reenable sshd.service
  $schroot systemctl reenable NetworkManager
  find -L "rootfs/etc/systemd/system" -name "*.service"| while read service ; do
    $schroot systemctl reenable $(basename $service)
  done

  $sudo cp -vf ./*.pkg.tar.xz $rootfsdir/tmp
}

function installscript {
  if [ ! -f "/etc/arch-release" ]; then ### Ubuntu / Debian
    $sudo apt-get install --yes         $SCRIPT_PACKAGES $SCRIPT_PACKAGES_DEBIAN
  else
    $sudo pacman -Syu --needed --noconfirm $SCRIPT_PACKAGES $SCRIPT_PACKAGES_ARCHLX
  fi
  # On all linux's
  if [ $runontarget != "true" ]; then # Not running on TARGET
    wget --no-verbose $QEMU          --no-clobber -P ./
    $sudo tar -xf $(basename $QEMU) -C /usr/local/bin
    S1=':qemu-arm:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00'
    S2=':\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/local/bin/qemu-arm-static:CF'
    echo -n $S1$S2| $sudo tee /lib/binfmt.d/05-local-qemu-arm-static.conf
    echo
    $sudo systemctl restart systemd-binfmt.service
  fi
  exit
}
function removescript {
  # On all linux's
  if [ $bpir64 != "true" ]; then # Not running on BPI-R64
    $sudo rm -f /usr/local/bin/qemu-aarch64-static
    $sudo rm -f /lib/binfmt.d/05-local-qemu-aarch64-static.conf
    $sudo systemctl restart systemd-binfmt.service
  fi
  exit
}

[ $USER = "root" ] && sudo="" || sudo="sudo"
[[ $# == 0 ]] && args=""|| args=$@
cd $(dirname $BASH_SOURCE)
while getopts ":ralRSDA" opt $args; do declare "${opt}=true" ; done
trap finish EXIT
shopt -s extglob
$sudo true

echo "Target device="$RKDEVICE
if [[ "$(tr -d '\0' 2>/dev/null </proc/device-tree/model)" == *"$TARGET"* ]]; then
  echo "Running on $TARGET"
  runontarget="true"
else
  echo "Not running on $TARGET"
  runontarget="false"
fi

[ "$a" = true ] && installscript
[ "$A" = true ] && removescript

rootdev=$(lsblk -pilno name,type,mountpoint | grep -G 'part /$')
rootdev=${rootdev%% *}

if [ "$S" = true ] && [ "$D" = true ]; then formatsd; exit; fi

if [ -L "/dev/disk/by-partlabel/$TARGET-root" ]; then
  mountdev=$(realpath "/dev/disk/by-partlabel/$TARGET-root")
else
  echo "Not inserted! (Maybe not matching the target device on the card)"
  exit
fi

if [ "$rootdev" == "$mountdev" ];then
  rootfsdir="" ; r="" ; R=""     # Protect root when running from it!
  schroot=""
else
  rootfsdir="/mnt/bpirootfs"
  schroot="$sudo unshare --mount --fork --kill-child --pid --root=$rootfsdir"
fi

echo OPTIONS: rootfs=$r apt=$a
if [ "$R" = true ] ; then
  echo Removing rootfs...
  $sudo rm -rf $rootfsdir/*
  exit
fi
echo "SETUP="$SETUP
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
  [ "$r" = true ] && rootfs || $schroot
fi

exit

# sudo dd if=/dev/zero of=~/miqi-sdmmc.img bs=16M count=480 status=progress
# sudo udisksctl loop-setup -f ~/miqi-sdmmc.img
# ./build.sh -lSD
# ./build.sh -r
# ./build.sh
# rm -vrf /tmp/*
# pacman -Scc
# exit
# sudo udisksctl loop-delete --block-device /dev/loop0
# xz --keep --force --verbose ~/miqi-sdmmc.img
