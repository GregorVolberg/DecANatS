"""
Reproduces every number I (Claude) reported for the DecANatS neurips
corner-classification analysis, directly from the .fig files saved by
read_and_analyse_2/3/4.m in md_images/.

Why this works at all: MATLAB .fig files are MAT-files. The ones here were
saved in the legacy "hgS_070000" graphics-object format (pre-R2014b style),
which scipy.io.loadmat can read as a plain nested struct. Each line/image
plotted by mv_plot_result() ends up as a child graphics object with
properties CData / XData / YData holding the actual plotted matrix and
axis values -- i.e. the real numbers behind the picture, not just pixels.

Requirements: numpy, scipy  (pip install numpy scipy)

Usage:
    python3 verify_neurips_numbers.py /path/to/DecANatS-main/md_images
"""

import sys
import numpy as np
import scipy.io as sio


def get_image_properties(root):
    """Walk figure -> axes -> children and return the properties of the
    first 'image' object (this is where mv_plot_result puts the data)."""
    axes = root.children
    if isinstance(axes, np.ndarray):
        axes = axes[0]
    for ch in np.atleast_1d(axes.children):
        if ch.type == 'image':
            return ch.properties
    raise ValueError("no image object found in this figure")


def load_fig(path):
    """Returns (CData, XData, YData) = (values, time axis, freq axis)."""
    m = sio.loadmat(path, squeeze_me=True, struct_as_record=False)
    root = m['hgS_070000']
    props = get_image_properties(root)
    cdata = np.array(props.CData, dtype=float)   # shape (n_freq, n_time)
    xdata = np.array(props.XData, dtype=float)    # time axis, seconds
    ydata = np.array(props.YData, dtype=float)    # frequency axis, Hz
    return cdata, xdata, ydata


def main(md_images_dir):
    contrasts = ['door_vs_null', 'l_corner_vs_null', 'r_corner_vs_null',
                 'l_corner_vs_r_corner']
    defs = ['pos', 'opt', 'head']

    # ------------------------------------------------------------------
    # 1) Peak accuracy / peak t / %significant bins, per contrast x def
    #    (this reproduces the first results table)
    # ------------------------------------------------------------------
    print("=" * 100)
    print("TABLE 1: peak values per contrast x label-definition")
    print("=" * 100)
    header = (f"{'contrast':22s} {'def':5s} {'peak_t':>8s} {'t_at_time':>10s} "
              f"{'t_at_freq':>10s} {'%sig(t>2.26)':>13s} {'peak_acc':>9s} "
              f"{'acc_at_time':>12s} {'acc_at_freq':>12s}")
    print(header)

    results = {}
    for c in contrasts:
        results[c] = {}
        for d in defs:
            tfile = f"{md_images_dir}/{c}_lda_neurips_{d}_t.fig"
            afile = f"{md_images_dir}/{c}_lda_neurips_{d}.fig"
            tcd, txd, tyd = load_fig(tfile)
            acd, axd, ayd = load_fig(afile)
            assert tcd.shape == acd.shape, "accuracy/t maps have different shapes!"

            peak_t = np.nanmax(tcd)
            ti = np.unravel_index(np.nanargmax(tcd), tcd.shape)
            pct_sig = 100 * np.mean(tcd > 2.26)   # uncorrected p<.05, df=9, two-sided

            peak_acc = np.nanmax(acd)
            ai = np.unravel_index(np.nanargmax(acd), acd.shape)

            results[c][d] = dict(cdata_acc=acd, xdata=axd, ydata=ayd,
                                  cdata_t=tcd)

            print(f"{c:22s} {d:5s} {peak_t:8.2f} {txd[ti[1]]:10.2f} "
                  f"{tyd[ti[0]]:10.1f} {pct_sig:13.1f} {peak_acc:9.3f} "
                  f"{axd[ai[1]]:12.2f} {ayd[ai[0]]:12.1f}")

    # ------------------------------------------------------------------
    # 2) Frequency-averaged accuracy curves + their peaks
    #    (reproduces 54.3% / 64.0% / 62.6% and the interactive chart)
    # ------------------------------------------------------------------
    print()
    print("=" * 100)
    print("TABLE 2: frequency-averaged accuracy curves, peak over time")
    print("=" * 100)
    print(f"{'contrast':22s} {'def':5s} {'peak(4-30Hz avg)':>18s} {'peak(>6Hz avg)':>16s}")

    for c in ['l_corner_vs_null', 'r_corner_vs_null', 'l_corner_vs_r_corner']:
        for d in defs:
            acd = results[c][d]['cdata_acc']
            ayd = results[c][d]['ydata']
            acc_full = acd.mean(axis=0)                 # mean over ALL freq rows (4-30 Hz)
            mask = ayd > 6
            acc_ex6 = acd[mask, :].mean(axis=0)          # mean over freq > 6 Hz only
            print(f"{c:22s} {d:5s} {100*acc_full.max():17.1f}% {100*acc_ex6.max():15.1f}%")

    # ------------------------------------------------------------------
    # 3) Specific time points quoted in the draft (t=-3s, t=0s, opt, L-vs-R)
    # ------------------------------------------------------------------
    print()
    print("=" * 100)
    print("TABLE 3: l_corner_vs_r_corner / opt, accuracy curve at specific times")
    print("=" * 100)
    acd = results['l_corner_vs_r_corner']['opt']['cdata_acc']
    axd = results['l_corner_vs_r_corner']['opt']['xdata']
    ayd = results['l_corner_vs_r_corner']['opt']['ydata']
    acc_full = acd.mean(axis=0)
    for t0 in [-3.0, 0.0]:
        idx = int(np.argmin(np.abs(axd - t0)))
        print(f"t={axd[idx]:+.2f}s: accuracy (4-30Hz avg) = {100*acc_full[idx]:.1f}%")

    # ------------------------------------------------------------------
    # 4) Bonferroni-corrected critical t, for context
    # ------------------------------------------------------------------
    print()
    print("=" * 100)
    print("TABLE 4: Bonferroni-corrected critical t (df=9, two-sided)")
    print("=" * 100)
    try:
        from scipy import stats
        df = 9
        n_bins = 27 * 301
        n_family = n_bins * len(defs) * len(contrasts)
        for label, n in [("per contrast x def (27x301 bins)", n_bins),
                          ("across all 12 contrast/def combos", n_family)]:
            alpha_bonf = 0.05 / n
            tcrit = stats.t.ppf(1 - alpha_bonf / 2, df)
            print(f"{label}: n={n}, t_crit = {tcrit:.2f}")
    except ImportError:
        print("scipy.stats not available, skipping")


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1].rstrip('/'))
