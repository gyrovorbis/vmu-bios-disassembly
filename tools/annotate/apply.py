import re, sys, collections
SRC, ANNOT_MAP, PDIS, ANN, OUT = sys.argv[1:6]

src = open(SRC).read().split('\n')
if src and src[-1] == '':
    src.pop()

addr_of_line = {}
for l in open(ANNOT_MAP):
    m = re.match(r'^\s*(\d+) (.{4})\|', l)
    if m and m.group(2).strip():
        addr_of_line[int(m.group(1)) - 1] = int(m.group(2), 16)

pdis = []
for l in open(PDIS).read().split('\n'):
    m = re.match(r'^([0-9A-F]{4})\|\s*(.*)$', l)
    if m:
        pdis.append((int(m.group(1), 16), m.group(2)))
        continue
    m = re.match(r'^\s*\|\s*(label_[0-9A-F]{4}):', l)
    if m:
        pdis.append((None, m.group(1) + ':'))
size_of = {}
addrs = [a for a, _ in pdis if a is not None]
for i in range(len(addrs) - 1):
    size_of[addrs[i]] = addrs[i + 1] - addrs[i]


src_label_at = {}
for _i, _l in enumerate(src):
    _m = re.match(r'^\s*([A-Za-z_][A-Za-z_0-9]*):', _l)
    if _m:
        for _j in range(_i + 1, min(_i + 8, len(src))):
            if _j in addr_of_line:
                src_label_at[addr_of_line[_j]] = _m.group(1)
                break


def fix_label_refs(t):
    def rep(m):
        a = int(m.group(1), 16)
        return src_label_at.get(a, m.group(0))
    return re.sub(r'label_([0-9A-F]{4})', rep, t)


def pdis_range(lo, hi):
    out = []
    for i, (a, t) in enumerate(pdis):
        if a is None:
            nxt = next((b for b, _ in pdis[i + 1:] if b is not None), None)
            if nxt is not None and lo <= nxt < hi:
                out.append((None, t))
        elif lo <= a < hi:
            t = re.sub(r'\s*; Arrived from:.*$', '', t)
            if t.startswith('.byte'):
                t = re.sub(r'\s*;.*$', '', t)
            t = t.replace('mplsw', 'mapletxrxctl').replace('mplsta', 'maplesta').replace('mplrst', 'maplerst')
            out.append((a, '  ' + fix_label_refs(t)))
    return out


# ---------------------------------------------------------------- annotations
renames = {}
headers = collections.defaultdict(list)
eol = {}
pre_addr = collections.defaultdict(list)
pre_line = collections.defaultdict(list)
eol_line = {}
new_labels = {}
ram0 = {}
ram1 = {}
sym_alias = {}
replace_blocks = []
entry_bank = {}
cur = None
for raw in open(ANN).read().split('\n'):
    if raw.startswith('|'):
        txt = raw[1:].rstrip()
        if txt.startswith(' '):
            txt = txt[1:]
        cur.append(txt)
        continue
    l = raw.strip()
    if not l or l.startswith('//'):
        cur = None
        continue
    if l.startswith('@'):
        old, new = l[1:].split(None, 1)
        renames[old] = new.strip()
        cur = headers[old]
    elif l.startswith('='):
        a, txt = l[1:].split(None, 1)
        eol[int(a, 16)] = txt
        cur = None
    elif l.startswith('>'):
        cur = pre_addr[int(l[1:].strip(), 16)]
    elif l.startswith('#'):
        cur = pre_line[int(l[1:].strip()) - 1]
    elif l.startswith('~'):
        a, txt = l[1:].split(None, 1)
        eol_line[int(a) - 1] = txt
        cur = None
    elif l.startswith('+'):
        name, a = l[1:].split()
        new_labels[int(a, 16)] = name
        cur = headers[name]
    elif l.startswith('$0'):
        a, name = l[2:].split()
        ram0[int(a, 16)] = name
        cur = None
    elif l.startswith('$1'):
        a, name = l[2:].split()
        ram1[int(a, 16)] = name
        cur = None
    elif l.startswith('^'):
        nm, b = l[1:].split()
        entry_bank[nm] = None if b == '?' else int(b)
        cur = None
    elif l.startswith('%'):
        a, b = l[1:].split()
        sym_alias[a] = int(b, 16)
        cur = None
    elif l.startswith('!'):
        parts = l[1:].split()
        if parts[2] == 'lit':
            lit = []
            replace_blocks.append((int(parts[0]) - 1, int(parts[1]) - 1, None, lit))
            cur = lit
        else:
            f, t, lo, hi = parts
            replace_blocks.append((int(f) - 1, int(t) - 1, int(lo, 16), int(hi, 16)))
            cur = None
    else:
        raise SystemExit('bad annotation line: ' + raw)

# ---------------------------------------------------------------- build line list
# each item: dict(text, addr, orig)
lines = []
rb = sorted(replace_blocks, key=lambda b: b[0])
i = 0
while i < len(src):
    blk = next((b for b in rb if b[0] == i), None)
    if blk:
        f, t, lo, hi = blk
        if lo is None:
            for txt in hi:
                m = re.match(r'^@([0-9A-F]{4})\s(.*)$', txt)
                if m:
                    _a = int(m.group(1), 16)
                    size_of.setdefault(_a, 3)
                    lines.append(dict(text=m.group(2), addr=_a, orig=None))
                else:
                    lines.append(dict(text=txt, addr=None, orig=None))
        else:
            for a, txt in pdis_range(lo, hi):
                lines.append(dict(text=txt, addr=a, orig=None))
        i = t + 1
        continue
    lines.append(dict(text=src[i], addr=addr_of_line.get(i), orig=i))
    i += 1

# manual line injections for E000 jump table are done by replace blocks with custom text
# (handled by special marker in annotation via pdis-less blocks is not needed)

# data-line addresses: propagate from previous instruction
last_end = None
for it in lines:
    t = it['text']
    if it['addr'] is not None:
        last_end = it['addr'] + size_of.get(it['addr'], 0)
        continue
    m = re.match(r'^\s*\.org\s+\$?([0-9A-Fa-f]+)', t)
    if m:
        last_end = int(m.group(1), 16)
        continue
    if last_end is None:
        continue
    m = re.match(r'^\s*\.byte\s+(.*)$', t.split(';')[0])
    if m:
        it['daddr'] = last_end
        last_end += len([x for x in m.group(1).split(',') if x.strip()])
        continue
    m = re.match(r'^\s*\.string\s+(\d+)', t)
    if m:
        it['daddr'] = last_end
        last_end += int(m.group(1))
        continue
    if re.match(r'^\s*[A-Za-z_.][A-Za-z_0-9]*:', t):
        it['daddr'] = last_end

split = []
for it in lines:
    m = re.match(r'^(\s*)\.byte\s+(.*)$', it['text'].split(';')[0])
    if it.get('daddr') is not None and m:
        items = [x.strip() for x in m.group(2).split(',') if x.strip()]
        cuts = sorted(a - it['daddr'] for a in new_labels if it['daddr'] < a < it['daddr'] + len(items))
        if cuts:
            prev = 0
            for c in cuts + [len(items)]:
                split.append(dict(text=m.group(1) + '.byte ' + ', '.join(items[prev:c]), addr=None,
                                  orig=it['orig'] if prev == 0 else None, daddr=it['daddr'] + prev))
                prev = c
            continue
    split.append(it)
lines = split

# insert new labels for data / code addresses
out = []
placed = set()
for it in lines:
    a = it['addr'] if it['addr'] is not None else it.get('daddr')
    if a is not None and a in new_labels and a not in placed and (it['addr'] is not None or re.match(r'^\s*\.(byte|string)', it['text'])):
        out.append(dict(text=new_labels[a] + ':', addr=None, orig=None, newlabel=True))
        placed.add(a)
    out.append(it)
lines = out
missing = set(new_labels) - placed
if missing:
    print('WARNING new labels not placed:', [hex(x) for x in missing], file=sys.stderr)

# ---------------------------------------------------------------- labels & scopes
LABEL_RE = re.compile(r'^\s*([A-Za-z_][A-Za-z_0-9]*):')
label_idx = {}
for k, it in enumerate(lines):
    m = LABEL_RE.match(it['text'])
    if m:
        label_idx[m.group(1)] = k
        it['label'] = m.group(1)
        it['text'] = re.sub(r'^\s*', '', it['text'])

CALL_OPS = ('call', 'callf', 'callr')
refs = collections.defaultdict(list)
for k, it in enumerate(lines):
    code = it['text'].split(';')[0]
    m = re.match(r'^\s+([a-z0-9]+)\s+(.*)$', code)
    if not m:
        continue
    op, args = m.groups()
    for w in re.findall(r'[A-Za-z_][A-Za-z_0-9]*', args):
        if w in label_idx:
            refs[w].append((k, op))

is_global = {}
for name in label_idx:
    r = renames.get(name)
    if r is not None:
        is_global[name] = not r.startswith('.')
    else:
        is_global[name] = any(op in CALL_OPS for _, op in refs[name]) or name in ('label_0200',)
    if not refs[name] and name not in renames:
        is_global[name] = True


def scope_of(k):
    best = None
    for name, idx in label_idx.items():
        if is_global[name] and idx <= k and (best is None or idx > label_idx[best]):
            best = name
    return best


changed = True
sorted_globals = None
while changed:
    changed = False
    gl = sorted((idx, n) for n, idx in label_idx.items() if is_global[n])
    import bisect
    gidx = [g[0] for g in gl]

    def scope(k):
        p = bisect.bisect_right(gidx, k) - 1
        return gl[p][1] if p >= 0 else None
    for name, idx in label_idx.items():
        if is_global[name]:
            continue
        sc = scope(idx)
        for k, _ in refs[name]:
            if scope(k) != sc:
                is_global[name] = True
                changed = True
                break


def next_instr(idx):
    for it in lines[idx + 1:]:
        t = it['text'].split(';')[0].strip()
        if t and not LABEL_RE.match(it['text']) and not t.startswith('.'):
            return t
    return ''


final = {}
gl = sorted((idx, n) for n, idx in label_idx.items() if is_global[n])
gidx = [g[0] for g in gl]


def scope(k):
    p = bisect.bisect_right(gidx, k) - 1
    return gl[p][1] if p >= 0 else None


used = collections.defaultdict(set)
for name in label_idx:
    if is_global[name]:
        r = renames.get(name, name)
        if r.startswith('.'):
            k0 = label_idx[name] - 1
            while k0 >= 0 and not (lines[k0].get('label') and is_global[lines[k0]['label']] and not renames.get(lines[k0]['label'], '').startswith('.')):
                k0 -= 1
            sc = renames.get(lines[k0]['label'], lines[k0]['label'])
            r = sc + '_' + r[1:]
            print('note: %s %s referenced across routines -> %s' % (name, renames[name], r), file=sys.stderr)
        final[name] = r
for name, idx in sorted(label_idx.items(), key=lambda x: x[1]):
    if is_global[name]:
        continue
    sc = scope(idx)
    r = renames.get(name)
    if r is None:
        nx = next_instr(idx)
        back = [k for k, op in refs[name] if k > idx]
        if nx.startswith('ret'):
            r = '.return'
        elif re.match(r'mov\s+#\$FF,\s*acc', nx):
            r = '.fail'
        elif re.match(r'mov\s+#\$00,\s*acc', nx):
            r = '.ok'
        elif back:
            r = '.loop'
        else:
            r = '.l' + name[-4:].lower()
    base = r
    n = 2
    while r in used[sc]:
        r = '%s%d' % (base, n)
        n += 1
    used[sc].add(r)
    final[name] = r
gnames = collections.Counter(v for k, v in final.items() if is_global[k])
dups = [k for k, v in gnames.items() if v > 1]
if dups:
    raise SystemExit('duplicate global names: %s' % dups)

# ---------------------------------------------------------------- RAM substitution
old_syms = {}
for l in src:
    m = re.match(r'^([A-Za-z_][A-Za-z_0-9]*)\s*=\s*\$([0-9A-Fa-f]+)', l)
    if m:
        old_syms[m.group(1)] = int(m.group(2), 16)
old_syms.update(sym_alias)

D9_FIRST = {'set1', 'clr1', 'not1', 'bp', 'bn', 'bpc', 'ld', 'st', 'inc', 'dec', 'add', 'addc', 'sub', 'subc',
            'and', 'or', 'xor', 'push', 'pop', 'xch', 'dbnz', 'be', 'bne'}


def subst_operand(tok, bank):
    t = tok.strip()
    table = ram0 if bank == 0 else ram1 if bank == 1 else None
    if table is None:
        return tok
    a = None
    m = re.fullmatch(r'\$([0-9A-Fa-f]{2})', t)
    if m:
        a = int(m.group(1), 16)
    elif t in old_syms:
        a = old_syms[t]
    if a is None or a < 0x04 or a not in table:
        return tok
    return tok.replace(t, table[a])


def subst_imm_ptr(tok, bank):
    t = tok.strip()
    table = ram0 if bank == 0 else ram1 if bank == 1 else None
    m = re.fullmatch(r'#\$([0-9A-Fa-f]{2})', t)
    if table is None or not m:
        return tok
    a = int(m.group(1), 16)
    if a in table:
        return tok.replace(t, '#' + table[a])
    return tok



def is_code(t):
    return bool(re.match(r'^\s+[a-z]', t)) and not t.lstrip().startswith('.') and not t.lstrip().startswith(';')


def eff(state, code):
    b, st = state
    if re.match(r'^\s+set1\s+psw,\s*rambk0', code):
        return (1, st)
    if re.match(r'^\s+clr1\s+psw,\s*rambk0', code):
        return (0, st)
    if re.match(r'^\s+push\s+psw\b', code):
        return (b, st + (b,))
    if re.match(r'^\s+pop\s+psw\b', code):
        return (st[-1], st[:-1]) if st else (None, ())
    if re.match(r'^\s+st\s+psw\b', code):
        return (None, st)
    return state


UNCOND = ('br', 'brf', 'jmp', 'jmpf', 'ret', 'reti')
BRANCH = ('br', 'brf', 'jmp', 'jmpf', 'bz', 'bnz', 'bp', 'bn', 'bpc', 'be', 'bne', 'dbnz')
state_in = {}
UNK = 'unk'
work = []
for k, it in enumerate(lines):
    if it.get('label') and is_global[it['label']]:
        eb = entry_bank.get(it['label'], 0)
        state_in[k] = (eb, ())
        work.append(k)


def merge(a, b):
    if a is None:
        return b
    if a == b:
        return a
    return (a[0] if a[0] == b[0] else None, a[1] if a[1] == b[1] else ())


def propagate(k, state):
    old = state_in.get(k)
    newst = merge(old, state)
    if newst != old:
        state_in[k] = newst
        work.append(k)


glines = [k for k, it in enumerate(lines) if it.get('label') and is_global[it['label']]]


def scope_line(k):
    p = bisect.bisect_right(glines, k) - 1
    return glines[p] if p >= 0 else -1


dot_labels = {}
for k, it in enumerate(lines):
    m = re.match(r'^(\.[A-Za-z_][A-Za-z_0-9]*):', it['text'])
    if m:
        dot_labels[(scope_line(k), m.group(1))] = k

guard = 0
while work and guard < 200000:
    guard += 1
    k = work.pop()
    st = state_in[k]
    it = lines[k]
    t = it['text']
    if it.get('label') and is_global[it['label']] and st[0] is not None and entry_bank.get(it['label'], 0) != st[0] and False:
        pass
    if not is_code(t):
        if k + 1 < len(lines):
            nxt = lines[k + 1]
            if nxt.get('label') and is_global[nxt['label']]:
                continue
            propagate(k + 1, st)
        continue
    code = t.split(';')[0]
    m = re.match(r'^\s+([a-z0-9]+)\s*(.*)$', code)
    op, args = m.group(1), m.group(2)
    out_st = eff(st, code)
    if op in BRANCH:
        for w in re.findall(r'[A-Za-z_][A-Za-z_0-9]*', args):
            if w in label_idx and not is_global[w]:
                propagate(label_idx[w], out_st)
        for w in re.findall(r'(?<![\w$#%])\.[A-Za-z_][A-Za-z_0-9]*', args):
            key = (scope_line(k), w)
            if key in dot_labels:
                propagate(dot_labels[key], out_st)
    if op not in UNCOND and k + 1 < len(lines):
        nxt = lines[k + 1]
        if nxt.get('label') and is_global[nxt['label']]:
            continue
        propagate(k + 1, out_st)

for k, it in enumerate(lines):
    t = it['text']
    if not is_code(t):
        continue
    bank = state_in.get(k, (None, ()))[0]
    code, sep, cmt = t.partition(';')
    m = re.match(r'^(\s+)([a-z0-9]+)(\s+)(.*?)(\s*)$', code)
    if not m:
        continue
    ind, op, sp, args, trail = m.groups()
    ops = [p for p in re.split(r'(,)', args) if p != ',']
    if op in D9_FIRST and ops:
        if op in ('be', 'bne'):
            if not ops[0].strip().startswith('#') and not ops[0].strip().startswith('@'):
                ops[0] = subst_operand(ops[0], bank)
        else:
            ops[0] = subst_operand(ops[0], bank)
    elif op == 'mov' and len(ops) == 2:
        ops[1] = subst_operand(ops[1], bank)
        if ops[1].strip() in ('$00', '$01', '$02', '$03'):
            ops[0] = subst_imm_ptr(ops[0], bank)
    it['text'] = ind + op + sp + ','.join(ops) + trail + (sep + cmt if sep else '')

# ---------------------------------------------------------------- trl/trh pointer pairs
label_addr = {}
for k, it in enumerate(lines):
    if it.get('label'):
        la = next((x['addr'] if x['addr'] is not None else x.get('daddr') for x in lines[k + 1:]
                   if x['addr'] is not None or x.get('daddr') is not None), None)
        if la is not None and (it.get('newlabel') or it['label'] in new_labels.values()):
            label_addr.setdefault(la, it['label'])
ptr_hits = 0
for k in range(len(lines) - 1):
    a, b = lines[k]['text'], lines[k + 1]['text']
    ma = re.match(r'^(\s+mov\s+)#\$([0-9A-F]{2})(,\s*trl)(.*)$', a)
    mb = re.match(r'^(\s+mov\s+)#\$([0-9A-F]{2})(,\s*trh)(.*)$', b)
    if ma and mb:
        tgt = int(mb.group(2) + ma.group(2), 16)
        if tgt in label_addr:
            nm = label_addr[tgt]
            lines[k]['text'] = ma.group(1) + '#<' + nm + ma.group(3) + ma.group(4)
            lines[k + 1]['text'] = mb.group(1) + '#>' + nm + mb.group(3) + re.sub(r';\s*(Load|Read) string.*$', '', mb.group(4)).rstrip()
            ptr_hits += 1
    ma = re.match(r'^(\s+mov\s+)#\$([0-9A-F]{2})(,\s*trh)(.*)$', a)
    mb = re.match(r'^(\s+mov\s+)#\$([0-9A-F]{2})(,\s*trl)(.*)$', b)
    if ma and mb:
        tgt = int(ma.group(2) + mb.group(2), 16)
        if tgt in label_addr:
            nm = label_addr[tgt]
            lines[k]['text'] = ma.group(1) + '#>' + nm + ma.group(3) + ma.group(4)
            lines[k + 1]['text'] = mb.group(1) + '#<' + nm + mb.group(3) + re.sub(r';\s*(Load|Read) string.*$', '', mb.group(4)).rstrip()
            ptr_hits += 1
print('pointer pairs', ptr_hits, file=sys.stderr)

# ---------------------------------------------------------------- render
COL = 40


def with_comment(code, cmt):
    code = code.rstrip()
    pad = max(COL - len(code), 1)
    return code + ' ' * pad + '; ' + cmt


def rename_refs(text):
    code, sep, cmt = text.partition(';')
    def rep(m):
        w = m.group(0)
        return final.get(w, w)
    code = re.sub(r'(?<![#$%\w.])[A-Za-z_][A-Za-z_0-9]*', rep, code)
    return code + sep + cmt


result = []
for k, it in enumerate(lines):
    t = it['text']
    a = it['addr']
    o = it['orig']
    if it.get('label'):
        name = it['label']
        nn = final[name]
        hdr = headers.get(name) or headers.get(nn)
        if a is None:
            nxt = next((x['addr'] for x in lines[k + 1:] if x['addr'] is not None or x.get('daddr') is not None), None)
        if is_global[name]:
            la = next((x['addr'] if x['addr'] is not None else x.get('daddr') for x in lines[k + 1:]
                       if x['addr'] is not None or x.get('daddr') is not None), None)
            if hdr is not None and hdr:
                result.append(';; ' + '-' * 77)
                title = nn + (' ($%04X)' % la if la is not None else '')
                result.append(';; ' + title)
                for h in hdr:
                    result.append((';; ' + h).rstrip())
                result.append(';; ' + '-' * 77)
            elif hdr is not None:
                pass
            rest = t.split(':', 1)[1]
            if hdr:
                rest = ''
            result.append(nn + ':' + rest)
        else:
            rest = t.split(':', 1)[1]
            if name in renames:
                rest = ''
            result.append(nn + ':' + rest)
        continue
    if a is not None and a in pre_addr:
        for h in pre_addr[a]:
            result.append(('  ; ' + h).rstrip())
    if o is not None and o in pre_line:
        for h in pre_line[o]:
            result.append((';; ' + h).rstrip())
    t = rename_refs(t)
    if a is not None and a in eol:
        code = t.split(';')[0]
        t = with_comment(code, eol[a])
    elif o is not None and o in eol_line:
        code = t.split(';')[0] if not t.lstrip().startswith('.string') else t
        if t.lstrip().startswith('.string'):
            t = with_comment(t.rstrip(), eol_line[o])
        else:
            t = with_comment(code, eol_line[o])
    result.append(t)

text = '\n'.join(result) + '\n'
text = re.sub(r'\n(\s*\n){2,}', '\n\n', text)
text = re.sub(r'\bSerialTimeout\b', 'HalfSecTicks', text)
text = re.sub(r'\bNFreeBlocks\b', 'FreeGameBlocks', text)
open(OUT, 'w').write(text)
unused = [k for k in renames if k not in label_idx]
if unused:
    print('WARNING renames for unknown labels:', unused, file=sys.stderr)
print('globals', sum(1 for v in is_global.values() if v), 'locals', sum(1 for v in is_global.values() if not v), file=sys.stderr)
