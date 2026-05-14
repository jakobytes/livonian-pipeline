import argparse
import csv
import glob
import lxml.etree as ET
import logging
import os.path as P
import re

# FIXME despite the name, this script right now is made for both SKVR and KR.
# Eventually, it will be merged with the scripts for ERAB and JR as well.

from common_xml_functions import \
    elem_content_to_str, \
    insert_refnrs, \
    parse_skvr_refs
from convert_skvr import read_inputs as skvr_read_inputs


PREFIX = 'vldl_'


def read_inputs(filenames, prefix, collection):
    yield from skvr_read_inputs(filenames, prefix, collection)

def make_display_name(item):
    if 'metaxml' in item:
        n_sgn = item['metaxml'].find('SGN')
        if n_sgn is not None and n_sgn.text:
            return n_sgn.text
    return None

#########################################################################
# MAPPING FUNCTIONS
#########################################################################

def map_poems(item):
    yield { 'poem_id': item['poem_id'],
            'collection': item['collection'] ,
            'display_name': make_display_name(item) }

def map_verses(item):
    for i, node in enumerate(item['textxml'], 1):
        yield { 'poem_id'    : item['poem_id'],
                'pos'        : i,
                'verse_type' : node.tag,
                'text'       : insert_refnrs(elem_content_to_str(node)).rstrip() }

def map_refs(item):
    if item['refsxml'] is not None:
        for refnr, reftext in parse_skvr_refs(item['refsxml']):
            yield { 'poem_id'    : item['poem_id'],
                    'ref_number' : refnr,
                    'ref_type'   : 'REF',
                    'ref'        : reftext.strip() }


def map_raw_meta(item):
    for node in item['metaxml']:
        yield { 'poem_id' : item['poem_id'],
                'field'   : node.tag,
                'value'   : insert_refnrs(elem_content_to_str(node)).rstrip() }

def map_meta(item):
    yield { key: item[key] \
            for key in ('poem_id', 'year', 'place_id', 'collector_id') }

# A dictionary: output_filename => (fieldnames, mapping_function)
# The mapping_function maps one row of the input CSV (i.e. one poem) to an
# iterator over output rows.
mappers = {
    'verses.csv': (('poem_id', 'pos', 'verse_type', 'text'), map_verses),

    'refs.csv' : (('poem_id', 'ref_number', 'ref_type', 'ref'),  map_refs),

    'meta.csv' : (('poem_id', 'year', 'place_id', 'collector_id'), map_meta),

    'poems.csv' : (('poem_id', 'collection', 'display_name'), map_poems),

    'raw_meta.csv' : (('poem_id', 'field', 'value'),  map_raw_meta),
}


def transform_rows(input_rows, mappers, output_dir='.'):
    '''Applies the mappers to an iterator over input rows.'''

    outfiles = { m_file: open(P.join(output_dir, m_file), 'w+') \
                         for m_file in mappers }
    writers = { m_file: csv.DictWriter(outfiles[m_file], m_header)
                for m_file, (m_header, m_func) in mappers.items() }
    for writer in writers.values():
        writer.writeheader()
    for row in input_rows:
        for m_file, (m_header, m_func) in mappers.items():
            writers[m_file].writerows(m_func(row))
    for fp in outfiles.values():
        fp.close()


def parse_arguments():
    parser = argparse.ArgumentParser(description='Convert VLDL to CSV files.')
    parser.add_argument(
        'xml_files', nargs='*', metavar='FILE', default=[],
        help='A list of input files in XML format.')
    parser.add_argument(
        '-d', '--output-dir', metavar='PATH', default='.',
        help='The directory to write output files to.')
    parser.add_argument(
        '-c', '--collection', metavar='NAME', default='vldl',
        help='The value to set for the collection attribute (default: vldl).')
    parser.add_argument(
        '-p', '--prefix', metavar='PREFIX', default='vldl_',
        help='The prefix to prepend to collector, place and type IDs.')
    return parser.parse_args()


if __name__ == '__main__':
    args = parse_arguments()

    if not args.xml_files:
        matches = sorted(glob.glob('data/raw/vldl/Volkslieder*.xml'))
        if not matches:
            raise SystemExit('No VLDL XML file found matching data/raw/vldl/Volkslieder*.xml')
        if len(matches) > 1:
            logging.warning('Multiple VLDL input files found; using %s', matches[0])
        args.xml_files = [matches[0]]

    inputs = read_inputs(args.xml_files, args.prefix, args.collection)
    transform_rows(inputs, mappers, output_dir=args.output_dir)

