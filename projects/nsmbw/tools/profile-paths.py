"""The most common call paths in a profile-stacks.txt that pass through one function and end in another.

    python projects/nsmbw/tools/profile-paths.py profile-stacks.txt HleFifoWrite sleep_for [--lib ...]

Prints each distinct path from FROM down to the leaf (innermost last) for samples whose stack holds
a frame matching FROM and one matching TO (substrings of the symbolized names), with its share.
"""
import argparse
import collections
import importlib.util
import os

spec = importlib.util.spec_from_file_location('report', os.path.join(os.path.dirname(__file__), 'profile-report.py'))
report = importlib.util.module_from_spec(spec)
spec.loader.exec_module(report)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('stacks')
    parser.add_argument('source')
    parser.add_argument('target')
    parser.add_argument('--lib', default=report.DEFAULT_LIB)
    parser.add_argument('--top', type=int, default=12)
    parser.add_argument('--scene')
    args = parser.parse_args()

    samples = report.read_samples(args.stacks, args.scene)
    wanted = set()
    for frames in samples:
        for depth, (_, offset) in enumerate(frames):
            if offset is not None:
                wanted.add(offset if depth == 0 else offset - 1)
    names = report.symbolize(args.lib, sorted(wanted))
    paths = collections.Counter()
    for frames in samples:
        chain = []
        for depth, (module, offset) in enumerate(frames):
            name = module if offset is None else names.get(offset if depth == 0 else offset - 1, '??')
            if not chain or chain[-1] != name:
                chain.append(name)
        source = next((i for i, n in enumerate(chain) if args.source in n), None)
        target = next((i for i, n in enumerate(chain) if args.target in n), None)
        if source is None or target is None or target > source:
            continue
        paths[' > '.join(reversed(chain[target:source + 1]))] += 1
    total = len(samples)
    for path, count in paths.most_common(args.top):
        print('%6.2f%%  %s' % (100.0 * count / total, path))


if __name__ == '__main__':
    main()
