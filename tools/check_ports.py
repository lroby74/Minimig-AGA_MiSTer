#!/usr/bin/env python3
"""Check that Verilog instantiations of the VHDL entities name real ports.

    python3 tools/check_ports.py

Quartus is the only thing that binds the two languages together, so a port
renamed on one side and not the other builds cleanly under ghdl and under
iverilog and then fails the day someone runs the fitter. This reads the entity
declarations out of the .vhd files and the named port connections out of every
Verilog instantiation of them, and reports a connection that names a port the
entity does not have.

VHDL is case insensitive and Quartus matches accordingly, so the comparison is
too. Ports left unconnected are listed but are not an error: an output may be
left open, and an input with a default in the entity may be as well.
"""
import io, os, re, sys, glob

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')


def entities(path):
    """{entity name: {port names}} for one VHDL file."""
    s = io.open(path, encoding='latin-1', errors='replace').read()
    out = {}
    for m in re.finditer(r'\bentity\s+(\w+)\s+is(.*?)\bend\s+(?:entity\s+)?\1?\s*;',
                         s, re.I | re.S):
        name, body = m.group(1), m.group(2)
        p = re.search(r'\bport\s*\(', body, re.I)
        if not p:
            continue
        ports = set()
        for line in body[p.end():].split('\n'):
            line = re.sub(r'--.*', '', line)
            d = re.match(r'\s*([A-Za-z_][\w, \t]*?)\s*:\s*(in|out|inout|buffer)\b',
                         line, re.I)
            if d:
                ports.update(n.strip().lower() for n in d.group(1).split(',') if n.strip())
        out[name.lower()] = (name, ports)
    return out


def instances(path, known):
    """(entity, instance name, {connected ports}) for each instantiation found."""
    s = io.open(path, encoding='utf-8', errors='replace').read()
    s = re.sub(r'//[^\n]*', '', s)
    s = re.sub(r'/\*.*?\*/', '', s, flags=re.S)
    for m in re.finditer(r'\b(\w+)\b((?:\s*#\s*\([^;]*?\))?)\s*(\w+)\s*\(', s):
        ent = m.group(1).lower()
        if ent not in known or m.group(3) in ('if', 'case', 'while', 'for'):
            continue
        depth, i = 1, m.end()
        while depth and i < len(s):
            depth += (s[i] == '(') - (s[i] == ')')
            i += 1
        body = s[m.end():i - 1]
        yield known[ent][0], m.group(3), \
            set(n.group(1).lower() for n in re.finditer(r'\.(\w+)\s*\(', body))


def main():
    known = {}
    for f in glob.glob(os.path.join(ROOT, 'rtl', '**', '*.vhd'), recursive=True):
        known.update(entities(f))
    if not known:
        print('no VHDL entities found', file=sys.stderr)
        return 1
    bad = 0
    seen = 0
    for f in sorted(glob.glob(os.path.join(ROOT, 'rtl', '**', '*.v'), recursive=True)
                    + glob.glob(os.path.join(ROOT, '*.sv'))):
        for ent, inst, used in instances(f, known):
            seen += 1
            ports = known[ent.lower()][1]
            wrong = sorted(used - ports)
            rel = os.path.relpath(f, ROOT)
            print('%s  %s %s  %d of %d ports connected' %
                  (rel, ent, inst, len(used & ports), len(ports)))
            if wrong:
                bad += 1
                print('    NOT ON THE ENTITY: %s' % ', '.join(wrong))
            open_ = sorted(ports - used)
            if open_:
                print('    left open: %s' % ', '.join(open_))
    print('\n%d instantiation(s) checked, %d with a port the entity does not have'
          % (seen, bad))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
