# Verse similarities from precomputed embeddings. The counterpart of
# `shortsim-ngrcos`, with the same input (distinct verse texts on stdin)
# and output (text1, text2, sim as TSV), but using the vectors from FILE
# (one row per input line, see load_embeddings.py) instead of n-grams.

import argparse
import sys
import warnings

import faiss
import numpy as np

from shortsim.scripts.ngrcos import find_similarities, read_verses


def parse_arguments():
    parser = argparse.ArgumentParser(
        description='Compute verse similarities from embeddings.')
    parser.add_argument(
        '-e', '--embeddings', metavar='FILE', required=True,
        help='NumPy matrix of verse embeddings.')
    parser.add_argument('-g', '--use-gpu', action='store_true')
    parser.add_argument(
        '-k', type=int, default=10,
        help='The number of nearest neighbors to find for each verse.')
    parser.add_argument(
        '-q', '--query-size', type=int, default=100,
        help='The number of verses to pass in a single query '
             '(doesn\'t affect the results, only performance)')
    parser.add_argument(
        '-t', '--threshold', type=float, default=0.7,
        help='Minimum similarity to output.')
    parser.add_argument(
        '-p', '--print-progress', action='store_true',
        help='Print a progress bar.')
    return parser.parse_args()


def main():
    args = parse_arguments()

    verses = read_verses(sys.stdin)
    m = np.load(args.embeddings).astype(np.float32)
    if m.shape[0] != len(verses):
        raise RuntimeError(
            'The number of embeddings ({}) does not match the number of'
            ' verses ({})!'.format(m.shape[0], len(verses)))

    index = faiss.IndexFlatIP(m.shape[1])
    if args.use_gpu:
        try:
            res = faiss.StandardGpuResources()
            index = faiss.index_cpu_to_gpu(res, 0, index)
        except Exception:
            warnings.warn('GPU not available!')
    index.add(m)

    sims = find_similarities(index, m, args.k, args.threshold,
                             args.query_size, args.print_progress)
    for i, j, sim in sims:
        print(verses[i], verses[j], sim, sep='\t')


if __name__ == '__main__':
    main()
