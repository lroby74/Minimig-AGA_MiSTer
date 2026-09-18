# Minimig-AGA_MiSTer

This is a port of the minimig core to the [MiSTer board](https://github.com/MiSTer-devel).

[Minimig](http://en.wikipedia.org/wiki/Minimig) (short for Mini Amiga) is an open source re-implementation of an Amiga using a field-programmable gate array (FPGA). Original Minimig author is Dennis van Weeren.

[Amiga](http://en.wikipedia.org/wiki/Amiga_500) was - in my opinion - an amazing personal computer, announced around 1984, which - at the time - far surpassed any other personal computer on the market, with advanced graphic & sound capabilities, not to mention its great OS with preemptive multitasking capabilities.

The Minimig-MiSTer variant in this repository has been upgraded with [AGA chipset](http://en.wikipedia.org/wiki/Amiga_Advanced_Graphics_Architecture) capabilites, which allows it to emulate the latest Amiga models ([Amiga 1200](http://en.wikipedia.org/wiki/Amiga_1200)) and (partially) [Amiga CD32](http://en.wikipedia.org/wiki/Amiga_CD32)). Of course it also supports previous OCS/ECS Amigas like [Amiga 500](http://en.wikipedia.org/wiki/Amiga_500), [Amiga 600](http://en.wikipedia.org/wiki/Amiga_600) etc.

This version has been modified to add support for MiSTer Floppy, SCP and IPF support - see https://mister.robsmithdev.co.uk

## Core features supported

* Chipset variants : OCS, ECS, AGA, CD32, CDTV
* ChipRAM : 0.5MB - 2.0MB
* SlowRAM : 0.0MB - 1.5MB
* FastRAM : 0.0MB - 384MB
* CPU core : 68000, 68020, 68030 (no MMU, no FPU)
* Kickstart : 1.2, 1.3, 2.0, 3.0, 3.1, 3.1.4, 3.2 (256kB, 512kB & 1MB kickstart ROMs currently supported)
* HRTmon with custom registers mirror
* Floppy drives : 1-4 floppies (supports ADF floppy image format), with normal & turbo speeds
* Up to 4 IDE devices
* CDROM
* Video standard : PAL / NTSC
* Supports almost all OCS/ECS/AGA custom resolutions
* RTG with up to 1920x1080 and 1600x1200 resolutions
* Peripherals : USB keyboards, USB mice, USB gamepads
* Serial connection to Linux with ability to connect to Internet.
* Ethernet A2065.
* Shared folder for rapid file exchange between Linux and Amiga.
* MIDI: both MiSTer internal emulation and external through USER_IO port (MT32-pi and generic MIDI device)
* Akiko chunk to planar implementation
* Mouse with wheel.
* SCP and IPF files
* MiSTer Floppy Hardware

## Usage

### Presets

Supported presets for most common Amiga models. You need to place Kickstart ROMs into Games/Amiga folder:
* A500.rom (KS v1.3)
* A600.rom (KS v2.05)
* A1200.rom (KS v3.1)
* CD32.rom + CD32_ext.rom (KS v3.1) (see CD32 and CDTV section)
* CDTV.rom + CDTV.rom (KS v1.3) (see CD32 and CDTV section)

While Kickstart versions above are recommended as most used in corresponding configs, it's not limited to that.
For other more advanced configs and non-listed hardware, additional OSD options and configuration Load/Save are available.

### Screen adjustment
Adjustment is initiated from OSD menu. 
Keyboard control:
* Cursor keys - top/left corner.
* ALT+Cursor keys - bottom/right corner.
* Enter - finish and store position.
* Backspace - reset do default.
* Esc - cancel and finish.

Positions are saved in the configuration file. Up to 64 different resolutions can be adjusted.

### Shared folder

All required files (and sources) are in extra/MiSTer_share.lha

Amiga driver is based on Niklas Ekström [a314](https://github.com/niklasekstrom/a314) driver.

On Amiga:
- copy dummy.device to DEVS:
- copy MountList to DEVS: (or add content from MountList to existing file)
- copy MiSTerFileSystem to L:
- open CLI and type there: mount share:
- MiSTer drive will appear on main WB screen. If it will work, then you can add this command into user-startup file, and it will be mounted at every boot.

On Linux side the folder is "shared" inside Amiga folder.

### RTG

* install [Picasso96.lha](http://aminet.net/package/driver/video/Picasso96) Choose uaegfx while installing.
* remove uaegfx (or whatever driver you choose in install) from SYS:Devs/Monitors
* extract [MiSTer_RTG.lha](https://github.com/MiSTer-devel/Minimig-AGA_MiSTer/raw/MiSTer/extra/rtg_driver/MiSTer_RTG.lha) and copy content to SYS:
* reboot

New video modes will appear in ScreenMode preference. For more screen modes use Picasso96Mode preference (attn: it has awkward interface!)

**Note: RTG outputs to HDMI primarily as it uses scaler.**
If you want to see RTG video on VGA output, then set vga_scaler=1 in MiSTer.ini.
RTG is available only for 68020/68030 CPU.

### 68030 CPU

The 68030 mode is the 68020 core plus the 68030 supervisor register set: full 68030 CACR
(EI/FI/CEI/CI/IBE and ED/FD/CED/CD/DBE/WA), working instruction and data cache clear bits,
and readable CAAR/MSP/ISP. AmigaOS therefore identifies the CPU as a 68030 and drives both
caches through the normal `CacheControl()` path. There is no MMU and no FPU, so MMU tools
(MuForce, Enforcer, 68030.library setups) and FPU code will not run.

The CPU clock is selectable - 25, 40 and 50 MHz, the speeds real 68030 accelerator
cards were sold at - and what paces it is a per-instruction cycle model rather than a
clock divider.

Section 11 of the MC68030 User's Manual gives every instruction a head, a tail and an
instruction-cache-case time, and composes a stream of them by equation 11-1:

    CC1 + [CC2 - min(H2,T1)] + [CC3 - min(H3,T2)] + ...

so what an instruction costs depends on the one before it, and an instruction that
takes an effective address composes the two the same way. `rtl/cpu_cycles.v` implements
both equations against ROM images built straight from those tables by
`tools/m68k_timing`, and holds the CPU until each instruction has been paid for. The
budget is earned by a fractional accumulator at `4096 x f_cpu / f_sys`:

| setting | rate (PAL / NTSC) | CPU clock |
|---|---|---|
| `00` | 902 / 894 | 25 MHz |
| `01` | 1444 / 1430 | 40 MHz |
| `10` | 1804 / 1788 | 50 MHz |
| `11` | - | unthrottled |

Nothing in the ROMs is estimated: a form with no table row behind it is charged the
architectural minimum of two clocks instead of a made-up number, and the generator
reports its coverage. Four things take numbers that are not in the opcode - MOVEM's
register count, the bit that makes a long divide signed, which shape an indexed address
is in, and the iteration a DBcc loop runs out on - so the kernel brings out the word
after the opcode and a flag for the expiring iteration, and the model reads those. What the model
does not touch is the memory system: chip RAM and the custom registers stay on the
7 MHz bus, so chipset-bound code does not scale with this setting - as on real hardware.

`tools/m68k_timing/run_tb.sh` checks twenty instruction forms against the manual's own
numbers, and `tools/cpi/run_trace.sh` runs a thousand instructions captured from the
real kernel through both the RTL and an independent Python implementation of the same
equations. `tools/cpi/run_cpi.sh` measures what the core itself can sustain: with
zero-wait memory it is faster than a 68030 on nearly every instruction, the binding
form costing three cycles against two clocks, so all three settings have margin.

The cpu config byte from the HPS is `SSPCCCTT`: `TT` the CPU type
(`00`=68000, `01`=68010, `10`=68030, `11`=68020), `CCC` the cache config, `P` the
68020 stock-speed throttle, `SS` the 68030 speed above.

**Selecting it needs a firmware change as well.** Main_MiSTer's minimig CPU menu shows
code `10` as `-----`, corrects a config carrying it back to 68020 on load, and masks the
config byte to six bits so the two speed bits never leave the board. The patch that
fixes all three is in `extra/main_mister/68030_cpu_menu.patch`:

    git clone https://github.com/MiSTer-devel/Main_MiSTer
    cd Main_MiSTer
    git apply .../extra/main_mister/68030_cpu_menu.patch
    make

The CPU line then cycles through eight settings - 68000, 68010, 68020 Fast, 68020
~14MHz, and the 68030 at 25, 40, 50 MHz and unthrottled - with nothing else in the menu
moved.

### AGA chipset accuracy

AA put every horizontal comparator on 35 ns - a quarter of a lores pixel - and Minimig
compared at 140 ns, so the extra bits had nowhere to land. The display window and the
sprites now use them:

* **DIWHIGH** bits 4 and 3 for the window start and 12 and 11 for the stop, 70 ns and
  35 ns, cleared again by any write to DIWSTRT or DIWSTOP as on ECS Denise.
* **SPRxCTL** bits 4 and 3 for the sprite start, below the 140 ns bit 0 that OCS
  already had.

Both take the position match where it was always taken and delay it by those bits, so
nothing moves on OCS, on ECS, or on an AGA program that leaves them clear. BPLCON1's
eight-bit playfield scroll was already right.

Two bitplane DMA behaviours went in with them, both from `TODO`: a write to BPLxPT one
cycle before the matching BPLxDAT fetch goes nowhere, because the DMA channel has the
address a cycle ahead of the fetch; and a write to BPLxMOD one cycle before a modulo add
does not change that add, though it is still accepted for the next one.

* **HBSTRT/HBSTOP** bits 10, 9 and 8 for the programmable blanking, 140/70/35 ns under
  the 280 ns field ECS had. Only in effect with VARBEAMEN set in BEAMCON0.

`tools/aga/run_tb.sh` checks all of it - fifty-one cases against Commodore's own AA
chipset specification and the AGA register reference, both quoted in
`doc/amiga/aga/SOURCES.md`. The whole lot costs thirty-three ALMs and a hundred and
eighty-two flip-flops.

### IDE and CDROM
By default up to 2 IDE devices are supported. For Secondary Master/Slave devices, you have to install either IDEFix97 (shareware, WB3.1/3.9) or AtapiMagic (freeware, WB 3.1.4/3.2).
Removable/CD mode allows to hot swap CDs. Currently audio portion of CD isn't implemented (although playback commands should be accepted).

### How to make a new HDF (HDD Image)
Only plain/raw HDF images are supported. WinUAE Dynamic HDF and Sparse File HDF formats are not supported.

1) Create an empty HDF file of required size on PC (ideally fill it by 0 if possible).
2) Copy it to MiSTer
3) Mount it as HDF on OSD, and also mount some adf with HDToolBox (for example install3.2.adf from OS3.2)
4) Boot that ADF
5) go to HDToolBox, then Change Drive Type -> Define New -> Read Configuration. Then Ok, Ok. Then Save Changes to Drive.
6) Press Partition Drive. Optionally delete MDH1 partition, expand MDH0 to full drive. Rename MDH0 to standard DH0 name, mark it as Bootable. Then OK, then Save Changes to Drive.
7) Exit, reboot.
8) After booting you will see DH0:Uninitialized. Format it from Workbench menu. You can use Quick format option.
9) Install required OS.

### CD32 and CDTV

For quick CD32 and CDTV game start from OSD menu you need to place following files into Games/Amiga folder:
* CD32: CD32.rom (Kickstart main ROM) and CD32_ext.rom (Extended CD32 ROM). Only one version set exists: KS 3.1 r40.060 + ExtROM r40.60
* CDTV: CDTV.rom (Kickstart main ROM) and CDTV_ext.rom (Extended CDTV ROM). Any version should work.

Instead of ROM+ExtROM, combined 1MB ROM is supported (*_ext.rom not required).
* CD32.rom: CD32_ext.rom+CD32.rom (1MB total)
* CDTV.rom: CDTV_ext.rom+CDTV_ext.rom+CDTV.rom[+CDTV.rom] (1MB total)

Besides original CD32 and CDTV use for games, these HW add-ons can be used in AmigaOS/Workbench as a CD drive, leaving all 4 IDE drives for HDD use.
Note1: enable either CD32 or CDTV, not both.
Note2: remove CD0(CD1-CD9) supporting files from devs:DOSDrivers as CD is fully handled by ExtROM.
You have to use appropriate ROM/ExtROM from CD32/CDTV to let AmigaOS recognize CD drive. Tested in AmigaOS v3.2.
CDTV mode is preferred because appropriate updated ROM and ExtROM v3.2 for CDTV are included in AmigaOS 3.2 installation CD.
Besides original CDTV HW config, you can use up to Amiga 1200 config (68020 + AGA + 2MB ChipRAM + 384MB FastRAM and A1200 KS ROM).
CD32 official KS 3.1 set of ROMs also work with AmigaOS 3.2 (remember to use IDEFix to access HDD >4GB).

### MIDI
Supported internal MiSTer emulation and external devices such as MT32-pi or generic MIDI though USER_IO.
For MIDI-IN support through USER_IO set UART mode to None in OSD settings.

### Akiko
Chunk to planar engine of Akiko is supported. It requires SetAkiko util (from releases/WheelDriverAkiko.adf) to be executed.

### Mouse Wheel
To enable wheel support both WheelDriver and FreeWheel must be run from releases/WheelDriverAkiko.adf

### Software
To use the core, you will need a Kickstart ROM image file, which you can obtain by copying Kickstart ROM IC from your actual Amiga, or by buying an [Amiga Forever](http://www.amigaforever.com/) software pack. The Kickstart image should be placed on the root of the SD card with the name KICK.ROM. Minimig also supports the [AROS](http://aros.sourceforge.net/) Kickstart ROM replacement.

The Minimig can read any ADF floppy images you place on the SD card. I recommend at least Workbench 1.3 or 3.1 (AmigaOS), some of the Amigas great games (I recommend Ruff'n'Tumble) or some of the amazing demos from the vast Amiga demoscene (like State of the Art from Spaceballs).

The Minimig can also use HDF harddisk images, which can be created with [WinUAE](http://www.winuae.net/).

### Recommended minimig config

* for ECS games / demos : CPU = 68000, Turbo=NONE, Chipset=ECS, ChipRAM=0.5MB, slowRAM=0.5MB, Kickstart 1.3
* for AGA games / demos : CPU = 68020, Turbo=NONE, Chipset=AGA, ChipRAM=2MB, SlowRAM=0MB, FastRAM=384MB, Kickstart 3.1

### Controlling minimig

Keyboard special keys:

* F12         - OSD menu
* F11         - start monitor (HRTmon) if HRTmon is enabled in OSD menu (otherwise F11 is the Amiga HELP key)
* ScrollLock  - toggle keyoard only / mouse / joystick 1 / joystick 2 emulation on the keyboard (direction keys + LCTRL)


## Sources

This sourcecode is based on Rok Krajnc project ([minimig-de1](https://github.com/rkrajnc/minimig-de1)).

Original Minimig sources from Dennis van Weeren with updates by Jakub Bednarski are published on [Google Code](http://code.google.com/p/minimig/).

Some Minimig updates are published on the [Minimig Discussion Forum](http://www.minimig.net/), done by Sascha Boing.

ARM firmware updates and Minimig-tc64 port changes by Christian Vogelsang ([minimig_tc64](https://github.com/cnvogelg/minimig_tc64)) and A.M. Robinson ([minimig_tc64](https://github.com/robinsonb5/minimig_tc64)).

MiSTer project by Sorgelig ([MiSTer](https://github.com/MiSTer-devel)).

TG68K.C core by Tobias Gubener.


## Links & more info

My page [somuch.guru](http://somuch.guru/).

Further info about Minimig can be found on the [Minimig Discussion Forum](http://www.minimig.net/).

MiSTer board support & other cores on the [MiSTer Project Page](https://github.com/MiSTer-devel).


## License

Copyright © 2011 - 2016 Rok Krajnc (rok.krajnc@gmail.com)

Copyright © 2005 - 2015 Dennis van Weeren, Jakub Bednarski, Sascha Boing, A.M. Robinson, Tobias Gubener, Till Harbaum

Copyright © 2017 - 2020 Sorgelig (mister.devel@gmail.com)

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
