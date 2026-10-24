import re, sys, difflib, json
src_path, dis_path, out_path = sys.argv[1:4]
src = open(src_path).read().split('\n')
dis = open(dis_path).read().split('\n')
def equs(lines):
    d = {}
    for l in lines:
        l = re.sub(r'^[0-9A-F ]{4}\|', '', l)
        m = re.match(r'^\s*([A-Za-z_][A-Za-z_0-9]*)\s+(?:EQU|=)\s+(\S+)', l) or re.match(r'^\s*([A-Za-z_][A-Za-z_0-9]*)\s*=\s*(\S+)', l)
        if m:
            v = m.group(2)
            v = int(v[1:], 16) if v.startswith('$') else int(v[1:], 2) if v.startswith('%') else int(v)
            d[m.group(1)] = v
    return d
def labels(lines):
    return set(m.group(1) for l in lines for m in [re.match(r'^(?:\s*\|)?\s*([A-Za-z_.][A-Za-z_0-9]*):', re.sub(r'^[0-9A-F ]{4}\|', '', l))] if m)
SYM = {}
LAB = set()
def norm(s):
    s = s.split(';')[0].strip()
    s = re.sub(r'\s+', ' ', s)
    def rep(m):
        w = m.group(0)
        if w in LAB: return 'L'
        if w in SYM: return '$%X' % SYM[w]
        return w
    s = re.sub(r'(?<![#$%\w])[A-Za-z_.][A-Za-z_0-9]*', rep, s, )
    s = re.sub(r'#%([01]+)', lambda m: '#$%02X' % int(m.group(1), 2), s)
    s = re.sub(r'\$0*([0-9A-Fa-f]+)', lambda m: '$%X' % int(m.group(1), 16), s)
    return s
SYM.update(equs(dis)); SYM.update(equs(src)); LAB |= labels(dis) | labels(src)
for k in ['acc','b','c','psw','sp','trl','trh','ext','b0','b1','b2','b3']: SYM.pop(k, None)
dkeys, daddr = [], []
for l in dis:
    m = re.match(r'^([0-9A-F]{4})\|\s+(.*)$', l)
    if m and not m.group(2).startswith('.'):
        k = norm(m.group(2))
        if k:
            dkeys.append(k); daddr.append(int(m.group(1), 16))
skeys, sidx = [], []
for i, l in enumerate(src):
    if re.match(r'^\s+[a-z]', l) and not re.match(r'^\s*\.', l):
        k = norm(l)
        if k:
            skeys.append(k); sidx.append(i)
sm = difflib.SequenceMatcher(None, skeys, dkeys, autojunk=False)
addr = {}
for a, b, n in sm.get_matching_blocks():
    for j in range(n):
        addr[sidx[a+j]] = daddr[b+j]
unmatched = [sidx[i] for i in range(len(skeys)) if sidx[i] not in addr]
bad = 0
for i, l in enumerate(src):
    m = re.match(r'^label_([0-9A-F]{4}):', l)
    if m:
        for k in range(i+1, min(i+6, len(src))):
            if k in addr:
                if addr[k] != int(m.group(1), 16):
                    bad += 1; print('label mismatch', l, hex(addr[k]), file=sys.stderr)
                break
print('matched', len(addr), 'unmatched', len(unmatched), 'label mismatches', bad, file=sys.stderr)
for u in unmatched[:40]:
    print('UNMATCHED', u+1, src[u], file=sys.stderr)
with open(out_path, 'w') as f:
    for i, l in enumerate(src):
        a = ('%04X' % addr[i]) if i in addr else '    '
        f.write('%5d %s| %s\n' % (i+1, a, l))
