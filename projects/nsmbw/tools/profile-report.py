"""Symbolize and summarize a profile-stacks.txt written by the runtime's sampling profiler.

NSMBW_PROFILE=<start s>:<length s> makes the Android/Linux runtime sample the game thread and write
profile-stacks.txt next to console.log: one sample a line, innermost frame first, each frame an
offset in libmain.so (or module+offset for other libraries). This script names the frames with
llvm-symbolizer against the unstripped library and prints self time, inclusive time and callers by
function, with translated functions (func_XXXXXXXX) labelled by their guest symbol. --annotate FUNC
prints FUNC's disassembly with the samples on each instruction.

    python projects/nsmbw/tools/profile-report.py profile-stacks.txt [--lib android-build/libmain.so] [--annotate func_801A3880]

Symbolize against the unstripped library that produced the run: copy it aside before rebuilding.
"""
import argparse
import collections
import json
import os
import re
import subprocess

REPO = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..', '..'))
# llvm-symbolizer / llvm-objdump: the NDK's (ANDROID_NDK_HOME), or any LLVM on PATH.
NDK_BIN = os.path.join(os.environ.get('ANDROID_NDK_HOME', ''), 'toolchains', 'llvm', 'prebuilt',
                       'windows-x86_64' if os.name == 'nt' else 'linux-x86_64', 'bin')
DEFAULT_LIB = os.path.join(REPO, 'android-build', 'libmain.so')
SYMBOL_TABLE = os.path.join(REPO, 'generated', 'guest_symbol_table.cpp')


def guest_symbols():
    text = open(SYMBOL_TABLE, encoding='utf-8').read()
    addresses = re.findall(r'0x([0-9A-Fa-f]{8})u,', text.split('kGuestMapSymbolNames[] = {')[0])
    names = re.findall(r'^\s+"(.*)",$', text.split('kGuestMapSymbolNames[] = {')[1], re.M)
    return {int(a, 16): n for a, n in zip(addresses, names)}


def read_samples(path, scene=None):
    """Each sample's frames; with `scene` (e.g. '005'), only the samples taken in that scene."""
    samples = []
    for line in open(path, encoding='utf-8'):
        if line.startswith('#') or not line.strip():
            continue
        tokens = line.split()
        if tokens[0].startswith('S'):
            if scene is not None and int(tokens[0][1:], 16) != int(scene, 16):
                continue
            tokens = tokens[1:]
        elif scene is not None:
            continue
        frames = []
        for depth, token in enumerate(tokens):
            if token.startswith('?+') and depth > 0:
                continue  # x30 reused as a scratch register, or a frame outside every module
            if '+' in token:
                frames.append(('[' + token.split('+')[0] + ']', None))
            else:
                frames.append((None, int(token, 16)))
        samples.append(frames)
    return samples


def tool(name):
    path = os.path.join(NDK_BIN, name + ('.exe' if os.name == 'nt' else ''))
    return path if os.path.exists(path) else name


def symbolize(lib, offsets, innermost=None):
    """Function name for each offset: the real (outermost) function the code is in. With `innermost`
    (a dict), also records the innermost inlined function there, i.e. which helper's code it is."""
    query = '\n'.join('0x%x' % o for o in offsets) + '\n'
    out = subprocess.run([tool('llvm-symbolizer'), '--obj=' + lib, '--output-style=JSON', '--inlines', '--functions=short'],
                         input=query, capture_output=True, text=True, check=True).stdout
    names = {}
    for line in out.splitlines():
        if not line.strip():
            continue
        record = json.loads(line)
        address = int(record['Address'], 16)
        symbols = record.get('Symbol') or [{}]
        names[address] = symbols[-1].get('FunctionName') or '??'
        if innermost is not None:
            innermost[address] = symbols[0].get('FunctionName') or '??'
    return names


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('stacks')
    parser.add_argument('--lib', default=DEFAULT_LIB)
    parser.add_argument('--top', type=int, default=40)
    parser.add_argument('--scene', help='only samples in this scene (hex, as console.log names it: 005 = STAGE)')
    parser.add_argument('--annotate', action='append', default=[], help='host function to disassemble with samples')
    args = parser.parse_args()

    guest = guest_symbols()
    samples = read_samples(args.stacks, args.scene)
    total = len(samples)
    scenes = collections.Counter(line.split()[0] for line in open(args.stacks, encoding='utf-8')
                                 if line.startswith('S'))
    print('scenes: ' + ', '.join('%s %d' % (k, v) for k, v in scenes.most_common()))
    wanted = set()
    for frames in samples:
        for depth, (_, offset) in enumerate(frames):
            if offset is not None:
                wanted.add(offset if depth == 0 else offset - 1)
    inner = {}
    names = symbolize(args.lib, sorted(wanted), inner)

    def label(name):
        m = re.fullmatch(r'func_([0-9A-F]{8})', name)
        if m:
            address = int(m.group(1), 16)
            return '%s %s' % (m.group(1), guest.get(address, ''))
        return name

    def frame_name(depth, frame):
        module, offset = frame
        if offset is None:
            return module
        return label(names.get(offset if depth == 0 else offset - 1, '??'))

    self_time = collections.Counter()
    inclusive = collections.Counter()
    callers = collections.defaultdict(collections.Counter)
    hot_pcs = collections.Counter()
    operations = collections.defaultdict(collections.Counter)  # function -> inlined helper at the leaf
    for frames in samples:
        chain = [frame_name(d, f) for d, f in enumerate(frames)]
        leaf = chain[0]
        self_time[leaf] += 1
        if frames[0][1] is not None:
            hot_pcs[frames[0][1]] += 1
            operations[leaf][inner.get(frames[0][1], '??')] += 1
        for name in set(chain):
            inclusive[name] += 1
        caller = next((name for name in chain[1:] if name != leaf), '?')
        callers[leaf][caller] += 1

    print('%d samples' % total)
    print('\n== self')
    for name, count in self_time.most_common(args.top):
        top_callers = ', '.join('%s %.0f%%' % (c, 100.0 * n / count) for c, n in callers[name].most_common(3))
        print('%6.2f%%  %s    <- %s' % (100.0 * count / total, name, top_callers))
        inlined = [(op, n) for op, n in operations[name].most_common(6) if op != name.split(' ')[-1]]
        if inlined and not name.startswith('['):
            print('           in: ' + ', '.join('%s %.0f%%' % (op, 100.0 * n / count) for op, n in inlined))
    print('\n== inclusive')
    for name, count in inclusive.most_common(args.top):
        print('%6.2f%%  %s' % (100.0 * count / total, name))

    for function in args.annotate:
        print('\n== %s' % function)
        out = subprocess.run([tool('llvm-objdump'), '-d', '--no-show-raw-insn', '--disassemble-symbols=' + function, args.lib],
                             capture_output=True, text=True, check=True).stdout
        in_function = 0
        for line in out.splitlines():
            m = re.match(r'\s*([0-9a-f]+):\s*(.*)', line)
            if not m:
                continue
            address = int(m.group(1), 16)
            count = hot_pcs.get(address, 0)
            in_function += count
            print('%6s  %8x  %s' % (count or '', address, m.group(2)))
        print('%d samples in %s' % (in_function, function))


if __name__ == '__main__':
    main()
