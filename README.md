# BeagleBone Black Setup

This repository contains a script designed to automate the setup of a Debian Linux environment on the BeagleBone Black. It streamlines the process of configuring the U-Boot bootloader, compiling the Linux kernel, and setting up the Debian root file system on a microSD card.

## Prerequisites

Before running the script, please ensure you have completed the following steps:

- **Create a Dedicated Directory**: It's recommended to create a dedicated directory to run this script. The script generates several directories and files, and having a dedicated space helps in managing these resources efficiently.

- **Insert Your microSD Card**: Make sure your microSD card is inserted into your host machine before executing the script. The script writes data directly to the microSD card to prepare it for use with the BeagleBone Black.

- **Verify SD Card Device Name**: The script assumes the SD card device name is `mmcblk0`. This is a common name for SD card devices in Linux, but it might differ on your system. You can check the device name by running `lsblk` before proceeding. If your device name is different, update the `DISK` variable value on line 12 of the script to match your specific device name.

- **Sudo Privileges**: The script requires sudo privileges to execute certain commands, such as writing to the SD card and mounting file systems. Please ensure you have the necessary permissions to execute commands as `sudo` on your system.

## Usage

1. Clone this repository or download the script to your dedicated directory.
2. Open a terminal and navigate to the directory containing the script.
3. Update the `DISK` variable in the script if your SD card device name differs from `mmcblk0`.
4. Execute the script with sudo privileges:
    ```bash
    sudo ./setup.sh
    ```
5. Follow any on-screen instructions to complete the setup process.

## Contributions

Contributions to the script are welcome. If you encounter any issues or have suggestions for improvements, please open an issue or submit a pull request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.
