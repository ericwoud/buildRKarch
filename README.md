# buildRKarch

** NOTICE: RK3588 HAS BEEN MOVED TO USING MAINLINE KERNEL, V4L2_REQUEST AND PANTHOR **

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

Basic settings are prompted for, when running the script. Other tweaks can be written to config.sh in the
same directory as the script. There the environment variables can be set, that will override the default settings.

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

The following commands can also be run with the `-l` switch. In this case an image is created by means of a loop device.

Now format your SD card and create rootfs with:
```
./build.sh -F
```

Optionally run the post-install script from chroot (which is slower). It can also be run after the board has booted (which is faster).

```
./build.sh -p
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
rockchip-toolbox --uboot@spi
```
U-Boot on SPI is not automatically updated with updating the uboot package, as it is on the SD card. I left it this way by design.
You still have a uboot partition on the nvme disk, but only the partlabel is being used (for identifying which board).

## Features

Command line options:

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
* [Armbian Linux Kernel](https://armbian.com)
