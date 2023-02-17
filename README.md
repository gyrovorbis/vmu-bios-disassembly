# Disassembly and Analysis of the American VMU BIOS (v1.05)
This repo seeks to provide a common entry point to the disassembled Sega Dreamcast VMU BIOS with comments and analysis on its functionality. It is my hope that we can discover any of its remaning secrets by analyzing these files and contributing our comments/findings.

Some useful things we've already discovered:
- The VMU is still polling the buttons for input state and is reporting them back to the MAPLE protocol when attached to the DC
- The 6Mhz CF oscillator crystal, which is enabled when the VMU is plugged into the controller, is most likely accessible in GAME modes
- You can jump past flash read/write protection regions in the firmware calls and access flash anywhere


