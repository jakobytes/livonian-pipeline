# Aligns precomputed verse embeddings (Parquet: p_id, pos, v_id, embedding)
# with the verses of the pipeline and saves them as a NumPy matrix.
#
# Without --by-text, the output has one row per input verse (CSV: poem_id,
# pos, text), in the input order. With --by-text, it has one row per line
# of the given file of distinct verse texts, averaged over all occurrences
# of the text. Verses without an embedding get a zero vector.

import argparse
import csv
import logging

import numpy as np
from numpy.linalg import norm
import pyarrow.parquet as pq
from scipy.sparse import csr_matrix


def key(p_id, pos):
    return (np.asarray(p_id, dtype=np.int64) << 20) \
           | np.asarray(pos, dtype=np.int64)


def read_poem_ids(filename):
    t = pq.read_table(filename, columns=['p_id', 'nro'])
    return dict(zip(t['nro'].to_pylist(), t['p_id'].to_pylist()))


def read_verses(filename, poem_ids):
    keys, texts = [], []
    with open(filename) as fp:
        for r in csv.DictReader(fp):
            p_id = poem_ids.get(r['poem_id'], -1)
            keys.append(key(p_id, int(r['pos'])) if p_id >= 0 else -1)
            texts.append(r['text'])
    return np.array(keys, dtype=np.int64), texts


def parse_arguments():
    parser = argparse.ArgumentParser(
        description='Align verse embeddings with the verses of the pipeline.')
    parser.add_argument(
        '-e', '--embeddings-file', required=True,
        help='Parquet file with columns p_id, pos, embedding.')
    parser.add_argument(
        '-p', '--poems-file', required=True,
        help='Parquet file with columns p_id, nro (mapping to poem_id).')
    parser.add_argument(
        '-i', '--input-file', required=True,
        help='Verses CSV (poem_id, pos, text).')
    parser.add_argument(
        '-t', '--by-text', metavar='FILE',
        help='Output one row per line of FILE (distinct verse texts).')
    parser.add_argument('-o', '--output-file', required=True)
    return parser.parse_args()


def main():
    args = parse_arguments()
    logging.basicConfig(level=logging.INFO,
                        format='%(asctime)s %(levelname)s %(message)s')

    keys, texts = read_verses(args.input_file,
                              read_poem_ids(args.poems_file))
    # target[i] -- the output row of the i-th input verse (-1 if none)
    if args.by_text is not None:
        with open(args.by_text) as fp:
            text_ids = {line.rstrip('\n'): i for i, line in enumerate(fp)}
        target = np.array([text_ids.get(t, -1) for t in texts])
        n = len(text_ids)
    else:
        target = np.arange(len(texts))
        n = len(texts)

    order = np.argsort(keys)
    sorted_keys = keys[order]

    pf = pq.ParquetFile(args.embeddings_file)
    dim = pf.schema_arrow.field('embedding').type.list_size
    m = np.zeros((n, dim), dtype=np.float32)
    found = np.zeros(len(keys), dtype=bool)
    for i, batch in enumerate(pf.iter_batches(
            columns=['p_id', 'pos', 'embedding'], batch_size=65536)):
        emb = batch.column('embedding').flatten().to_numpy()\
                   .reshape(-1, dim).astype(np.float32)
        bk = key(batch.column('p_id'), batch.column('pos'))
        idx = np.searchsorted(sorted_keys, bk)
        idx[idx >= len(sorted_keys)] = 0
        match = sorted_keys[idx] == bk
        rows = order[idx[match]]
        found[rows] = True
        t = target[rows]
        keep = t >= 0
        # sum the embeddings of all occurrences of each output row
        u, inv = np.unique(t[keep], return_inverse=True)
        s = csr_matrix((np.ones(inv.shape[0]),
                        (inv, np.where(match)[0][keep])),
                       shape=(u.shape[0], emb.shape[0]))
        m[u] += s @ emb
        if i % 10 == 0:
            logging.info('{} batches read'.format(i+1))

    lengths = norm(m, axis=1, keepdims=True)
    np.divide(m, lengths, where=lengths > 0, out=m)
    logging.info('verses with an embedding: {} / {}'\
                 .format(found.sum(), len(keys)))
    logging.info('output rows with an embedding: {} / {}'\
                 .format((lengths > 0).sum(), n))
    np.save(args.output_file, m.astype(np.float16))


if __name__ == '__main__':
    main()
