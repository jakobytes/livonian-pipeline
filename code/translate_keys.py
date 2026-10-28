import argparse
import csv
from operator import itemgetter
import os.path
import sys


class Dictionary:
    def __init__(self, fields, keyname, filename, header):
        self.fields = fields
        self.keyname = keyname
        self.filename = filename
        self.dict = {}
        self.inv_dict = {}
        self.next_id = 1
        if os.path.isfile(self.filename):
            self.load(header)

    def add(self, key):
        self.inv_dict[key] = self.next_id
        self.next_id += 1

    def __getitem__(self, key):
        if key not in self.inv_dict:
            self.add(key)
        return self.inv_dict[key]

    def get_by_key(self, key, default=None):
        try:
            return self.dict[key]
        except KeyError as e:
            if default is not None:
                return default
            else:
                raise e

    def load(self, header=None):
        with open(self.filename) as fp:
            reader = csv.DictReader(fp, fieldnames=header)
            if header is not None:
                next(reader)            # skip the original header row
            for row in reader:
                val = int(row[self.keyname])
                key = tuple(row[f] for f in self.fields)
                self.dict[val] = key
                self.inv_dict[key] = val
                if val >= self.next_id:
                    self.next_id = val+1

    def save(self):
        with open(self.filename, 'w+') as fp:
            writer = csv.DictWriter(
                fp,
                fieldnames=(self.keyname,)+self.fields,
                lineterminator='\n')
            writer.writeheader()
            for key, val in sorted(self.inv_dict.items(), key=itemgetter(1)):
                row = dict(zip((self.keyname,)+self.fields, (val,)+key))
                writer.writerow(row)


def parse_dictionary_name(name):
    try:
        sp = name.split(':')
        fields_str, keyname, filename = sp[:3]
        fields = tuple(fields_str.split(','))
        header = tuple(sp[3].split(',')) if len(sp) >= 4 else None
        return fields, keyname, filename, header
    except Exception:
        raise RuntimeError('Invalid dictionary specification: {}'.format(name))


def map_fields(fields, dicts, add_keys=False, reverse=False):
    '''Figure out what the fields of the resulting CSV will be.
       (Fields mapped by any of the dictionaries are replaced by the
       dictionary's key.)'''
    result = []
    for f in fields:
        add = True
        for d in dicts:
            if not reverse and f in d.fields:
                add = add_keys
                if d.keyname not in result:
                    result.append(d.keyname)
            elif reverse and f == d.keyname:
                add = add_keys
                result.extend(d.fields)
        if add:
            result.append(f)
    return result


def translate(reader, writer, dicts, reverse=False, null=''):
    for row_in in reader:
        row_out = {}
        for f in writer.fieldnames:
            if f in row_in:
                row_out[f] = row_in[f]
            else:
                for d in dicts:
                    if not reverse and d.keyname == f:
                        row_out[f] = d[tuple(row_in[ff] for ff in d.fields)]
                        break
                    elif reverse and f in d.fields:
                        idx = d.fields.index(f)
                        key = int(row_in[d.keyname]) if row_in[d.keyname] else 0
                        row_out[f] = d.get_by_key(
                          key, default=(null,)*len(d.fields))[idx]
        writer.writerow(row_out)


def translate_files(infiles, outfp, dicts, add_keys=False, reverse=False, null=''):
    fields, writer = None, None
    for infile in infiles:
        with open(infile) as infp:
            reader = csv.DictReader(infp)
            fields = map_fields(reader.fieldnames, dicts, add_keys, reverse)
            if writer is None:
                writer = csv.DictWriter(outfp, fields, lineterminator='\n')
                writer.writeheader()
            elif fields != writer.fieldnames:
                raise RuntimeError(
                    'Fields in input file {} inconsistent with the earlier'
                    ' input files.'.format(infile))
            translate(reader, writer, dicts, reverse, null)


# FIXME there is some code duplication with translate_files() here
# -> eliminate if possible
def translate_stream(infp, outfp, dicts, add_keys=False, reverse=False, null=''):
    reader = csv.DictReader(infp)
    fields = map_fields(reader.fieldnames, dicts, add_keys, reverse)
    writer = csv.DictWriter(outfp, fields, lineterminator='\n')
    writer.writeheader()
    translate(reader, writer, dicts, reverse, null)


def parse_arguments():
    parser = argparse.ArgumentParser(
        description='Replace fields in CSV with numeric keys.')
    parser.add_argument(
        '-a', '--add-keys', action='store_true',
        help='Do not replace the fields, just add the keys.')
    parser.add_argument(
        '-i', '--input-files', nargs='+', default=[],
        help='A list of input files (CSV, all having the same columns).')
    parser.add_argument(
        '-n', '--null', default='',
        help='The string to use for null value (default: empty string).')
    parser.add_argument('-o', '--output-file', metavar='PATH')
    parser.add_argument(
        '-d', '--dicts', nargs='+', default=[],
        metavar='FIELDS:KEY:FILE[:HEADER]',
        help='A list of key dictionaries, each having the format:'
             ' FIELDS:KEY:FILE, where FIELDS are the CSV fields to'
             ' convert to a key (comma-separated), KEY is the name of the'
             ' column to contain the resulting key, and FILE is the file where'
             ' the mapping is stored. Example value:'
             ' \'verse_type,content:v_id:v_id.map.txt\'.'
             ' If HEADER is given, it replaces the header of the dictionary'
             ' file.')
    parser.add_argument(
        '-r', '--reverse', action='store_true',
        help='Instead replace keys with values.')
    parser.add_argument(
        '-O', '--no-overwrite', action='store_true',
        help='Do not overwrite the dictionary files.')
    return parser.parse_args()


def main():
    args = parse_arguments()
    dicts = []
    for fields, keyname, filename, header in map(parse_dictionary_name, args.dicts):
        dicts.append(Dictionary(fields, keyname, filename, header))
    if args.input_files and args.input_files != ['-']:
        if args.output_file is None:
            # input from files, output to stdout
            translate_files(args.input_files, sys.stdout, dicts,
                            args.add_keys, args.reverse, args.null)
        else:
            # both input and output are files
            with open(args.output_file, 'w+') as outfp:
                translate_files(args.input_files, outfp, dicts,
                                args.add_keys, args.reverse, args.null)
    else:
        if args.output_file is None:
            # input from stdin, output to stdout
            translate_stream(sys.stdin, sys.stdout, dicts,
                             args.add_keys, args.reverse, args.null)
        else:
            # input from stdin, output to file
            with open(args.output_file, 'w+') as outfp:
                translate_stream(sys.stdin, outfp, dicts,
                                 args.add_keys, args.reverse, args.null)
    if not args.no_overwrite:
        for d in dicts:
            d.save()


if __name__ == '__main__':
    main()

