# buildRKarch

Install a minimal Arch-Linux on Rockchip devices from scratch. Now I started only for RK-3288 devices.

Openhour Chameleon device is added from Miqi files, as I have an OpenHour Chameleon. It is set as default.

All U-Boot supported devices are supported in this script, but only Miqi is tested!

Now includes a patch so that temperature is regulated at higher degrees!
Delete the file rootfs/boot/dtbos/rk3288-thermal-overlay.dts before building, if you do not want to.

The script can be run from Arch Linux and Debian/Ubuntu.

The script only formats the SD card and installs packages and configures them. Nothing needs to be build.
Everything that is build, is installed with prebuild packages. These packages can be updated through the AUR.

The script installs a version of ffmpeg that supports HW decoding on RockChip devices, using only mainline kernel.
It is build from the same source as LibreElec's patched ffmpeg for Kodi.

The script is in development and uses sudo. Any bug may possibly delete everything permanently!

USE AT YOUR OWN RISK!!!

## Getting Started

You need:

  - Rockchip device (now only RK3288)
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

evb firefly miqi openhour phycore popmetal rock-pi-n8 vyasa tinker tinker-s

```
./build.sh -SD
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
ssh root@192.168.1.5
```

Now install gnome and kodi including hardware decoding:
```
rk3288-postinstall
```

You can either start gnome with:
```
systemctl start gdm
```
Or you can start kodi in standalone mode, with ffmpeg HW support (see acknowledgments):
```
systemctl start kodi
```
After this, you are on your own. It is supposed to be a minimal installation of Arch Linux.


## Features

Command line options:

* -a   : Install necessairy packages.
* -A   : Remove necessairy packages.
* -SD  : Format SD card
* -r   : Build RootFS.
* -R   : Delete RootFS.
* none : Enter chroot

* Other variables to tweak also at top of build script.


## Acknowledgments

* [Jernej Škrabec's FFmpeg](https://github.com/jernejsk/FFmpeg)

