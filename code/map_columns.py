import argparse
from collections import defaultdict
import csv
import logging
from operator import itemgetter
import os.path
import sys


def load_mapping(filename, cols_from, cols_to, header=None, multiple=False):
    mapping = defaultdict(list) if multiple else {}
    with open(filename) as fp:
        reader = csv.DictReader(fp)
        # map the header used in the mapping file to the provided one
        if header is not None:
            if any(c not in header for c in cols_from + cols_to):
                raise RuntimeError('Column {} not in header!'.format(c))
            cols_from = tuple(reader.fieldnames[header.index(c)] for c in cols_from)
            cols_to = tuple(reader.fieldnames[header.index(c)] for c in cols_to)
        # read the key-value mapping
        for row in reader:
            key = tuple(row[c] for c in cols_from)
            val = tuple(row[c] for c in cols_to)
            if multiple:
                mapping[key].append(val)
            else:
                if key in mapping:
                    logging.warning(
                        'Ignoring {} -> {}: key already in use. You may '
                        'consider using --multiple.'.format(key, val))
                else:
                    mapping[key] = val
    return mapping


def map_fieldnames(fieldnames, cols_from, cols_to, multiple=False):
    result = []
    added = False
    for f in fieldnames:
        # insert cols_to at the index of the first column of cols_from
        if f in cols_from:
            if not added:
                result.extend(cols_to)
                added = True
        else:
            result.append(f)
    return result


def parse_arguments():
    parser = argparse.ArgumentParser(
        description='Map column combinations in the CSV.')
    parser.add_argument(
        '-f', '--cols-from', help='The columns of the input key.')
    parser.add_argument(
        '-t', '--cols-to', help='The columns of the output key.')
    parser.add_argument(
        '-H', '--header', default=None,
        help='Assume a different header for the mapping file.')
    parser.add_argument(
        '-m', '--multiple', action='store_true',
        help='Allow one-to-many mappings (multiple output values for one input key).')
    parser.add_argument(
        '-u', '--unique', action='store_true',
        help='Do not output duplicate rows.')
    parser.add_argument('map_file', help='The file containing the mapping.')
    return parser.parse_args()


def main():
    args = parse_arguments()
    cols_from = args.cols_from.split(',')
    cols_to = args.cols_to.split(',')
    header = args.header.split(',') if args.header is not None else None
    mapping = load_mapping(args.map_file, cols_from, cols_to,
                           header=header, multiple=args.multiple)
    reader = csv.DictReader(sys.stdin)
    fieldnames = map_fieldnames(reader.fieldnames, cols_from, cols_to)
    writer = csv.DictWriter(sys.stdout, fieldnames, lineterminator='\n')
    writer.writeheader()
    seen = set()
    for row in reader:
        key = tuple(row[c] for c in cols_from)
        if key in mapping:
            for c in cols_from:
                del row[c]
            if args.multiple:
                for val in mapping[key]:
                    for i, c in enumerate(cols_to):
                        row[c] = val[i]
                    if not args.unique or tuple(row.values()) not in seen:
                        writer.writerow(row)
                    if args.unique:
                        seen.add(tuple(row.values()))
            else:
                for i, c in enumerate(cols_to):
                    row[c] = mapping[key][i]
                if not args.unique or tuple(row.values()) not in seen:
                    writer.writerow(row)
                if args.unique:
                    seen.add(tuple(row.values()))


if __name__ == '__main__':
    main()

