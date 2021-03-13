SIGN IN
Design

Android Open Source Project
Google is committed to advancing racial equity for Black communities. See how.
AOSP
Design
Architecture
Device Tree Overlays
A device tree (DT) is a data structure of named nodes and properties that describe non-discoverable hardware. Operating systems, such as the Linux kernel used in Android, use DTs to support a wide range of hardware configurations used by Android-powered devices. Hardware vendors supply their own DT source files, which Linux then compiles into the Device Tree Blob (DTB) file used by the bootloader.

A device tree overlay (DTO) enables a central device tree blob (DTB) to be overlaid on the device tree. A bootloader using DTO can maintain the system-on-chip (SoC) DT and dynamically overlay a device-specific DT, adding nodes to the tree and making changes to properties in the existing tree.

This page details a typical bootloader workflow for loading a DT and provides a list of common DT terms. Other pages in this section describe how to implement bootloader support for DTO, how to compile, verify, and optimize your DTO implementation, and how to use multiple DTs. You can also get details on DTO syntax and required DTO/DTBO partition formatting.

Updates in Android 9 Release
In Android 9, the bootloader must not modify the properties defined in the device tree overlays before passing the unified device tree blob to the kernel.

Loading a device tree
Loading a device tree in bootloader involves building, partitioning, and running.


Figure 1. Typical implementation for loading device tree in bootloader.
To build:
Use the device tree compiler (dtc) to compile device tree source (.dts) into a device tree blob (.dtb), formatted as a flattened device tree.
Flash the .dtb file into a bootloader runtime-accessible location (detailed below).
To partition, determine a bootloader runtime-accessible and trusted location in flash memory to put .dtb. Example locations:
Boot Partition

Figure 2. Put .dtb in boot partition by appending to image.gz and passing as "kernel" to mkbootimg.
Unique Partition

Figure 3. Put .dtb in an unique partition (e.g. dtb partition).
To run:
Load .dtb from storage into memory.
Start kernel given the memory address of the loaded DT.
