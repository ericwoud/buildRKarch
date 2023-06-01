# buildRKarch

Install a minimal Arch-Linux on Rockchip devices from scratch. Now I started only for RK-3288 and RK-3588 devices.

RK-3588 is now the default. Change the first couple of lines of the script (uncomment/comment) to change to RK-3288.

Openhour Chameleon device is added from Miqi files, as I have an OpenHour Chameleon.

All U-Boot supported devices are supported in this script, but only miqi an rock-5b are tested!

The script can be run from Arch Linux and Debian/Ubuntu.

The script only formats the SD card and installs packages and configures them. Nothing needs to be build.
Everything that is build, is installed with prebuild packages. These packages can be updated through the AUR.

RK3288: Now includes a patch so that temperature is regulated at higher degrees!
Delete the file rootfs/boot/dtbos/rk3288-thermal-overlay.dts before building, if you do not want to.

RK3288: The postinstall script installs a version of ffmpeg that supports HW decoding on RockChip devices, using only mainline kernel.
It is build from the same source as LibreElec's patched ffmpeg for Kodi.

The script is in development and uses sudo. Any bug may possibly delete everything permanently!

USE AT YOUR OWN RISK!!!

## Getting Started

You need:

  - Rockchip device (now only RK3288 and RK3588)
  - SD card

### Prerequisites

Take a look with the script at the original formatting of the SD card. We use this info to determine it's page/erase size.

### Installing


Clone from Git

```
git clone https://github.com/ericwoud/buildRKarch.git
```

Change directory

```
cd buildRKarch
```

Install all necessary packages with:
```
./build.sh -a
```
Check your SD card with the following command, write down where the original first partition starts! The script will first show you this info before formatting anything. Set `SD_BLOCK_SIZE_KB` and `SD_ERASE_SIZE_MB` in the script as described there. Don't format a brand new SD card before you find the original erase/block size. It is the best way to determine this.

Change RKDEVICE to your device. Following devices are supported:

RK3288: evb firefly miqi openhour phycore popmetal rock-pi-n8 vyasa tinker tinker-s
RK3588: rock-5b

```
./build.sh -F
```
Now format your SD card with the same command.

Now build the root filesystem.

```
./build.sh -r
```
Optionally enter chroot environment on the SD card:

```
./build.sh
```

## Deployment

Insert the SD card and powerup, login with user root and password admin. To start ssh to the board:

```
ssh root@192.168.1.7
```

Now install gnome and kodi including hardware decoding:
```
rockchip-postinstall
```
It is also possible to execute rockchip-postinstall from inside the chroot. You could use option `-p` for this.

You can either start gnome with:
```
systemctl start gdm
```
Or you can start kodi in standalone mode, with ffmpeg HW support (see acknowledgments):
```
systemctl start kodi
```
After this, you are on your own. It is supposed to be a minimal installation of Arch Linux.

## Installation on NVME of RK3588

Create the SD card as above and login in as root. Then clone and edit the script so that:
```
ROOT_END_MB=$(( 256*1024  ))        # Size 256GiB if you want to limit the size
```
Install packages with argument '-a'. Format with the same argument `-F`, but now choose the nvme disk. Install with argument '-r'. Now write U-Boot to the SPI with:
```
rockchip-write-dtbos --uboot@spi
```
U-Boot on SPI is not automatically updated with updating the uboot package, as it is on the SD card. I left it this way by design.
You still have a uboot partition on the nvme disk, but only the partlabel is being used (for identifying which board).

## Features

Command line options:

* -a   : Install necessairy packages.
* -A   : Remove necessairy packages.
* -F   : Format SD card or image, then setup rootfs (adds -r)
* -l   : Add this option to use an image-file instead of an SD card
* -r   : Build RootFS.
* -p   : Execute rockchip-postinstall from chroot
* -c   : Execute chroot
* -R   : Delete RootFS.
* -b   : Create backup of rootfs
* -B   : Restore backup of rootfs
* -x   : Create archive from image-file
* none : Enter chroot, same as option `-c`

* Other variables to tweak also at top of build script.


## Acknowledgments

* [Jernej Škrabec's FFmpeg](https://github.com/jernejsk/FFmpeg)

