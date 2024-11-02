# PacManTang - PacMan Arcade for Sipeed Tang FPGA Boards 


PacManTang is an open source project to recreate the PacMan Arcade with Sipeed Tang FPGA boards, including Sipeed [Tang Primer 25K](https://wiki.sipeed.com/hardware/en/tang/tang-primer-25k/primer-25k.html), [Tang Nano 20K](https://wiki.sipeed.com/hardware/en/tang/tang-nano-20k/nano-20k.html). Based on the work of [@herbaum](https://github.com/harbaum/Pacman-TangNano9k)

## Why another Pac-Man in HDL?

There are many Pac-Man implementations in HDL, especially the [great
version by MikeJ](https://www.fpgaarcade.com/kb/pacman/).  I wanted to
gain some experiences with the GoWin FPGAs and wanted to make use of
the HDMI output of the TangNano9K. So I wrote another Pac-Man using
[HDMI](https://github.com/hdl-util/hdmi).

Most existing versions recreate the original video and in a way that
outputs an upright 60hz signal with NTSC timing expecting the screen
to be mounted in portrait mode as it was in the original Arcade
machine. Such a signal can be converted to HDMI in landscape
format. But that needs a seperate frame buffer.

I wanted to implement the video to directly output a signal compatible
with modern screens. So the video logic implemented here does not work
like the original arcade machine. Instead it replaces the video logic
by something that outputs a double scanned signal with 576 lines
(576p@60hz).

By default the video is 1024x576p to nicely fit a 16:9 screen. The
game area is displayed centered with a dark blue border left and right.
The video can be configured to output a 4:3 video with a resolution
of 768x576p instead by commenting ``define WIDE` in line 4 of src/top.sv.

## ROMs

Since this project implements the hardware of the Pac-Man Arcade
machine it needs the original ROM files to run. These can
be obtained from the [Pac-Man (Midway)](https://www.bing.com/search?q=pacman+midway+arcade+rom) romset.

The ROMs need to be converted into HDL source files compatible with
the GoWin toolchain. This can either be done manually using the GoWin
IDE or via the [Python conversion tool](src/roms/bin2v.py) and [a shell script](src/roms/conv.sh).

|     ROM file    |     Contents    |   Verilog file    |     Module     | Depth | Width |
|-----------------|-----------------|-------------------|----------------|------:|------:|
| ```pacman.6e``` |   CPU ROM #1    | ```pacman_6e.v``` | pacman_6e      | 4096  |     8 |
| ```pacman.6f``` |   CPU ROM #2    | ```pacman_6f.v``` | pacman_6f      | 4096  |     8 |
| ```pacman.6h``` |   CPU ROM #3    | ```pacman_6h.v``` | pacman_6h      | 4096  |     8 |
| ```pacman.6j``` |   CPU ROM #4    | ```pacman_6j.v``` | pacman_6j      | 4096  |     8 |
| ```pacman.5e``` |   tile graphics | ```pacman_5e.v``` | pacman_5e      | 4096  |     8 |
| ```pacman.5f``` | sprite graphics | ```pacman_5f.v``` | pacman_5f      | 4096  |     8 |
| ```82s123.7f``` |   color palette | ```82s123_7f.v``` | prom_82s123_7f |    32 |     8 |
| ```82s126.4a``` |        colormap | ```82s126_4a.v``` | prom_82s126_4a |   256 |     4 |
| ```82s126.1m``` | audio wavetable | ```82s126_1m.v``` | prom_82s126_1m |   256 |     4 |
| ```82s126.3m``` | audio wavetable | ```82s126_3m.v``` | prom_82s126_3m |   256 |     4 |

The easiest way to convert these files is to place the ten ROM files
in the [src/roms](src/roms) directory and then run the
[shell script](src/roms/conv.sh).

## Getting the parts

You need either the Sipeed Tang Primer 25K or Tang Nano 20K FPGA board to run the latest NESTang.

* If you choose the Primer 25K, get the [main Primer 25K dock board](https://wiki.sipeed.com/hardware/en/tang/tang-primer-25k/primer-25k.html), [DVI PMod](https://wiki.sipeed.com/hardware/en/tang/tang-PMOD/FPGA_PMOD.html#PMOD_DVI), [TF Card PMod](https://wiki.sipeed.com/hardware/en/tang/tang-PMOD/FPGA_PMOD.html#PMOD_TF-CARD), [DS2x2 PMod](https://wiki.sipeed.com/hardware/en/tang/tang-PMOD/FPGA_PMOD.html#PMOD_DS2x2) and a [Tang SDRAM](https://wiki.sipeed.com/hardware/en/tang/tang-PMOD/FPGA_PMOD.html#TANG-40P-MODULE).
* For the Tang Nano 20K, we suggest the [Tang Nano 20K Retro Gaming Kit](https://www.amazon.com/GW2AR-18-Computer-Debugger-Multiple-Emulator/dp/B0C5XLBQ6C), as it contains the necessary controllers and adapters.

## Installation


## Gamepad

Sofar there's support for DualShock2, SNES and NES gamepads.

| Function |  Button  |
|----------|---------:|
| Up       |    Up    |
| Down     |    Dn    |
| Left     |  left    |
| Right    |  right   |
| Coin     |  select  |
| Start    |  start   |

## Development

If you want to generate the bitstream from source, see [Build Instructions](https://nand2mario.github.io/nestang-doc/dev/build_bitstream/). Make sure you use the Gowin IDE version 1.9.9 commercial (requires a free license).

[Usb_hid_host](https://github.com/nand2mario/usb_hid_host) was development so NESTang could support USB gamepads. Follow the link if you want to use it for your FPGA projects. It supports keyboards and mice too.


## Special Thanks

* [Pacman-TangNano9k](https://github.com/harbaum/Pacman-TangNano9k)
* [nestang](https://github.com/nand2mario/nestang)

fjpolo (`fjpolo at gmail.com`)

Since 2024.11
