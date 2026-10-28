import argparse
import csv
import itertools
import logging
import numpy as np
import re
import torch
import tqdm
import sys
import time

from shortsim.ngrcos import vectorize
from matrix_align import matrix_align


# The maximum size of the alignment matrix between one poem and the rest.
# If the matrix is too large, it will be split and computed in parts.
# Change this to a lower value if you're getting out-of-memory errors.
MAX_SIZE = 3758096384               # this many 16-bit numbers =~ 7G


def read_input(filename):
    verses = []
    with open(filename) as fp:
        reader = csv.DictReader(fp)
        for line in reader:
            verses.append((line['poem_id'], line['pos'], line['text']))
    return verses


# move input lines where the poem ID matches regex to the beginning of the list
def move_to_beginning(verses, regex):
    pattern = re.compile(regex)
    return [v for v in verses if pattern.match(v[0][0])] + \
           [v for v in verses if not pattern.match(v[0][0])]


def similarity_with_splitting(x, y, yb, max_size, **kwargs):
    assert yb[0] == 0
    if x.shape[0] * y.shape[0] <= max_size:
        #logging.debug('Not splitting: {}*{} < {}'.format(x.shape[0], y.shape[0], max_size))
        return matrix_align(x, y, yb, **kwargs)
    else:
        logging.debug('Splitting: {}*{} > {}'.format(x.shape[0], y.shape[0], max_size))
        j = torch.searchsorted(x.shape[0] * yb, max_size)
        if j <= 1:
            logging.error('Cannot process a single pair: {}*{} > {}'\
                          .format(x.shape[0], yb[1], max_size))
            # return empty results
            if not kwargs['return_alignments']:
                return torch.zeros(yb.shape[0]-1)
            else:
                return (torch.zeros(yb.shape[0]-1),
                        -torch.ones(y.shape[0]),
                        torch.zeros(y.shape[0]))
        logging.debug('Processing: {}*{} < {}'.format(x.shape[0], y[:yb[j-1],].shape[0], max_size))
        result_1 = matrix_align(x, y[:yb[j-1],], yb[:j], **kwargs)
        result_2 = similarity_with_splitting(x, y[yb[j-1]:,], yb[j-1:]-yb[j-1], max_size, **kwargs)
        if not kwargs['return_alignments']:
            return torch.concat((result_1, result_2))
        else:
            return (torch.concat((result_1[0], result_2[0])),
                    torch.concat((result_1[1], result_2[1])),
                    torch.concat((result_1[2], result_2[2])))


def compute_similarities(
        m, poem_boundaries, poem_ids,
        ids_to_process=None,
        threshold=0.5, sim_raw_thr=2.0,
        sim_onesided_thr=0.1, sim_sym_thr=0,
        rescale=False, return_alignments=False, print_progress=False):

    if ids_to_process is None:
        ids_to_process = range(len(poem_boundaries)-1)
    pbar = tqdm.tqdm(total=len(ids_to_process)) if print_progress else None
    
    for i in ids_to_process:
        logging.debug('Processing: {}'.format(poem_ids[i]))
        sim_result = similarity_with_splitting(
            m[poem_boundaries[i]:poem_boundaries[i+1],],
            m[poem_boundaries[i+1]:],
            poem_boundaries[(i+1):]-poem_boundaries[i+1],
            MAX_SIZE,
            threshold=threshold, rescale=rescale,
            return_alignments=return_alignments,
            sim_raw_thr=sim_raw_thr)
        (sim_raw, a, w) = sim_result if return_alignments \
                          else (sim_result, None, None)
        p1_length = poem_boundaries[i+1]-poem_boundaries[i]
        sim_l = sim_raw / p1_length
        p2_lengths = poem_boundaries[(i+2):]-poem_boundaries[(i+1):-1]
        sim_r = sim_raw / p2_lengths
        sim_sym = 2*sim_raw / (p2_lengths + p1_length)
        for j in torch.argwhere((sim_raw > sim_raw_thr) \
                                & ((sim_l > sim_onesided_thr) \
                                    | (sim_r > sim_onesided_thr)) \
                                & (sim_sym > sim_sym_thr)
                               ).flatten():
            als = None
            if return_alignments:
                a_j = a[poem_boundaries[i+j+1]-poem_boundaries[i+1]:\
                        poem_boundaries[i+j+2]-poem_boundaries[i+1]]
                w_j = w[poem_boundaries[i+j+1]-poem_boundaries[i+1]:\
                        poem_boundaries[i+j+2]-poem_boundaries[i+1]]
                als = [(int(a_j[k]), int(k), float(w_j[k])) \
                       for k in torch.where(a_j > -1)[0]]
            yield (i, int(i+j+1), float(sim_raw[j]), float(sim_l[j]),
                   float(sim_r[j]), float(sim_sym[j]), als)
        # update the progress bar
        if pbar is not None:
            pbar.update()


def format_als_for_output(als, p1_idx, p2_idx, poem_ids, verses,
                          add_texts=False):
    p1_id = poem_ids[p1_idx]
    p2_id = poem_ids[p2_idx]
    if add_texts:
        return itertools.chain(
                ((p1_id, verses[poem_boundaries[p1_idx]+pos1][1],
                  verses[poem_boundaries[p1_idx]+pos1][2],
                  p2_id, verses[poem_boundaries[p2_idx]+pos2][1],
                  verses[poem_boundaries[p2_idx]+pos2][2], w) \
                 for pos1, pos2, w in als),
                ((p2_id, verses[poem_boundaries[p2_idx]+pos2][1],
                  verses[poem_boundaries[p2_idx]+pos2][2],
                  p1_id, verses[poem_boundaries[p1_idx]+pos1][1], \
                  verses[poem_boundaries[p1_idx]+pos1][2], w)
                 for pos1, pos2, w in als))
    else:
        return itertools.chain(
                ((p1_id, verses[poem_boundaries[p1_idx]+pos1][1],
                  p2_id, verses[poem_boundaries[p2_idx]+pos2][1], w) \
                 for pos1, pos2, w in als),
                ((p2_id, verses[poem_boundaries[p2_idx]+pos2][1],
                  p1_id, verses[poem_boundaries[p1_idx]+pos1][1], w) \
                 for pos1, pos2, w in als))


def setup_logging(logfile, level):
    if logfile is None:
        logging.basicConfig(level=level,
                            format='%(asctime)s %(levelname)s %(message)s',
                            datefmt='%d.%m.%Y %H:%M:%S')
    else:
        logging.basicConfig(filename=logfile, level=level,
                            format='%(asctime)s %(levelname)s %(message)s',
                            datefmt='%d.%m.%Y %H:%M:%S')


def parse_arguments():
    parser = argparse.ArgumentParser(
        description='Align large collections of versified poetry.')
    parser.add_argument(
        '-a', '--alignments-file', type=str, default=None,
        help='File to write verse-level alignments to.')
    parser.add_argument(
        '-d', '--dim', type=int, default=450,
        help='The number of dimensions of n-gram vectors for verses')
    parser.add_argument(
        '-e', '--embeddings', metavar='FILE', default=None,
        help='Use the verse embeddings from FILE (a NumPy matrix with one'
             ' row per input verse) instead of n-gram vectors.')
    parser.add_argument(
        '-g', '--use-gpu', action='store_true',
        help='Use the GPU for computation.')
    parser.add_argument(
        '-i', '--input-file', type=str, default=None,
        help='Input file (CSV: poem_id, pos, text)')
    parser.add_argument('--logfile', metavar='FILE')
    parser.add_argument('-L', '--logging-level', metavar='LEVEL',
                        default='WARNING', 
                        choices=['ERROR', 'WARNING', 'INFO', 'DEBUG'])
    parser.add_argument(
        '-n', type=int, default=2,
        help='The size (`n`) of the n-grams (default: 2, i.e. ngrams).')
    parser.add_argument(
        '-j', '--job-id', type=int, default=None,
        help='Zero-based job number if using multi-process parallelization (0 <= job-id < jobs).')
    parser.add_argument(
        '-J', '--jobs', type=int, default=None,
        help='Overall number of jobs if using multi-process parallelization.')
    parser.add_argument(
        '-o', '--output-file', type=str, default=None,
        help='Output file.')
    parser.add_argument(
        '-p', '--print-progress', action='store_true',
        help='Print a progress bar.')
    parser.add_argument(
        '-r', '--rescale', action='store_true',
        help='After applying the threshold, rescale the verse similarities'
             ' to [0, 1].')
    parser.add_argument(
        '-t', '--threshold', type=float, default=0.5,
        help='Minimum verse cosine similarity to consider (default=0.5).')
    parser.add_argument(
        '-T', '--print-texts', action='store_true',
        help='Print texts of the aligned verses.')
    parser.add_argument(
        '-x', '--regex', type=str, default=None, metavar='REGEX',
        help='Process only pairs where at least one poem ID matches REGEX.')
    parser.add_argument(
        '-w', '--weighting', choices=['plain', 'sqrt', 'binary'],
        default='plain', help='Weighting of n-gram frequencies.')
    parser.add_argument(
        '--sim-raw-thr', type=float, default=2.0,
        help='Threshold on raw similarity (default=2).')
    parser.add_argument(
        '--sim-onesided-thr', type=float, default=0.1,
        help='Threshold on one-sided similarity (default=0.1).')
    parser.add_argument(
        '--sim-sym-thr', type=float, default=0,
        help='Threshold on symmetric similarity (default=0).')
    return parser.parse_args()


if __name__ == '__main__':
    args = parse_arguments()
    setup_logging(args.logfile, args.logging_level)
    
    verses = read_input(args.input_file)
    if args.regex is not None:
        if args.embeddings is not None:
            raise RuntimeError('--regex is not supported with --embeddings')
        verses = move_to_beginning(verses, args.regex)

    if args.embeddings is not None:
        logging.info('loading embeddings')
        m = torch.from_numpy(np.load(args.embeddings)).float()
        if m.shape[0] != len(verses):
            raise RuntimeError(
                'The number of embeddings ({}) does not match the number'
                ' of verses ({})!'.format(m.shape[0], len(verses)))
    else:
        logging.info('starting vectorization')
        m = vectorize([v[2] for v in verses], n=args.n, dim=args.dim,
                      weighting=args.weighting)
        m = torch.from_numpy(m)
        logging.info('vectorization completed')
    poem_boundaries = [0] \
        + [i+1 for i in range(len(verses)-1) if verses[i][0] != verses[i+1][0]] \
        + [len(verses)]
    poem_ids = [verses[i][0] for i in poem_boundaries[:-1]]
    
    if args.use_gpu:
        logging.info('using torch on GPU')
        import torch.cuda
        poem_boundaries_a = torch.tensor(poem_boundaries).cuda()
        m = torch.tensor(m, dtype=torch.float16).cuda()
    else:
        logging.info('using torch on CPU')
        poem_boundaries_a = torch.tensor(poem_boundaries)
    
    ids_to_process = []
    if args.regex is not None:
        pattern = re.compile(args.regex)
        ids_to_process = [i for i in range(len(poem_ids)) if pattern.match(poem_ids[i])]
    else:
        ids_to_process = list(range(len(poem_ids)))

    if args.job_id is not None and args.jobs is not None and args.job_id < args.jobs:
        ids_to_process = [\
            ids_to_process[i] \
            for i in range(args.job_id, len(ids_to_process), args.jobs)]
    elif args.job_id is not None or args.jobs is not None:
        raise RuntimeError(
            'Either both or none of --job-id and --jobs must be given'
            ' and --job-id < --jobs must hold!')

    logging.info('starting similarity computation')

    sims = compute_similarities(
        m, poem_boundaries_a, poem_ids,
        ids_to_process=ids_to_process,
        threshold=args.threshold,
        rescale=args.rescale,
        print_progress=args.print_progress,
        return_alignments=(args.alignments_file is not None),
        sim_raw_thr=args.sim_raw_thr,
        sim_onesided_thr=args.sim_onesided_thr,
        sim_sym_thr=args.sim_sym_thr,
    )
    
    alfp, a_writer = None, None
    if args.alignments_file is not None:
        alfp = open(args.alignments_file, 'w+')
        a_writer = csv.writer(alfp, delimiter=',', lineterminator='\n')
        if args.print_texts:
            a_writer.writerow(('poem_id_1', 'pos1', 'text1',
                               'poem_id_2', 'pos2', 'text2', 'sim'))
        else:
            a_writer.writerow(('poem_id_1', 'pos1', 'poem_id_2', 'pos2', 'sim'))

    try:
        t1 = time.time()
        if args.output_file is None:
            writer = csv.writer(sys.stdout, delimiter=',', lineterminator='\n')
            writer.writerow(('poem_id_1', 'poem_id_2', 'sim_raw', 'sim_l', 'sim_r', 'sim'))
            for p1_idx, p2_idx, sim_raw, sim_l, sim_r, sim, als in sims:
                writer.writerow((poem_ids[p1_idx], poem_ids[p2_idx],
                                 sim_raw, sim_l, sim_r, sim))
                writer.writerow((poem_ids[p2_idx], poem_ids[p1_idx],
                                 sim_raw, sim_r, sim_l, sim))
                if a_writer is not None:
                    rows = format_als_for_output(
                      als, p1_idx, p2_idx,
                      poem_ids, verses, add_texts=args.print_texts)
                    a_writer.writerows(rows)
        else:
            with open(args.output_file, 'w+') as outfp:
                writer = csv.writer(outfp, delimiter=',', lineterminator='\n')
                writer.writerow(('poem_id_1', 'poem_id_2', 'sim_raw', 'sim_l', 'sim_r', 'sim'))
                for p1_idx, p2_idx, sim_raw, sim_l, sim_r, sim, als in sims:
                    writer.writerow((poem_ids[p1_idx], poem_ids[p2_idx],
                                     sim_raw, sim_l, sim_r, sim))
                    writer.writerow((poem_ids[p2_idx], poem_ids[p1_idx],
                                     sim_raw, sim_r, sim_l, sim))
                    if a_writer is not None:
                        rows = format_als_for_output(
                          als, p1_idx, p2_idx,
                          poem_ids, verses, add_texts=args.print_texts)
                        a_writer.writerows(rows)
    
        t2 = time.time()
        logging.info('similarity computation completed in {} s'.format(t2-t1))

    except Exception as e:
        logging.critical(str(e))
        raise
    finally:
        if alfp:
            alfp.close()

