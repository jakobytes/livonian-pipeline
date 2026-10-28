# Converts the tables prepared for the runoregi database (*.tbl.csv, with
# numeric keys) directly to Parquet files, as an alternative to loading them
# into MariaDB and exporting from there.
#
# The result mimics the MariaDB database: columns have the types of the
# MariaDB tables, rows with a duplicate primary key are dropped (keeping
# the first one, like LOAD DATA LOCAL), rows are sorted by the primary key,
# empty numeric fields become 0, and the tables computed in SQL (frequencies
# and statistics) are computed here.

import argparse
from datetime import datetime
import json
import logging
import os
import re

import numpy as np
import pandas as pd
import pyarrow as pa
import pyarrow.csv as pacsv
import pyarrow.parquet as pq


I8, U8, I32, U32 = pa.int8(), pa.uint8(), pa.int32(), pa.uint32()
F32, STR, BOOL = pa.float32(), pa.string(), pa.bool_()

# name: (columns (in file order), primary key, options)
TABLES = {
  'collectors': ([('col_id', I32), ('col_orig_id', STR), ('name', STR)],
                 ['col_id'], {}),
  'maps': ([('map_id', I8), ('name', STR)], ['map_id'], {}),
  'map_pol': ([('map_id', I8), ('pol_id', I32)], ['map_id', 'pol_id'], {}),
  'places': ([('pl_id', I32), ('place_orig_id', STR), ('name', STR),
              ('type', STR), ('par_id', I32)],
             ['pl_id'], {'enums': {'type': ['parish', 'county']}}),
  'polygons': ([('pol_id', I32), ('lang', STR), ('code', STR), ('name', STR),
                ('geometry', pa.binary())],
               ['pol_id'],
               {'tsv': True, 'header': False,
                'columns': ['pol_id', 'code', 'lang', 'name', 'geometry'],
                'enums': {'lang': ['in', 'ka', 'kaA', 'kaV', 'li', 'ly', 'ru',
                                   'su', 'suI', 'va', 've', 'viE', 'viP', 'x']}}),
  'pol_pl': ([('pol_id', I32), ('pl_id', I32), ('is_primary', I8)],
             ['pol_id', 'pl_id'], {}),
  'poems': ([('p_id', I32), ('nro', STR), ('collection', STR),
             ('display_name', STR)], ['p_id'], {}),
  'p_col': ([('p_id', I32), ('col_id', I32)], ['p_id', 'col_id'], {}),
  'p_dupl': ([('p_id', I32), ('master_p_id', I32)],
             ['p_id', 'master_p_id'], {}),
  'p_pl': ([('p_id', I32), ('pl_id', I32)], ['p_id', 'pl_id'], {}),
  'p_typ': ([('p_id', I32), ('t_id', I32), ('is_minor', BOOL)],
            ['p_id', 't_id'], {}),
  'p_year': ([('p_id', I32), ('year', I32)], ['p_id'], {}),
  'raw_meta': ([('p_id', I32), ('field', STR), ('value', STR)],
               ['p_id', 'field'], {'ci_keys': ['field']}),
  'refs': ([('p_id', I32), ('num', I32), ('type', STR), ('text', STR)],
           ['p_id', 'num'], {}),
  'runoregi_pages': ([('b_id', I32), ('view', STR), ('position', STR),
                      ('title', STR), ('helptext', STR), ('content', STR)],
                     ['b_id'],
                     {'tsv': True, 'header': False, 'file': 'runoregi_pages.tbl.tsv',
                      'auto_increment': 'b_id',
                      'enums': {'position': ['left', 'main', 'right']}}),
  'types': ([('t_id', I32), ('type_orig_id', STR), ('name', STR),
             ('description', STR), ('par_id', I32)], ['t_id'], {}),
  'verses': ([('v_id', I32), ('type', STR), ('text', STR)], ['v_id'], {}),
  'verse_poem': ([('p_id', I32), ('pos', I32), ('v_id', I32)],
                 ['p_id', 'pos'], {}),
  'verses_cl': ([('v_id', I32), ('text', STR)], ['v_id'], {}),
  'word_occ': ([('v_id', I32), ('pos', I32), ('w_id', I32)],
               ['v_id', 'pos'], {}),
  'words': ([('w_id', I32), ('text', STR)], ['w_id'], {}),
  'v_clusterings': ([('clustering_id', I8), ('name', STR),
                     ('description', STR)], ['clustering_id'], {}),
  'v_clust': ([('clustering_id', U8), ('v_id', I32), ('clust_id', I32),
               ('score', F32), ('confidence', F32)],
              ['clustering_id', 'v_id'], {}),
  'v_sim': ([('v1_id', I32), ('v2_id', I32), ('sim_cos', F32)],
            ['v1_id', 'v2_id'], {}),
  'p_sim': ([('p1_id', I32), ('p2_id', I32), ('sim_raw', F32),
             ('sim_al_l', F32), ('sim_al_r', F32), ('sim_al', F32)],
            ['p1_id', 'p2_id'], {}),
  'p_clust': ([('p_id', I32), ('clust_id', I32)], ['p_id'], {}),
}

# computed from other tables (as in the SQL scripts of filter-db)
DERIVED = {
  'v_clust_freq': ['verse_poem', 'v_clust'],
  'p_clust_freq': ['p_clust'],
  'word_freq': ['verse_poem', 'word_occ'],
  'place_stats': ['places', 'p_pl', 'poems', 'verse_poem', 'word_occ'],
}

TSV_ESCAPES = {'0': '\0', 'b': '\b', 'n': '\n', 'r': '\r', 't': '\t',
               'Z': '\x1a'}


def unescape(s):
    # MariaDB's default for LOAD DATA: ESCAPED BY '\\'
    return re.sub(r'\\(.)', lambda m: TSV_ESCAPES.get(m.group(1), m.group(1)), s)


def geojson_to_mariadb(s):
    # MariaDB's internal geometry format: 4-byte SRID + WKB
    # (an empty geometry becomes NULL)
    import shapely.geometry
    geom = shapely.geometry.shape(json.loads(s))
    return None if geom.is_empty else b'\0\0\0\0' + geom.wkb


def read_tbl(path, columns, opts):
    tsv = opts.get('tsv', False)
    file_cols = opts.get('columns', [c for c, t in columns])
    if opts.get('auto_increment'):
        file_cols = [c for c in file_cols if c != opts['auto_increment']]
    types = dict(columns)
    with open(path) as fp:
        n_file_cols = len(fp.readline().rstrip('\n').split('\t' if tsv else ','))
    # columns missing from the file (e.g. v_clust.score) get NULL
    present = file_cols[:n_file_cols]
    col_types = {c: (pa.int64() if pa.types.is_integer(types[c])
                     or pa.types.is_boolean(types[c]) else
                     STR if pa.types.is_binary(types[c]) else types[c])
                 for c in present}
    def _read(col_types):
        return pacsv.read_csv(
            path,
            read_options=pacsv.ReadOptions(
                column_names=present,
                skip_rows=1 if opts.get('header', True) else 0,
                block_size=1 << 26),
            parse_options=pacsv.ParseOptions(
                delimiter='\t' if tsv else ',', quote_char=False if tsv else '"',
                newlines_in_values=not tsv),
            convert_options=pacsv.ConvertOptions(
                column_types=col_types, null_values=['', '\\N'],
                strings_can_be_null=False, quoted_strings_can_be_null=False))\
            .to_pandas()
    try:
        df = _read(col_types)
    except pa.ArrowInvalid:
        # Some numeric field is not a number: like MariaDB, take its
        # leading digits (e.g. '19xx' -> 19), or 0 if there are none.
        num_cols = [c for c, t in col_types.items() if t == pa.int64()]
        df = _read(dict(col_types, **{c: STR for c in num_cols}))
        for c in num_cols:
            num = df[c].str.extract(r'^\s*([+-]?\d+)')[0]
            bad = df[c].ne('') & (num.isna() | num.str.len().ne(df[c].str.strip().str.len()))
            if bad.any():
                logging.warning('{}: {} non-numeric values, e.g. {!r}'
                                .format(c, bad.sum(), df.loc[bad, c].iloc[0]))
            df[c] = pd.to_numeric(num)
    for c, typ in columns:
        if c not in df.columns:
            df[c] = None
        elif pa.types.is_integer(typ) or pa.types.is_boolean(typ) \
                or pa.types.is_floating(typ):
            # LOAD DATA sets empty numeric fields to 0
            df[c] = df[c].fillna(0)
            if pa.types.is_boolean(typ):
                df[c] = df[c] != 0
            elif pa.types.is_integer(typ):
                # out-of-range values are clamped (non-strict SQL mode)
                info = np.iinfo(typ.to_pandas_dtype())
                out = (df[c] < info.min) | (df[c] > info.max)
                if out.any():
                    logging.warning('{}: {} values out of range for {}, clamped'
                                    .format(c, out.sum(), typ))
                    df[c] = df[c].clip(info.min, info.max)
    if tsv:
        for c, typ in columns:
            if c in present and typ == STR:
                df[c] = df[c].map(unescape)
    if opts.get('auto_increment'):
        df[opts['auto_increment']] = np.arange(1, len(df)+1)
    return df


def to_table(df, columns):
    schema = pa.schema(columns)
    return pa.Table.from_pandas(df[[c for c, t in columns]], schema=schema,
                                preserve_index=False)


def export_table(name, tbl_dir, out_dir):
    columns, key, opts = TABLES[name]
    df = read_tbl(os.path.join(tbl_dir, opts.get('file', name + '.tbl.csv')),
                  columns, opts)
    for c, values in opts.get('enums', {}).items():
        if c == 'lang':          # polygons: IF(@lang = 'null', NULL, @lang)
            df.loc[df[c] == 'null', c] = None
        bad = df[c].notna() & ~df[c].isin(values)
        df.loc[bad, c] = ''
    if name == 'polygons':
        df['geometry'] = df['geometry'].map(geojson_to_mariadb)
    # drop duplicate primary keys (keeping the first), sort by the key
    dedup = df[key].copy()
    for c in opts.get('ci_keys', []):
        dedup[c] = dedup[c].str.lower().str.rstrip(' ')
    keep = ~dedup.duplicated(keep='first')
    df = df[keep].sort_values(key, kind='stable')
    return df, int((~keep).sum())


def derive(name, t):
    if name == 'v_clust_freq':
        df = t['verse_poem'][['v_id']].merge(
            t['v_clust'][['v_id', 'clust_id', 'clustering_id']], on='v_id')
        df = df.groupby(['clustering_id', 'clust_id']).size()\
               .rename('freq').reset_index()
        return df, [('clust_id', I32), ('freq', I32), ('clustering_id', U8)]
    if name == 'p_clust_freq':
        df = t['p_clust'].groupby('clust_id').size().rename('freq').reset_index()
        return df, [('clust_id', I32), ('freq', I32)]
    if name == 'word_freq':
        df = t['verse_poem'][['v_id']].merge(t['word_occ'][['v_id', 'w_id']],
                                            on='v_id')
        df = df.groupby('w_id').size().rename('freq').reset_index()
        return df, [('w_id', I32), ('freq', I32)]
    if name == 'place_stats':
        df = t['places'][['pl_id']]\
            .merge(t['p_pl'], on='pl_id', how='left')\
            .merge(t['poems'][['p_id', 'collection']], on='p_id', how='left')\
            .merge(t['verse_poem'][['p_id', 'pos', 'v_id']], on='p_id', how='left')\
            .merge(t['word_occ'][['v_id', 'w_id']], on='v_id', how='left')
        df['collection'] = df['collection'].fillna('literary')
        # COUNT(DISTINCT vp.p_id): only poems that have verses
        df['vp_p_id'] = df['p_id'].where(df['pos'].notna())
        g = df.groupby(['pl_id', 'collection'])
        df = pd.DataFrame({
            'npoems': g['vp_p_id'].nunique(),
            'nverses': g[['p_id', 'pos']].apply(
                lambda x: len(x.dropna().drop_duplicates())),
            'nwords': g['w_id'].count(),
        }).reset_index()
        return df, [('pl_id', I32), ('collection', STR), ('npoems', U32),
                    ('nverses', U32), ('nwords', U32)]


def parse_arguments():
    parser = argparse.ArgumentParser(
        description='Convert the runoregi tables (*.tbl.csv) to Parquet.')
    parser.add_argument('-i', '--input-dir', required=True,
                        help='Directory containing the *.tbl.csv files.')
    parser.add_argument('-o', '--output-dir', required=True)
    parser.add_argument('-t', '--tables', nargs='+',
                        default=list(TABLES) + list(DERIVED),
                        help='Tables to export (default: all).')
    return parser.parse_args()


def main():
    args = parse_arguments()
    logging.basicConfig(level=logging.INFO,
                        format='%(asctime)s %(levelname)s %(message)s')
    os.makedirs(args.output_dir, exist_ok=True)

    needed = set(t for t in args.tables if t in TABLES)
    for t in args.tables:
        needed.update(DERIVED.get(t, []))
    loaded, exported = {}, []
    for name in [t for t in TABLES if t in needed]:
        df, n_dupl = export_table(name, args.input_dir, args.output_dir)
        if name in args.tables:
            pq.write_table(to_table(df, TABLES[name][0]),
                           os.path.join(args.output_dir, name + '.parquet'),
                           compression='zstd')
            exported.append(name)
            logging.info('{:<16} {:>10} rows ({} duplicate keys dropped)'
                         .format(name, len(df), n_dupl))
        # keep only what the derived tables need, to save memory
        if any(name in DERIVED[d] for d in args.tables if d in DERIVED):
            loaded[name] = df
    for name in [d for d in DERIVED if d in args.tables]:
        df, columns = derive(name, loaded)
        pq.write_table(to_table(df, columns),
                       os.path.join(args.output_dir, name + '.parquet'),
                       compression='zstd')
        exported.append(name)
        logging.info('{:<16} {:>10} rows (derived)'.format(name, len(df)))

    now = datetime.now().replace(microsecond=0)
    dbmeta = pd.DataFrame({'table_name': ['dbmeta'] + sorted(exported),
                           'last_modified': now, 'ready': True})
    dbmeta = dbmeta.sort_values('table_name')
    pq.write_table(
        to_table(dbmeta, [('table_name', STR),
                          ('last_modified', pa.timestamp('us')),
                          ('ready', BOOL)]),
        os.path.join(args.output_dir, 'dbmeta.parquet'))


if __name__ == '__main__':
    main()
