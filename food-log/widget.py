#!/usr/bin/env python3
"""Render today's calories and macros as a phone-sized PNG, like a tracker widget.

    .venv/bin/python food-log/widget.py            # today -> food-log/widget.png
    .venv/bin/python food-log/widget.py --date yesterday --out /tmp/x.png

Kept separate from fl.py so the log itself stays stdlib-only.
"""

import argparse
import os
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Wedge, FancyBboxPatch

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fl  # noqa: E402

BG = "#1b1f2e"
TRACK = "#2b3044"
TEXT = "#f4f5f8"
MUTED = "#9aa0b4"
KCAL = "#4fd1c5"
COLORS = {"protein": "#5fe3a1", "carbs": "#4fc3f7", "fat": "#c58bf2", "fiber": "#f5c86b"}
OVER = "#ff7a7a"


def render(day, out_path):
    conn = fl.project()
    totals = fl.totals_for(conn, day, day)
    targets = fl.get_targets(conn, day)
    note = conn.execute("SELECT note FROM day_notes WHERE day = ?", (day,)).fetchone()
    rows = [r for r in fl.macro_status(conn, totals, day) if r["key"] != "kcal"]
    conn.close()

    kcal_target = targets.get("kcal")
    eaten = totals["kcal"]
    left = (kcal_target - eaten) if kcal_target else None
    frac = min(eaten / kcal_target, 1.0) if kcal_target else 0.0
    over = kcal_target is not None and eaten > kcal_target

    fig = plt.figure(figsize=(4.2, 5.6), dpi=200, facecolor=BG)
    ax = fig.add_axes([0, 0, 1, 1])
    ax.set_xlim(0, 100)
    ax.set_ylim(0, 133)
    ax.set_facecolor(BG)
    ax.axis("off")

    # ring
    cx, cy, r, w = 50, 92, 30, 7
    ax.add_patch(Wedge((cx, cy), r, 0, 360, width=w, facecolor=TRACK, edgecolor="none"))
    if frac > 0:
        ax.add_patch(Wedge((cx, cy), r, 90 - 360 * frac, 90, width=w,
                           facecolor=OVER if over else KCAL, edgecolor="none"))

    if left is None:
        big, small = fl.fmt(eaten), "kcal eaten (no target)"
    elif over:
        big, small = fl.fmt(-left), "kcal OVER"
    else:
        big, small = fl.fmt(left), "kcal left"
    ax.text(cx, cy + 3, big, ha="center", va="center", fontsize=30, color=TEXT,
            fontweight="bold")
    ax.text(cx, cy - 7, small, ha="center", va="center", fontsize=10, color=MUTED)
    if kcal_target:
        ax.text(cx, cy - 14, "%s of %s" % (fl.fmt(eaten), fl.fmt(kcal_target)),
                ha="center", va="center", fontsize=8.5, color=MUTED)

    # macro rows
    y = 50
    for r in rows:
        key, got, tgt = r["key"], r["eaten"], r["target"]
        col = COLORS.get(key, MUTED)
        ax.add_patch(plt.Circle((9, y), 2.0, color=col))
        ax.text(15, y, r["label"].capitalize(), ha="left", va="center", fontsize=10, color=TEXT)
        if tgt is not None:
            rem = r["left"]
            if r["floor"]:
                right = "met" if rem <= 0 else "%s g to go" % fl.fmt(rem)
                bad = False
            else:
                right = ("%s g left" % fl.fmt(rem)) if rem >= 0 else ("%s g over" % fl.fmt(-rem))
                bad = rem < 0
            ax.text(91, y, right, ha="right", va="center", fontsize=10,
                    color=OVER if bad else TEXT)
            ax.text(91, y - 4.6, "%s / %s g" % (fl.fmt(got), fl.fmt(tgt)), ha="right",
                    va="center", fontsize=7, color=MUTED)
            f = min(got / tgt, 1.0) if tgt > 0 else 0
            ax.add_patch(FancyBboxPatch((15, y - 8.2), 76, 1.9, boxstyle="round,pad=0,rounding_size=0.95",
                                        facecolor=TRACK, edgecolor="none"))
            if f > 0:
                ax.add_patch(FancyBboxPatch((15, y - 8.2), 76 * f, 1.9,
                                            boxstyle="round,pad=0,rounding_size=0.95",
                                            facecolor=OVER if bad else col, edgecolor="none"))
        else:
            ax.text(91, y, "%s g" % fl.fmt(got), ha="right", va="center", fontsize=10, color=TEXT)
        y -= 12.5

    footer = day
    ax.text(50, 3.5, footer, ha="center", va="center", fontsize=7.5, color=MUTED)
    if note:
        ax.text(50, 128, note["note"][:60], ha="center", va="center", fontsize=6.5, color=MUTED)

    fig.savefig(out_path, facecolor=BG, dpi=200)
    plt.close(fig)
    return out_path


def main():
    p = argparse.ArgumentParser(description="render the day as a widget image")
    p.add_argument("--date", help="YYYY-MM-DD, today, or yesterday (default today)")
    p.add_argument("--out", default=os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                                 "widget.png"))
    args = p.parse_args()
    day = fl.parse_day(args.date)
    print(render(day, args.out))


if __name__ == "__main__":
    main()
