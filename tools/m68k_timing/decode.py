#!/usr/bin/env python3
"""Map a 68k opcode onto the row of the Motorola timing tables that describes it.

decode(op) -> (section, label, ea_class) or None

`op` is a 16-bit opcode with its low three bits (always a register number, and
never a term in the timing) zeroed. A form this table does not cover returns
None, and the generator emits an entry with the valid bit clear so the RTL
falls back to the averaged divider rather than to an invented number.

ea_class says which effective-address table to add on top, and comes from the
footnote markers of the 68020 manual, whose legend reads:
    *   Add Fetch Effective Address Time          -> FEA
    **  Add Fetch Immediate Effective Address Time -> FIEA
plus the two tables the prose names rather than marks: Calculate Effective
Address for the instructions that only compute an address (LEA, PEA), and
Jump Effective Address for JMP and JSR.
"""

NONE, FEA, FIEA, CEA, CIEA, JEA = range(6)

def b(op, hi, lo):
    return (op >> lo) & ((1 << (hi - lo + 1)) - 1)

def decode(op):
    mode, reg = b(op, 5, 3), b(op, 2, 0)
    mem = mode >= 2
    line = b(op, 15, 12)
    sz = b(op, 7, 6)

    # ---- 0000: immediate, bit ops, MOVEP, CMP2/CHK2, CAS, MOVES ----------
    if line == 0x0:
        imm = {0x0: 'ORI', 0x1: 'ANDI', 0x2: 'SUBI', 0x3: 'ADDI',
               0x5: 'EORI', 0x6: 'CMPI'}.get(b(op, 11, 9))
        if b(op, 8, 8) == 0 and imm and sz != 3:
            if mode == 7 and reg == 4 and imm in ('ORI', 'ANDI', 'EORI'):
                return ('ctrl', f'{imm} to {"CCR" if sz == 0 else "SR"}', NONE)
            if imm == 'CMPI':
                return ('immarith', 'CMPI #<data>,Mem' if mem else 'CMPI #<data>,Dn', FIEA)
            return ('immarith', f'{imm} #<data>,' + ('Mem' if mem else 'Dn'), FIEA)
        if b(op, 11, 9) == 4 and b(op, 8, 8) == 0:                 # static bit ops
            n = {0: 'BTST', 1: 'BCHG', 2: 'BCLR', 3: 'BSET'}[sz]
            return ('bit', f'{n} #<data>,' + ('Mem' if mem else 'Dn'), FEA if mem else NONE)
        if b(op, 8, 8) == 1 and mode == 1:                          # MOVEP
            long_, to_mem = sz in (1, 3), sz in (2, 3)
            w = 'L' if long_ else 'W'
            if to_mem and not long_:
                # the 68030 table's MOVEP.W Dn,(d16,An) row is merged into the
                # MOVEM row by the PDF text layer, so it has no row to cite
                return None
            return ('spmove', f'MOVEP.{w} Dn,(d16,An)' if to_mem
                    else f'MOVEP.{w} (d16,An),Dn', NONE)
        if b(op, 8, 8) == 1:                                        # dynamic bit ops
            n = {0: 'BTST', 1: 'BCHG', 2: 'BCLR', 3: 'BSET'}[sz]
            return ('bit', f'{n} Dn,' + ('Mem' if mem else 'Dn'), FEA if mem else NONE)
        return None

    # ---- 0001/0010/0011: MOVE ------------------------------------------
    if line in (0x1, 0x2, 0x3):
        dmode, dreg = b(op, 8, 6), b(op, 11, 9)
        src_is_reg = mode in (0, 1)
        if dmode == 1:  return ('move', 'MOVE EA,An', FEA)
        if dmode == 0:  return ('move', 'MOVE EA,Dn', FEA)
        if dmode == 2:  return ('move', 'MOVE Rn,(An)'  if src_is_reg else 'MOVE SOURCE, (An)', FEA)
        if dmode == 3:  return ('move', 'MOVE Rn,(An)+' if src_is_reg else 'MOVE SOURCE, (An)+', FEA)
        if dmode == 4:  return ('move', 'MOVE Rn,-(An)' if src_is_reg else 'MOVE SOURCE, -(An)', FEA)
        if dmode == 5:  return ('move', 'MOVE EA, (d16,An)', FEA)
        if dmode == 6:  return ('move', 'MOVE EA, (d8,An,Xn)', FEA)
        if dmode == 7 and dreg == 0: return ('move', 'MOVE EA,XXX.W', FEA)
        if dmode == 7 and dreg == 1: return ('move', 'MOVE EA,XXX.L', FEA)
        return None

    # ---- 0100: the miscellaneous line ------------------------------------
    if line == 0x4:
        one = {0: 'NEGX', 1: 'CLR', 2: 'NEG', 3: 'NOT'}.get(b(op, 11, 9))
        if one and sz != 3 and b(op, 8, 8) == 0:
            return ('single', f'{one} ' + ('Mem' if mem else 'Dn'), FEA if mem else NONE)
        if sz == 3 and b(op, 8, 8) == 0 and b(op, 11, 9) in (0, 1, 2, 3):
            sr = {0: 'MOVE SR,', 1: 'MOVE CCR,', 2: 'MOVE %s,CCR', 3: 'MOVE %s,SR'}[b(op, 11, 9)]
            if b(op, 11, 9) in (0, 1):
                return ('spmove', sr + ('Mem' if mem else 'Dn'), FEA if mem else NONE)
            if b(op, 11, 9) == 3:                       # MOVE <ea>,SR
                return ('spmove', 'MOVE EA,SR', FEA if mem else NONE)
            return ('spmove', 'MOVE Dn,CCR' if mode == 0 else 'MOVE EA,CCR',
                    FEA if mem else NONE)
        if op & 0xFFC0 == 0x4800: return ('single', 'NBCD Dn', FEA if mem else NONE)
        if op & 0xFFF8 == 0x4840: return ('spmove', 'SWAP Dn', NONE)
        if op & 0xFFC0 == 0x4840: return ('ctrl', 'PEA', CEA)
        if op & 0xFFF8 in (0x4880, 0x48C0, 0x49C0):
            return ('single', 'EXT Dn', NONE)                            # EXT.W/.L, EXTB.L
        if op & 0xFB80 == 0x4880:
            # MOVEM's register count lives in the extension word, outside
            # this ROM's index, so rtl/cpu_cycles.v counts the mask and builds
            # the entry itself. Nothing for the ROM to hold.
            return None
        if op & 0xFFC0 == 0x4C00: return ('arith', 'MULU.L EA,Dn', FIEA)
        if op & 0xFFC0 == 0x4C40:
            # The signed/unsigned bit is in the extension word, out of index.
            # DIVU.L is 78 clocks and DIVS.L 90; the entry carries the 78 and
            # rtl/cpu_cycles.v adds the 12 when it sees the bit set.
            return ('arith', 'DIVU.L EA,Dn', FIEA)
        if op & 0xFFC0 == 0x4A00 or op & 0xFFC0 == 0x4A40 or op & 0xFFC0 == 0x4A80:
            return ('single', 'TST ' + ('Mem' if mem else 'Dn'), FEA if mem else NONE)
        if op & 0xFFC0 == 0x4AC0:
            return ('single', 'TAS ' + ('Mem' if mem else 'Dn'), FEA if mem else NONE)
        if op == 0x4AFC: return ('exc', 'Illegal Instruction', NONE)
        if op & 0xFFF0 == 0x4E40: return ('exc', 'TRAP #n', NONE)
        if op & 0xFFF8 == 0x4E50: return ('ctrl', 'LINK.W', NONE)
        if op & 0xFFF8 == 0x4808: return ('ctrl', 'LINK.L', NONE)
        if op & 0xFFF8 == 0x4E58: return ('ctrl', 'UNLK', NONE)
        if op & 0xFFF8 == 0x4848: return ('exc', 'BKPT', NONE)
        if op & 0xFFF0 == 0x4E60: return ('spmove', 'MOVE USP,An' if op & 8 else 'MOVE An,USP', NONE)
        if op == 0x4E70: return ('exc', 'RESET Instruction', NONE)
        if op == 0x4E71: return ('ctrl', 'NOP', NONE)
        if op == 0x4E72: return ('exc', 'STOP', NONE)
        if op == 0x4E73: return ('saverest', 'RTE (Normal Four Word)', NONE)
        if op == 0x4E74: return ('ctrl', 'RTD', NONE)
        if op == 0x4E75: return ('ctrl', 'RTS', NONE)
        if op == 0x4E76: return ('exc', 'TRAPV (No Trap)', NONE)
        if op == 0x4E77: return ('ctrl', 'RTR', NONE)
        if op & 0xFFFE == 0x4E7A: return ('spmove', 'MOVEC Cr,Rn' if op & 1 == 0 else 'MOVEC Rn,Cr-A', NONE)
        if op & 0xFFC0 == 0x4E80: return ('ctrl', 'JSR', JEA)
        if op & 0xFFC0 == 0x4EC0: return ('ctrl', 'JMP', JEA)
        if op & 0xF1C0 == 0x41C0: return ('ctrl', 'LEA', CEA)
        if op & 0xF1C0 in (0x4180, 0x4100):
            return ('ctrl', 'CHK EA,Dn (No Exception)' if mem else 'CHK Dn,Dn (No Exception)',
                    FEA if mem else NONE)
        return None

    # ---- 0101: ADDQ/SUBQ, Scc, DBcc, TRAPcc -----------------------------
    if line == 0x5:
        if sz != 3:
            n = 'SUBQ' if b(op, 8, 8) else 'ADDQ'
            return ('immarith', f'{n} #<data>,' + ('Mem' if mem else 'Rn'), FEA if mem else NONE)
        if mode == 1:
            return ('bcc', 'DBcc (cc = False, Count Not Expired)', NONE)
        if mode == 7 and reg in (2, 3, 4):
            return ('exc', 'TRAPcc (No Trap)', NONE)
        return ('single', 'Scc ' + ('Mem' if mem else 'Dn'), FEA if mem else NONE)

    # ---- 0110: Bcc / BSR / BRA ------------------------------------------
    if line == 0x6:
        if b(op, 11, 8) == 1: return ('ctrl', 'BSR', NONE)
        return ('bcc', 'Bcc (Taken)', NONE)

    # ---- 0111: MOVEQ -----------------------------------------------------
    if line == 0x7:
        return ('immarith', 'MOVEQ #<data>,Dn', NONE) if b(op, 8, 8) == 0 else None

    # ---- 1000/1001/1011/1100/1101: the ALU lines ------------------------
    if line in (0x8, 0x9, 0xB, 0xC, 0xD):
        opmode = b(op, 8, 6)
        if line == 0x8:
            if opmode == 3: return ('arith', 'DIVU.W Dn,Dn' if mode == 0 else 'DIVU.W EA,Dn', FEA if mem else NONE)
            if opmode == 7: return ('arith', 'DIVS.W Dn,Dn' if mode == 0 else 'DIVS.W EA,Dn', FEA if mem else NONE)
            if opmode == 4 and b(op, 5, 4) == 0:
                return ('bcd', 'SBCD Dn,Dn' if b(op, 3, 3) == 0 else 'SBCD -(An),-(An)', NONE)
            if opmode == 5 and b(op, 5, 4) == 0:
                return ('bcd', 'PACK Dn,Dn,#<data>' if b(op, 3, 3) == 0 else 'PACK -(An),-(An),#<data>', NONE)
            if opmode == 6 and b(op, 5, 4) == 0:
                return ('bcd', 'UNPK Dn,Dn,#<data>' if b(op, 3, 3) == 0 else 'UNPK -(An),-(An),#<data>', NONE)
            return _alu('OR', op, mode, mem)
        if line == 0xC:
            if opmode == 3: return ('arith', 'MULU.W EA,Dn', FEA if mem else NONE)
            if opmode == 7: return ('arith', 'MULS.W EA,Dn', FEA if mem else NONE)
            if opmode == 4 and b(op, 5, 4) == 0:
                return ('bcd', 'ABCD Dn,Dn' if b(op, 3, 3) == 0 else 'ABCD -(An),-(An)', NONE)
            if opmode in (5, 6) and b(op, 5, 3) in (0, 1):
                return ('spmove', 'EXG Ry,Rx', NONE)
            return _alu('AND', op, mode, mem)
        if line in (0x9, 0xD):
            n = 'SUB' if line == 0x9 else 'ADD'
            if opmode == 3:
                if mode in (0, 1): return ('arith', f'{n}A.W Rn,An', NONE)
                # the 68030 table writes the word form as ADD.W EA,An
                return ('arith', f'{n}.W EA,An' if n == 'ADD' else f'{n}A.W EA,An', FEA)
            if opmode == 7: return ('arith', f'{n}A.L Rn,An' if mode in (0, 1) else f'{n}A.L EA,An', FEA if mem else NONE)
            if opmode >= 4 and b(op, 5, 4) == 0:
                x = f'{n}X'
                if b(op, 3, 3) == 0: return ('bcd', f'{x} Dn,Dn', NONE)
                return ('bcd', 'SUBX -(An)' if n == 'SUB' else 'ADDX -(An),-(An)', NONE)
            return _alu(n, op, mode, mem)
        if line == 0xB:
            if opmode == 3: return ('arith', 'CMPA Rn,An' if mode in (0, 1) else 'CMPA EA,An', FEA if mem else NONE)
            if opmode == 7: return ('arith', 'CMPA Rn,An' if mode in (0, 1) else 'CMPA EA,An', FEA if mem else NONE)
            if opmode < 3:
                return ('arith', 'CMP Rn,Dn' if mode in (0, 1) else 'CMP EA,Dn', FEA if mem else NONE)
            if mode == 1: return ('bcd', 'CMPM (An)+,(An)+', NONE)
            return ('arith', 'EOR Dn,Dn' if mode == 0 else 'EOR Dn,EA', FEA if mem else NONE)

    # ---- 1110: shift / rotate and the bit field group --------------------
    if line == 0xE:
        if sz != 3:
            left, ir, typ = b(op, 8, 8), b(op, 5, 5), b(op, 4, 3)
            src = 'Dx,Dy' if ir else '#<data>,Dy'
            if typ == 0: return ('shift', ('ASL ' if left else 'ASR ') + src, NONE)
            if typ == 1: return ('shift', 'LSd ' + src, NONE)
            if typ == 2: return ('shift', 'ROXd Dn', NONE)
            return ('shift', 'ROd ' + src, NONE)
        kind = b(op, 11, 9)
        if b(op, 11, 11) == 0:
            typ = {0: 'ASd', 1: 'LSd', 2: 'ROXd', 3: 'ROd'}[kind & 3]
            name = ('ASL' if b(op, 8, 8) else 'ASR') if (kind & 3) == 0 else typ
            return ('shift', f'{name} Mem by 1', FEA)
        bf = {0x8: 'BFTST', 0x9: 'BFEXTU', 0xA: 'BFCHG', 0xB: 'BFEXTS',
              0xC: 'BFCLR', 0xD: 'BFFFO', 0xE: 'BFSET', 0xF: 'BFINS'}.get(b(op, 11, 8))
        if bf:
            return ('bitfield', f'{bf} Mem (<5 Bytes)' if mem else f'{bf} Dn', CEA if mem else NONE)
        return None

    if line == 0xA: return ('exc', 'A-Line Trap', NONE)
    if line == 0xF: return ('exc', 'F-Line Trap', NONE)
    return None


def _alu(n, op, mode, mem):
    """ADD/SUB/AND/OR with a data register on one side."""
    to_ea = b(op, 8, 8) == 1
    if to_ea:
        return ('arith', f'{n} Dn,EA' if mem else f'{n} Dn,Dn', FEA if mem else NONE)
    if mode in (0, 1):
        return ('arith', f'{n} Rn,Dn' if n in ('ADD', 'SUB') else f'{n} Dn,Dn', NONE)
    return ('arith', f'{n} EA,Dn', FEA)
