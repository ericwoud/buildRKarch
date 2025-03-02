#!/bin/bash

# Set default configuration values
# These can be overridden by entering them into config.sh

ALARM_MIRROR="http://mirror.archlinuxarm.org"

REPOKEY="DD73724DCA27796790D33E98798137154FE1474C"
REPOURL='ftp://ftp.woudstra.mywire.org/repo/$arch'
BACKUPREPOURL='https://github.com/ericwoud/buildRKarch/releases/download/repo-$arch'

# Standard erase size, when it cannot be determined (using /dev/sdX cardreader or loopdev)
SD_ERASE_SIZE_MB=8                   # in Mega bytes

MINIMAL_SIZE_UBOOT_MB=15             # Minimal size of uboot partition
SPL_START_KB=32                      # Start of uboot partition
MINIMAL_SIZE_BOOT_MB=500             # Minimal size of boot partition
ROOT_END_MB=100%                     # Size of root partition
#ROOT_END_MB=$(( 256*1024  ))        # Size 256GiB
IMAGE_SIZE_MB=15000                  # Size of image
IMAGE_FILE="./rockchip.img"          # Name of image

NEEDED_PACKAGES="base dbus-broker-units openssh wireless-regdb iproute2 nftables btrfs-progs dosfstools\
 dtc mkinitcpio patch sudo evtest parted linux-firmware networkmanager"
EXTRA_PACKAGES="nano screen"
PREBUILT_PACKAGES="mmc-utils-git ssh-fix-reboot"
SCRIPT_PACKAGES="curl ca-certificates udisks2 parted gzip bc btrfs-progs dosfstools"
SCRIPT_PACKAGES_ARCHLX="base-devel      uboot-tools  ncurses        openssl"
SCRIPT_PACKAGES_DEBIAN="build-essential u-boot-tools libncurses-dev libssl-dev flex bison"

DEFAULT_IP="192.168.1.7"
LC="en_US.UTF-8"                     # Locale
TIMEZONE="Europe/Paris"              # Timezone
USERNAME="user"
USERPWD="admin"
ROOTPWD="admin"                      # Root password

function setupenv {
# If the root file system is btrfs or XFS, the fsck order should be set to 0 instead of 1.
PARTLABELROOT="${target}@${atfdevice}-root"
PARTLABELBOOT="${target}@${atfdevice}-boot"
PARTLABELUBOOT="${target}-${rkdev}@${atfdevice}-uboot"
FSTABBOOT="PARTLABEL=$PARTLABELBOOT /boot vfat   defaults                    0      2"
FSTABROOT="PARTLABEL=$PARTLABELROOT /     auto   defaults,noatime,nodiratime 0      0"
#BACKUPFILE="/run/media/$USER/DATA/${target}-${atfdevice}-rootfs.tar"
BACKUPFILE="./${target}-${rkdev}-${atfdevice}-rootfs.tar"
PREBUILT_PACKAGES+=' '"${target}-uboot"
case ${target} in
  rk3288)
    arch='armv7h'
    INTERFACENAME="end0"
    ;;
  rk3588)
    arch='aarch64'
    INTERFACENAME="enP4p65s0"
    [[ $rkdev == "armsom-sige7" ]] && PREBUILT_PACKAGES+=' '"linux-firmware-brcm43752"
    ;;
  *)
    echo "Unknown target '${target}'"
    exit
    ;;
esac
case ${arch} in
  armv7h)
    linuxpkgs=("linux-armv7   Standard Mainline ArchlinuxArm linux package")
    QEMU="https://github.com/multiarch/qemu-user-static/releases/download/v7.2.0-1/qemu-arm-static.tar.gz"
    QEMUFILE="qemu-arm-static"
    S1=':qemu-arm:M::\x7fELF\x01\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\x28\x00'
    S2=':\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/run/buildarch/qemu-arm-static:CF'
    ;;
  aarch64)
    linuxpkgs=("linux-aarch64-rk-rc    Mainline linux for RockChip Release Candidate <RECOMMENDED>"
               "linux-aarch64          Standard Mainline ArchlinuxArm linux package")
    QEMU="https://github.com/multiarch/qemu-user-static/releases/download/v7.2.0-1/qemu-aarch64-static.tar.gz"
    QEMUFILE="qemu-aarch64-static"
    S1=':qemu-aarch64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xb7'
    S2=':\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff:/run/buildarch/qemu-aarch64-static:CF'
    ;;
  *)
    echo "Unknown architecture '${arch}'"
    exit
    ;;
esac
} 
# End of default configuration values

function finish {
  trap 'echo got SIGINT' INT
  trap 'echo got SIGEXIT' EXIT
  [ -v noautomountrule ] && $sudo rm -vf $noautomountrule
  if [ -v rootfsdir ] && [ ! -z "$rootfsdir" ]; then
    $sudo sync
    echo Running exit function to clean up...
    while mountpoint -q $rootfsdir; do
      echo "Unmounting...DO NOT REMOVE!"
      $sudo sync
      $sudo umount -R $rootfsdir
      sleep 0.1
    done
    $sudo rm -rf $rootfsdir
    $sudo sync
    echo -e "Done. You can remove the card now.\n"
  fi
  unset rootfsdir
  if [ -v loopdev ] && [ ! -z "$loopdev" ]; then
    $sudo losetup -d $loopdev
  fi
  unset loopdev
  [ -v sudoPID ] && kill -TERM $sudoPID
  disableqemu
}

function waitdev {
  while [ ! -b $(realpath "$1") ]; do
    echo "WAIT!"
    sleep 0.1
  done
}

function formatimage {
  esize_mb=$(cat /sys/block/${device/"/dev/"/""}/device/preferred_erase_size 2>/dev/null) 
  [ -z "$esize_mb" ] && esize_mb=$SD_ERASE_SIZE_MB || esize_mb=$(( $esize_mb /1024 /1024 ))
  echo "Erase size = $esize_mb MB"
  minimalbootstart_kb=$(( $SPL_START_KB + ($MINIMAL_SIZE_UBOOT_MB * 1024) ))
  bootstart_kb=0
  while [[ $bootstart_kb -lt $minimalbootstart_kb ]]; do
    bootstart_kb=$(( $bootstart_kb + ($esize_mb * 1024) ))
  done
  minimalrootstart_kb=$(( $bootstart_kb + ($MINIMAL_SIZE_BOOT_MB * 1024) ))
  rootstart_kb=0
  while [[ $rootstart_kb -lt $minimalrootstart_kb ]]; do
    rootstart_kb=$(( $rootstart_kb + ($esize_mb * 1024) ))
  done
  if [[ "$ROOT_END_MB" =~ "%" ]]; then
    root_end_kb=$ROOT_END_MB
  else
    root_end_kb=$(( ($ROOT_END_MB/$esize_mb*$esize_mb)*1024 ))
  fi
  for PART in `df -k | awk '{ print $1 }' | grep "${device}"` ; do $sudo umount $PART; done
  if [ "$l" != true ]; then
    $sudo parted -s "${device}" unit MiB print
    echo -e "\nAre you sure you want to format "$device"???"
    read -p "Type <format> to format: " prompt
    [[ $prompt != "format" ]] && exit
  fi
  $sudo wipefs --all --force "${device}"
  $sudo sync
  $sudo partprobe "${device}"; udevadm settle
  $sudo parted -s -- "${device}" mklabel gpt
  [[ $? != 0 ]] && exit
  $sudo parted -s -- "${device}" unit kiB \
    mkpart primary $SPL_START_KB $bootstart_kb \
    mkpart primary fat32 $bootstart_kb $rootstart_kb \
    mkpart primary $rootstart_kb $root_end_kb \
    set 2 boot on \
    name 1 $PARTLABELUBOOT \
    name 2 $PARTLABELBOOT \
    name 3 $PARTLABELROOT \
    print
  $sudo partprobe "${device}"; $sudo udevadm settle
  while 
    bootdev=$( lsblk -prno partlabel,name $device | grep -P '^rk' | grep -- -boot | cut -d' ' -f2)
    [ -z "$bootdev" ]
  do sleep 0.1; done
  while 
    mountdev=$(lsblk -prno partlabel,name $device | grep -P '^rk' | grep -- -root | cut -d' ' -f2)
    [ -z "$mountdev" ]
  do sleep 0.1; done
  waitdev "${bootdev}"
  waitdev "${mountdev}"
  $sudo blkdiscard -fv "${mountdev}"
  waitdev "${mountdev}"
  $sudo mkfs.vfat -v -n "${target^^}-BOOT" ${bootdev}
  $sudo mkfs.btrfs -f -L "${target^^}-ROOT" ${mountdev}
  $sudo sync
  $sudo lsblk -o name,mountpoint,label,partlabel,size,uuid "${device}"
}

function resolv {
  $sudo cp /etc/resolv.conf $rootfsdir/etc/
  if [ -z "$(cat $rootfsdir/etc/resolv.conf | grep -oP '^nameserver')" ]; then
    echo "nameserver 8.8.8.8" | $sudo tee -a $rootfsdir/etc/resolv.conf
  fi
}

function bootstrap {
  trap ctrl_c INT
  [ -d "$rootfsdir/etc" ] && return
  eval repo=${BACKUPREPOURL}
  until pacmanpkg=$(curl -L $repo'/ericwoud.db' | tar -xzO --wildcards "pacman-static*/desc" \
        | grep "%FILENAME%" -A1 | tail -n 1)
  do sleep 2; done
  until curl -L $repo'/'$pacmanpkg | xz -dc - | $sudo tar x -C $rootfsdir
  do sleep 2; done
  [ ! -d "$rootfsdir/usr" ] && return
  $sudo mkdir -p $rootfsdir/{etc/pacman.d,var/lib/pacman}
  resolv
  echo 'Server = '"$ALARM_MIRROR/$arch"'/$repo' | \
    $sudo tee $rootfsdir/etc/pacman.d/mirrorlist
  cat <<-EOF | $sudo tee $rootfsdir/etc/pacman.conf
	[options]
	SigLevel = Never
	[core]
	Include = /etc/pacman.d/mirrorlist
	[extra]
	Include = /etc/pacman.d/mirrorlist
	[community]
	Include = /etc/pacman.d/mirrorlist
	EOF
  until $schroot pacman-static -Syu --noconfirm --needed --overwrite \* pacman archlinuxarm-keyring
  do sleep 2; done
  $sudo mv -vf $rootfsdir/etc/pacman.conf.pacnew         $rootfsdir/etc/pacman.conf
  $sudo mv -vf $rootfsdir/etc/pacman.d/mirrorlist.pacnew $rootfsdir/etc/pacman.d/mirrorlist
}

function setupnetworkmanager {
  nmdir="$rootfsdir/etc/NetworkManager/system-connections"
  cat <<-EOF | $sudo tee $nmdir/WiredConnection1.nmconnection
	[connection]
	id=WiredConnection1
	uuid=27553c0f-0427-3d42-9ea5-883eb4725bbb
	type=ethernet
	autoconnect-priority=-999
	interface-name=${INTERFACENAME}
	
	[ipv4]
	address1=${lanip}/24,${gateway}
	dns=${dns}
	method=manual
	EOF
  $sudo chmod 0600 -R $nmdir
  $sudo chmod 0700    $nmdir
}

function rootfs {
  trap ctrl_c INT
  resolv
  if [ -z "$(cat $rootfsdir/etc/pacman.conf | grep -oP '^\[ericwoud\]')" ]; then
    serv="[ericwoud]\nServer = $REPOURL\nServer = $BACKUPREPOURL\n"
    $sudo sed -i '/^\[core\].*/i'" ${serv}"'' $rootfsdir/etc/pacman.conf
  fi
  $schroot pacman-key --init
  $schroot pacman-key --populate archlinuxarm
  $schroot pacman-key --recv-keys $REPOKEY
  $schroot pacman-key --finger     $REPOKEY
  $schroot pacman-key --lsign-key $REPOKEY
  $schroot pacman-key --lsign-key "Arch Linux ARM Build System <builder@archlinuxarm.org>"
  until $schroot pacman -Syyu --needed --noconfirm --overwrite \* pacman-static \
                        $NEEDED_PACKAGES $linuxpkg $EXTRA_PACKAGES $PREBUILT_PACKAGES
  do sleep 2; done
  $schroot useradd --create-home --user-group \
               --groups audio,games,log,lp,optical,power,scanner,storage,video,wheel \
               -s /bin/bash $USERNAME
  echo $USERNAME:$USERPWD | $schroot chpasswd
  echo      root:$ROOTPWD | $schroot chpasswd
  echo "${target}" | $sudo tee $rootfsdir/etc/hostname
  echo "%wheel ALL=(ALL) ALL" | $sudo tee $rootfsdir/etc/sudoers.d/wheel
  $schroot ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime
  $sudo sed -i 's/.*PermitRootLogin.*/PermitRootLogin yes/' $rootfsdir/etc/ssh/sshd_config
  $sudo sed -i 's/.*UsePAM.*/UsePAM no/' $rootfsdir/etc/ssh/sshd_config
  $sudo sed -i 's/.*#IgnorePkg.*/IgnorePkg = rk*-uboot*/' $rootfsdir/etc/pacman.conf
  # prevent login from tty gets broken:
  $sudo sed -i '/^-account.*pam_systemd_home.so.*/ s/./#&/' $rootfsdir/etc/pam.d/system-auth
  $sudo sed -i '/'$LC'/s/^#//g' $rootfsdir/etc/locale.gen           # Remove leading #
  $sudo sed -i '/.*'$LC'.*/{x;/^$/!d;g;}' $rootfsdir/etc/locale.gen # Only leave one match
  [ -z $($schroot localectl list-locales | grep --ignore-case $LC) ] && $schroot locale-gen
  echo "LANG=$LC" | $sudo tee $rootfsdir/etc/locale.conf
  echo -e "# <device> <dir> <type> <options> <dump> <fsck>\n$FSTABROOT\n$FSTABBOOT" | \
    $sudo tee $rootfsdir/etc/fstab
  $schroot sudo systemctl --force --no-pager reenable systemd-timesyncd.service
  $schroot sudo systemctl --force --no-pager reenable sshd.service
  $schroot sudo systemctl --force --no-pager reenable NetworkManager
  $schroot rockchip-toolbox --extlinux
  setupnetworkmanager
}

function postinstall {
  trap ctrl_c INT
  $schroot rockchip-postinstall
}

function chrootfs {
  echo "Entering chroot on image. Enter commands as if running on the target:"
  echo "Type <exit> to exit from the chroot environment."
  $schroot
}

function compressimage {
  rm -f $IMAGE_FILE".xz" $IMAGE_FILE".gz"
  $sudo rm -vrf $rootfsdir/tmp/*
  echo "Type Y + Y:"
  yes | $schroot pacman -Scc
  finish
  [ "$x" = true ] && xz   --keep --force --verbose $IMAGE_FILE
  [ "$z" = true ] && dd if=$IMAGE_FILE status=progress | gzip >$IMAGE_FILE".gz"
}

function backuprootfs {
  $sudo tar -vcf "${BACKUPFILE}" -C $rootfsdir .
}

function restorerootfs {
  if [ -z "$(ls $rootfsdir)" ] || [ "$(ls $rootfsdir)" = "boot" ]; then
    $sudo tar -vxf "${BACKUPFILE}" -C $rootfsdir
    echo "Run ./build.sh and execute 'rockchip-write-dtbos --uboot@root or --uboot@spi' to" \
         " write the new uboot! Then type 'exit'."
  else
    echo "Root partition not empty!"
  fi
}

function setupqemu {
  if [ $hostarch == "x86_64" ]; then # Script running on x86_64 so use qemu
    if [ ! -f "/run/buildarch/${QEMUFILE}" ]; then
      $sudo mkdir -p "/run/buildarch"
      until curl -L $QEMU | $sudo tar -xz  -C "/run/buildarch"
      do sleep 2; done
    fi
    $sudo mkdir -p "/run/binfmt.d"
    echo -n $S1$S2| $sudo tee /run/binfmt.d/05-buildarch-qemu-static.conf >/dev/null
    echo
    $sudo systemctl restart systemd-binfmt.service
  fi
}

function disableqemu {
  if [ -f "/run/binfmt.d/05-buildarch-qemu-static.conf" ]; then
    $sudo rm -f "/run/binfmt.d/05-buildarch-qemu-static.conf" >/dev/null
    $sudo systemctl restart systemd-binfmt.service
  fi
}

function removescript {
  # On all linux's
  if [ $hostarch == "x86_64" ]; then # Script running on x86_64 so remove qemu
    $sudo rm -f /usr/local/bin/qemu-arm-static
    $sudo rm -f /usr/local/bin/qemu-aarch64-static
    $sudo rm -f /lib/binfmt.d/05-local-qemu-arm-static.conf
    $sudo rm -f /lib/binfmt.d/05-local-qemu-aarch64-static.conf
    $sudo systemctl restart systemd-binfmt.service
  fi
  exit
}

function add_children() {
  [ -z "$1" ] && return || echo $1
  for ppp in $(pgrep -P $1 2>/dev/null) ; do add_children $ppp; done
}

function ctrl_c() {
  echo "** Trapped CTRL-C, PID=$mainPID **"
  if [ ! -z "$mainPID" ]; then
    for pp in $(add_children $mainPID | sort -nr); do
      $sudo kill -s SIGKILL $pp &>/dev/null
    done
  fi
  trap - EXIT
  finish
  exit 1
}

export LC_ALL=C
export LANG=C
export LANGUAGE=C 

[ -f "config.sh" ] && source config.sh

cd "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")"
[ $USER = "root" ] && sudo="" || sudo="sudo"
while getopts ":rlcbxzpRFBMI" opt $args; do
  if [[ "${opt}" == "?" ]]; then echo "Unknown option -$OPTARG"; exit; fi
  declare "${opt}=true"
  ((argcnt++))
done
[ -z "$argcnt" ] && c=true
if [ "$l" = true ]; then
  if [ $argcnt -eq 1 ]; then 
    c=true
  else
    [ ! -f $IMAGE_FILE ] && F=true
  fi
fi
[ "$F" = true ] && r=true
trap finish EXIT
trap ctrl_c INT
shopt -s extglob

if [ -n "$sudo" ]; then
  sudo -v
  ( while true; do sudo -v; sleep 40; done ) &
  sudoPID=$!
fi

echo "Current dir:" $(realpath .)

compatible="$(tr -d '\0' 2>/dev/null </proc/device-tree/compatible)"
echo "Compatible:" $compatible

hostarch=$(uname -m)
echo "Host Arch:" $hostarch

if [ ! -f "/etc/arch-release" ]; then ### Ubuntu / Debian
  for package in $SCRIPT_PACKAGES $SCRIPT_PACKAGES_DEBIAN; do 
    if ! dpkg -l $package >/dev/null; then missing+=" $package"; fi
  done
  instcmd="sudo apt-get install $missing"
else
  for package in $SCRIPT_PACKAGES $SCRIPT_PACKAGES_ARCHLX; do 
    if ! pacman -Qi $package >/dev/null; then missing+=" $package"; fi
  done
  instcmd="sudo pacman -Syu $missing"
fi
if [ ! -z "$missing" ]; then
  echo -e "\nInstall these packages with command:\n${instcmd}\n"
  exit
fi

rootdevice=$(mount | grep -E '\s+on\s+/\s+' | cut -d' ' -f1)
rootdev=$(lsblk -sprno name ${rootdevice} | tail -2 | head -1)
echo "rootdev=$rootdev , do not use."
[ -z $rootdev ] && exit

pkroot=$(lsblk -srno name ${rootdevice} | tail -1)
echo "pkroot=$pkroot , do not use."
[ -z $pkroot ] && exit

[ "$I" = true ] && source config.sh

if [ "$F" = true ]; then
  PS3="Choose target SOC to format image for: "; COLUMNS=1
  select target in "rk3288 SOC" "rk3588 SOC" "Quit" ; do
    if (( REPLY > 0 && REPLY <= 2 )) ; then break; else exit; fi
  done
  target=${target%% *}
  case ${target} in
    rk3288)
      rkdevs=(evb firefly miqi openhour phycore popmetal rock-pi-n8 tinker tinker vyasa)
      ;;
    rk3588)
      rkdevs=(armsom-sige7 rock-5b)
      ;;
  esac
  PS3="Choose rockchip device to format image for: "; COLUMNS=1
  select rkdev in "${rkdevs[@]}" "Quit" ; do
    if (( REPLY > 0 && REPLY <= ${#rkdevs[@]} )) ; then break; else exit; fi
  done
  rkdev=${rkdev%% *}
  PS3="Choose atfdevice to format image for: "; COLUMNS=1
  select atfdevice in "sdmmc SD Card" "nvme  NVME solid state drive" "Quit" ; do
    if (( REPLY > 0 && REPLY <= 2 )) ; then break; else exit; fi
  done
  atfdevice=${atfdevice%% *}
  if [ "$l" = true ]; then
    [ ! -f $IMAGE_FILE ] && touch $IMAGE_FILE
    loopdev=$($sudo losetup --show --find $IMAGE_FILE)
    echo "Loop device = $loopdev"
    device=$loopdev
  else
    readarray -t options < <(lsblk -dprno name,size \
             | grep -v "^/dev/"${pkroot} | grep -v 'boot0 \|boot1 \|boot2 ')
    PS3="Choose device to format: "; COLUMNS=1
    select device in "${options[@]}" "Quit" ; do
      if (( REPLY > 0 && REPLY <= ${#options[@]} )) ; then break; else exit; fi
    done
    device=${device%% *}
  fi
else
  if [ "$l" = true ]; then
    loopdev=$($sudo losetup --show --find $IMAGE_FILE)
    echo "Loop device = $loopdev"
    $sudo partprobe $loopdev; udevadm settle
    device=$loopdev
  else
    readarray -t options < <(lsblk -prno partlabel,pkname | grep -P '^rk' | grep -- -root \
                                 | grep -v ${pkroot} | grep -v 'boot0$\|boot1$\|boot2$')
    if [ ${#options[@]} -gt 1 ]; then
      PS3="Choose device to work on: "; COLUMNS=1
      select choice in "${options[@]}" "Quit" ; do
        if (( REPLY > 0 && REPLY <= ${#options[@]} )) ; then break; else exit; fi
      done
    else
      choice=${options[0]}
    fi
    device=$(echo $choice | cut -d' ' -f2)
  fi
  pub=$(lsblk -prno partlabel $device | grep -P '^rk' | grep -- -uboot)
  rkdev=${pub#*-}
  target=${pub%"-$rkdev"}
  rkdev=${rkdev/"-uboot"/""}
  atfdevice=${rkdev#*@}
  rkdev=${rkdev%"@$atfdevice"}
fi
echo -e "Device=${device}\nTarget=${target}\nRK-device=${rkdev}\nATF-device=${atfdevice}"
[ -z "$device" ] && exit
[ -z "${target}" ] && exit
[ -z "${rkdev}" ] && exit
[ -z "${atfdevice}" ] && exit
setupenv # Now that target and atfdevice are known.

if [ "$r" = true ]; then
  echo -e "\nCreate root filesystem\n"
  PS3="Choose linux package to install: "; COLUMNS=1
  select linuxpkg in "${linuxpkgs[@]}" "Quit" ; do
    if (( REPLY > 0 && REPLY <= ${#linuxpkgs[@]} )) ; then break; else exit; fi
  done
  linuxpkg=${linuxpkg%% *}
  read -p "Enter ip address for local network (emtpy for default): " lanip
  [ -z "$lanip" ] && lanip=$DEFAULT_IP
  echo "IP = "$lanip
  gateway="$(echo $lanip | cut -d"." -f1,2,3)"'.1'
  read -p "Enter ip address of gateway (emtpy for default): " readgateway
  [ ! -z "$readgateway" ] && gateway=$readgateway
  echo "Default Gateway = "$gateway
  read -p "Enter ip address of dns (emtpy for same as gateway): " dns
  [ -z "$dns" ] && dns=$gateway
  echo "DNS = "$dns
fi

# Check if 'config.sh' exists.  If so, source that to override default values.
[ -f "config.sh" ] && source config.sh

if [ "$l" = true ] && [ $(stat --printf="%s" $IMAGE_FILE) -eq 0 ]; then
  echo -e "\nCreating image file..."
  dd if=/dev/zero of=$IMAGE_FILE bs=1M count=$IMAGE_SIZE_MB status=progress conv=notrunc,fsync
  $sudo losetup --set-capacity $device
fi

$sudo mkdir -p "/run/udev/rules.d"
noautomountrule="/run/udev/rules.d/10-no-automount-rk.rules"
echo 'KERNELS=="'${device/"/dev/"/""}'", ENV{UDISKS_IGNORE}="1"' | $sudo tee $noautomountrule

[ "$F" = true ] && formatimage

mountdev=$(lsblk -prno partlabel,name $device | grep -P '^rk' | grep -- -root | cut -d' ' -f2)
bootdev=$( lsblk -prno partlabel,name $device | grep -P '^rk' | grep -- -boot | cut -d' ' -f2)
echo "Mountdev = $mountdev"
echo "Bootdev  = $bootdev"
[ -z "$mountdev" ] && exit

if [ "$rootdev" == "$(realpath $mountdev)" ]; then
  echo "Target device == Root device, exiting!"
  exit
fi

rootfsdir="/tmp/rkrootfs.$$"
schroot="$sudo unshare --fork --kill-child --pid --root=$rootfsdir"
echo "Rootfsdir="$rootfsdir

$sudo umount $mountdev
$sudo mkdir -p $rootfsdir
[ "$b" = true ] && ro=",ro" || ro=""
$sudo mount --source $mountdev --target $rootfsdir \
            -o exec,dev,noatime,nodiratime$ro
[[ $? != 0 ]] && exit
if [ ! -z "$bootdev" ]; then
  $sudo umount $bootdev
  $sudo mkdir -p $rootfsdir/boot
  $sudo mount -t vfat "$bootdev" $rootfsdir/boot
  [[ $? != 0 ]] && exit
fi

if [ "$b" = true ] ; then backuprootfs ; exit; fi
if [ "$B" = true ] ; then restorerootfs; exit; fi

if [ "$R" = true ] ; then
  read -p "Type <remove> to delete everything from the card: " prompt
  [[ $prompt != "remove" ]] && exit
  (shopt -s dotglob; $sudo rm -rf $rootfsdir/*)
  exit
fi

setupqemu

[ ! -d "$rootfsdir/dev" ] && $sudo mkdir $rootfsdir/dev
$sudo mount --rbind --make-rslave /dev  $rootfsdir/dev # install gnupg needs it
[[ $? != 0 ]] && exit
if [ "$r" = true ]; then bootstrap &
  mainPID=$! ; wait $mainPID ; unset mainPID
fi
$sudo mount -t proc               /proc $rootfsdir/proc
[[ $? != 0 ]] && exit
$sudo mount --rbind --make-rslave /sys  $rootfsdir/sys
[[ $? != 0 ]] && exit
$sudo mount --rbind --make-rslave /run  $rootfsdir/run
[[ $? != 0 ]] && exit
if [ "$r" = true ]; then rootfs &
  mainPID=$! ; wait $mainPID ; unset mainPID
fi
if [ "$p" = true ]; then postinstall &
  mainPID=$! ; wait $mainPID ; unset mainPID
fi
[ "$c" = true ] && chrootfs
if [ "$x" = true ] || [ "$z" = true ]; then
  compressimage
fi

exit

