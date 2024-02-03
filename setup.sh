#!/usr/bin/env bash

TOOLCHAIN="arm-none-linux-gnueabihf"
TOOLCHAIN_PATH="$(pwd)/$TOOLCHAIN/bin"

IMAGE="am335x_debian.img"
IMAGE_PATH="$(pwd)/$IMAGE"

BOOT="boot"
BOOT_PATH="$(pwd)/$BOOT"

DISK="mmcblk0"
DISK_PATH="/dev/$DISK"

MOUNT_PATH_BOOT="/tmp/boot"
MOUNT_PATH_ROOTFS="/tmp/rootfs"
MOUNT_PATH_IMAGE="/tmp/img"

OFFSET=4194304

# Download Linaro toolchain and its checksum if its not already there
echo "[i] Downloading latest Linaro GNU GCC x86_64 Linux Hosted cross compiler ..."
if [ ! -d $TOOLCHAIN ]; then
    wget -q "https://developer.arm.com/-/media/Files/downloads/gnu-a/10.3-2021.07/binrel/gcc-arm-10.3-2021.07-x86_64-arm-none-linux-gnueabihf.tar.xz?rev=302e8e98351048d18b6f5b45d472f406&hash=95ED9EEB24EAEEA5C1B11BBA864519B2" -O "$TOOLCHAIN.tar.xz"
    wget -q "https://developer.arm.com/-/media/Files/downloads/gnu-a/10.3-2021.07/binrel/gcc-arm-10.3-2021.07-x86_64-arm-none-linux-gnueabihf.tar.xz.asc?rev=e92080d836504f239ca27e4f9bbfdbd3&hash=5D713A9A710FA784BDAEAA4D0801533C" -O "$TOOLCHAIN.tar.xz.asc"

    # Compute checksum of downloaded archive
    computed_checksum_output=$(md5sum $TOOLCHAIN.tar.xz)
    read -r computed_checksum _ <<< "$computed_checksum_output"

    # Extract actual checksum
    content=$(cat $TOOLCHAIN.tar.xz.asc)
    read -r actual_checksum _ <<< "$content"

    # Compare checksums
    if [ "$computed_checksum" = "$actual_checksum" ]; then
        echo "[+] Checksum validated."
    else
        echo "[!] Invalid checksum."
        exit
    fi

    # Decompress and cleanup
    echo "[i] Decompressing archive ..."
    mkdir $TOOLCHAIN
    tar -xvf $TOOLCHAIN.tar.xz -C $TOOLCHAIN --strip-components=1 > /dev/null 2>&1

    echo "[i] Cleaning up ..."
    rm $TOOLCHAIN.tar.xz
    rm $TOOLCHAIN.tar.xz.asc
fi

# Add toolchain to PATH and export other environment variables
echo "[i] Adding toolchain to PATH and creating environment variables ..."

# Check if $TOOLCHAIN/bin is already in PATH
if [[ ":$PATH:" != *":$TOOLCHAIN_PATH:"* ]]; then
    export PATH=$TOOLCHAIN_PATH:$PATH
fi

# Check if CROSS_COMPILE is already set
if [ -z ${CROSS_COMPILE+x} ]; then 
    export CROSS_COMPILE=$TOOLCHAIN-
fi

# Check if ARCH is already set
if [ -z ${ARCH+x} ]; then 
    export ARCH=arm
fi

# Download "latest" Debian image for BeagleBone Black
echo "[i] Downloading latest Debian image for the BeagleBone Black ..."
if [ ! -f "${IMAGE_PATH}.img" ]; then
    wget -q "https://files.beagle.cc/file/beagleboard-public-2021/images/am335x-debian-12.2-iot-armhf-2023-10-07-4gb.img.xz" -O "$IMAGE.xz"
    wget -q "https://files.beagle.cc/file/beagleboard-public-2021/images/am335x-debian-12.2-iot-armhf-2023-10-07-4gb.img.xz.sha256sum" -O "$IMAGE.xz.sha256sum"

    # Compute checksum of downloaded image
    computed_checksum_output=$(sha256sum $IMAGE.xz)
    read -r computed_checksum _ <<< "$computed_checksum_output"

    # Extract actual checksum
    content=$(cat $IMAGE.xz.sha256sum)
    read -r actual_checksum _ <<< "$content"

    # Compare checksums
    if [ "$computed_checksum" = "$actual_checksum" ]; then
        echo "[+] Checksum validated."
    else
        echo "[!] Invalid checksum."
        exit
    fi

    # Decompress and cleanup
    echo "[i] Decompressing image ..."
    unxz $IMAGE.xz >/dev/null

    echo "[i] Cleaning up ..."
    rm $IMAGE.xz.sha256um
fi

# Create directory to store items which will go in boot sector
if [ -d $BOOT ]; then 
    rm -r $BOOT
fi
mkdir $BOOT

# Setup Das U-Boot
echo "[i] Cloning U-Boot Repository ..."

if [ ! -d "u-boot" ]; then
    git clone https://github.com/u-boot/u-boot.git > /dev/null 2>&1
fi

if [ -d "u-boot" ]; then
    cd u-boot || { echo "[!] Failed to change directory to u-boot"; exit 1; }
else
    echo "[!] u-boot directory not found"
    exit 1
fi

# Make configuration for U-Boot
echo "[i] Generating U-Boot configuration file ..."
make distclean 
make am335x_evm_defconfig 

# Create bootloader
echo "[i] Creating first and second stage bootloader ..."
make 

echo "[i] Moving first and second stage bootloader into holding folder ..."
cp MLO $BOOT_PATH/
cp u-boot.img $BOOT_PATH/
cd ../

echo "[i] Creating extlinux.conf ..."
mkdir -p $BOOT_PATH/extlinux
cat << EOF > $BOOT_PATH/extlinux/extlinux.conf
menu title Select kernel
timeout 100

label Linux kernel with device tree
    kernel /uImage
    fdt /am335x-boneblack.dtb
    append console=ttyO0,115200n8 root=/dev/mmcblk0p2 rw rootfstype=ext4 rootwait earlyprintk mem=512M
EOF

# Clone Linux kernel
echo "[i] Cloning Linux kernel ..."

if [ ! -d "linux" ]; then
    git clone https://github.com/beagleboard/linux.git > /dev/null 2>&1
fi

if [ -d "linux" ]; then
    cd linux || { echo "[!] Failed to change directory to linux"; exit 1; }
else
    echo "[!] linux directory not found"
    exit 1
fi

echo "[i] Configuring kernel ..."
make distclean >/dev/null
make omap2plus_defconfig 

echo "[i] Compiling kernel ..."
make uImage dtbs LOADADDR=0x80008000 -j6

echo "[i] Compiling kernel modules ..."
make modules -j6

echo "[i] Installing modules ..."
make modules_install

echo "[i] Moving kernel image and DTB to holding folders ..."
cp arch/arm/boot/uImage $BOOT_PATH/
cp arch/arm/boot/dts/ti/omap/am335x-boneblack.dtb $BOOT_PATH
cd ../

echo "[i] Preparting the disk at $DISK_PATH ..."
echo "[i] Unmounting all existing partitions on the disk ..."

for partition in $(ls ${DISK_PATH}*? 2>/dev/null); do
    umount $partition >/dev/null || true
done

echo "[i] Creating new partition table and partitions ..."
{
    echo "label: dos"
    echo ",256M,c,*"
    echo ",,"
} | sfdisk $DISK_PATH >/dev/null

echo "[i] Informing the OS about partition changes ..."
partprobe $DISK_PATH >/dev/null
udevadm trigger >/dev/null
udevadm settle >/dev/null
sleep 2

echo "[i] Formatting the first partition as FAT32 ..."
mkfs.vfat -F 32 ${DISK_PATH}p1 >/dev/null || { echo "[!] Failed to format partition 1"; exit 1; }

echo "[i] Formatting the second partition as ext4 ..."
mkfs.ext4 -F ${DISK_PATH}p2 >/dev/null || { echo "[!] Failed to format partition 2"; exit 1; }

echo "[i] Creating mount point $MOUNT_PATH_BOOT ..."
if [ ! -d $MOUNT_PATH_BOOT ]; then
    mkdir $MOUNT_PATH_BOOT
fi

echo "[i] Creating mount point $MOUNT_PATH_ROOTFS ..."
if [ ! -d $MOUNT_PATH_ROOTFS ]; then
    mkdir $MOUNT_PATH_ROOTFS
fi

echo "[i] Creating mount point $MOUNT_PATH_IMAGE ..."
if [ ! -d $MOUNT_PATH_IMAGE ]; then
    mkdir $MOUNT_PATH_IMAGE
fi

echo "[i] Mounting ${DISK_PATH}p1 at $MOUNT_PATH_BOOT ..."
mount -t vfat ${DISK_PATH}p1 $MOUNT_PATH_BOOT >/dev/null

echo "[i] Mounting ${DISK_PATH}p2 at $MOUNT_PATH_ROOTFS ..."
mount ${DISK_PATH}p2 $MOUNT_PATH_ROOTFS >/dev/null

echo "[i] Mounting $IMAGE_PATH at $MOUNT_PATH_IMAGE ..."
mount -o loop,offset=$OFFSET $IMAGE_PATH $MOUNT_PATH_IMAGE >/dev/null

echo "[i] Moving bootloader configuration files into ${DISK_PATH}p1 ..."
cp -r $BOOT_PATH/* $MOUNT_PATH_BOOT/
sync

echo "[i] Moving root file system onto partition 2 ..."
cp -r $MOUNT_PATH_IMAGE/* $MOUNT_PATH_ROOTFS/
sync

echo "[i] Updating kernel modules ..."
cp -r /lib/modules/6.5.0-rc1-00033-geb26cbb1a754/* $MOUNT_PATH_ROOTFS/lib/modules/

echo "[i] Unmounting ${DISK_PATH}p1 from $MOUNT_PATH_BOOT ..."
umount $MOUNT_PATH_BOOT >/dev/null || { echo "[!] Failed to unmount partition 1"; exit 1; }

echo "[i] Unmounting ${DISK_PATH}p2 from $MOUNT_PATH_ROOTFS ..."
umount $MOUNT_PATH_ROOTFS >/dev/null || { echo "[!] Failed to unmount partition 2"; exit 1; }

echo "[i] Unmounting $IMAGE_PATH from $MOUNT_PATH_IMAGE ..."
umount $MOUNT_PATH_IMAGE >/dev/null || { echo "[!] Failed to unmount image"; exit 1; }

echo "[+] OK to remove media ..."
