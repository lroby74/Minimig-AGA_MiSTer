# The Main_MiSTer side

The core's 68030 mode is picked by CPU type code `10` in the config byte the
firmware sends, with the clock in bits 7-6. Stock Main_MiSTer cannot ask for
it: the CPU menu shows that slot as `-----`, loading a config corrects the code
back to 68020, and `minimig_ConfigCPU` masks the byte to six bits so the clock
bits never leave the board. One commit fixes all three.

## Building it

    git clone https://github.com/lroby74/Main_MiSTer
    cd Main_MiSTer
    git checkout claude/model-opus-lrhvk4
    make

The CPU line then cycles through eight settings instead of four:

    68000 -> 68010 -> 68020 Fast -> 68020 ~14MHz
          -> 68030 25MHz -> 68030 40MHz -> 68030 50MHz -> 68030 Fast

Nothing else in the menu moves. D-Cache and the larger FastRAM sizes already
keyed off bit 1 of the CPU type, which code `10` has, so both follow the 68030
without being touched.

`68030_cpu_menu.patch` is the same commit as a file, for a checkout that is not
that fork:

    git am .../extra/main_mister/68030_cpu_menu.patch

It is a plain mbox, so `git am` keeps the message and the authorship.

## Keeping it in step with upstream

The branch is deliberately one commit sitting directly on upstream's master, so
catching up is a rebase and never a merge:

    git remote add upstream https://github.com/MiSTer-devel/Main_MiSTer
    git fetch upstream master
    git rebase upstream/master
    git push --force-with-lease

Three files are touched - `menu.cpp`, `support/minimig/minimig_config.cpp` and
`support/minimig/minimig_config.h` - and only in the Minimig CPU menu, so a
rebase conflicts only if upstream edits that menu itself. If it does, the
places to look are `config_cpu_msg`, the `cpu_steps` table in
`MENU_MINIMIG_CHIPSET2`, and `minimig_ConfigCPU`.

## One consequence worth knowing

Dropping the load-time correction of code `10` means a config that selects the
68030 now selects it. Loading such a config under a core that does not offer
the mode gives an undefined CPU - the same as asking any core for something it
does not have.
