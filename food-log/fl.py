#!/usr/bin/env python3
"""Minimal personal food log. Stdlib only.

Source of truth is food-log/events.jsonl, an append-only text log that git can
merge. SQLite is built in memory on every run purely to query it, so there is no
database file to sync and no binary merge conflicts.

Run `python3 food-log/fl.py --help` for commands.
"""

import argparse
import json
import os
import re
import secrets
import sqlite3
import subprocess
import sys
from datetime import date, datetime, timedelta

HERE = os.path.dirname(os.path.abspath(__file__))
EVENTS_PATH = os.environ.get("FOOD_LOG_EVENTS", os.path.join(HERE, "events.jsonl"))

MACROS = ("kcal", "protein", "carbs", "fat", "fiber")

GRAM_UNITS = {"g", "gram", "grams", "ml", "milliliter", "milliliters"}
SERVING_UNITS = {
    "serving", "servings", "scoop", "scoops", "slice", "slices",
    "piece", "pieces", "unit", "units", "each", "item", "items",
    "cup", "cups", "tbsp", "tsp", "can", "cans", "bar", "bars",
    "egg", "eggs", "packet", "packets", "bottle", "bottles",
}

SCHEMA = """
CREATE TABLE foods (
    id            TEXT PRIMARY KEY,
    name          TEXT NOT NULL,
    aliases       TEXT NOT NULL DEFAULT '',
    basis         TEXT NOT NULL,
    serving_grams REAL,
    serving_label TEXT,
    kcal          REAL NOT NULL,
    protein       REAL NOT NULL,
    carbs         REAL NOT NULL,
    fat           REAL NOT NULL,
    fiber         REAL,
    fiber_soluble   REAL,
    fiber_insoluble REAL,
    micros        TEXT,
    source        TEXT,
    notes         TEXT,
    created_at    TEXT
);
CREATE TABLE entries (
    id         TEXT PRIMARY KEY,
    seq        INTEGER NOT NULL,
    food_id    TEXT,
    label      TEXT NOT NULL,
    qty        REAL NOT NULL,
    unit       TEXT NOT NULL,
    grams      REAL,
    kcal       REAL NOT NULL,
    kcal_label REAL,
    kcal_adjust REAL NOT NULL DEFAULT 0,
    protein    REAL NOT NULL,
    carbs      REAL NOT NULL,
    fat        REAL NOT NULL,
    fiber      REAL,
    fiber_soluble   REAL,
    fiber_insoluble REAL,
    micros     TEXT,
    eaten_on   TEXT NOT NULL,
    eaten_at   TEXT,
    meal       TEXT,
    source     TEXT,
    confidence TEXT,
    note       TEXT
);
CREATE INDEX idx_entries_day ON entries (eaten_on);
CREATE TABLE profile (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE day_notes (day TEXT PRIMARY KEY, note TEXT NOT NULL);
"""

FOOD_FIELDS = ("name", "aliases", "basis", "serving_grams", "serving_label", "kcal",
               "protein", "carbs", "fat", "fiber", "fiber_soluble", "fiber_insoluble",
               "micros", "source", "notes")
ENTRY_FIELDS = ("food_id", "label", "qty", "unit", "grams", "kcal", "protein", "carbs",
                "fat", "fiber", "fiber_soluble", "fiber_insoluble", "micros", "eaten_on",
                "eaten_at", "meal", "source", "confidence", "note")

SCALED = ("kcal", "protein", "carbs", "fat", "fiber", "fiber_soluble", "fiber_insoluble")


FIBER_MODES = {
    "label": "fiber at 4 kcal/g, calories exactly as printed on the label",
    "half": "fiber at 2 kcal/g, the EU convention and Cronometer's usual setting",
    "net": "fiber at 0 kcal/g, net-carb style, nothing from fiber counts",
    "split": "insoluble at 0 and soluble at 2 kcal/g, needs the split recorded",
}
DEFAULT_FIBER_MODE = "half"


def fiber_adjustment(fiber, soluble, insoluble, mode):
    """Calories to remove from a figure that counted every gram of fiber at 4 kcal.

    Which convention is right is genuinely unsettled, so this is a setting rather
    than a decision. Because it is applied when the log is replayed, changing the
    mode re-scores every day already logged.
    """
    sol = soluble or 0.0
    insol = insoluble or 0.0
    total = fiber if fiber is not None else (sol + insol)
    total = total or 0.0
    if mode == "label":
        return 0.0
    if mode == "half":
        return round(2.0 * total, 2)
    if mode == "net":
        return round(4.0 * total, 2)
    unspecified = max(0.0, total - sol - insol)
    return round(4.0 * insol + 2.0 * (sol + unspecified), 2)


def fiber_mode_of(events):
    mode = DEFAULT_FIBER_MODE
    for ev in events:
        if ev.get("type") == "profile_set" and ev.get("key") == "fiber_mode":
            if ev.get("value") in FIBER_MODES:
                mode = ev["value"]
    return mode


def die(msg):
    sys.stderr.write("error: " + msg + "\n")
    sys.exit(1)


def now_local():
    return datetime.now().astimezone().isoformat(timespec="seconds")


def new_id():
    return secrets.token_hex(3)


# ---------------------------------------------------------------- event log


def read_events():
    if not os.path.exists(EVENTS_PATH):
        return []
    events, seen = [], set()
    with open(EVENTS_PATH, "r") as fh:
        for lineno, line in enumerate(fh, 1):
            line = line.strip()
            if not line or line.startswith("<<<<<<<") or line.startswith(">>>>>>>") \
                    or line.startswith("======="):
                continue
            try:
                ev = json.loads(line)
            except ValueError:
                sys.stderr.write("warning: skipping unparseable line %d\n" % lineno)
                continue
            eid = ev.get("id")
            if eid and eid in seen:
                continue
            if eid:
                seen.add(eid)
            events.append(ev)
    events.sort(key=lambda e: e.get("ts") or "")
    return events


def append_event(ev):
    ev.setdefault("id", new_id())
    ev.setdefault("ts", now_local())
    needs_nl = os.path.exists(EVENTS_PATH) and os.path.getsize(EVENTS_PATH) > 0
    with open(EVENTS_PATH, "a") as fh:
        if needs_nl:
            with open(EVENTS_PATH, "rb") as check:
                check.seek(-1, os.SEEK_END)
                if check.read(1) != b"\n":
                    fh.write("\n")
        fh.write(json.dumps(ev, sort_keys=True) + "\n")
    return ev


def project():
    """Replay the event log into an in-memory SQLite database."""
    conn = sqlite3.connect(":memory:")
    conn.row_factory = sqlite3.Row
    conn.executescript(SCHEMA)

    events = read_events()
    mode = fiber_mode_of(events)
    seq = 0
    for ev in events:
        kind = ev.get("type")
        if kind == "food_add":
            cols = ["id"] + list(FOOD_FIELDS) + ["created_at"]
            vals = [ev["id"]] + [ev.get(f) for f in FOOD_FIELDS] + [ev.get("ts")]
            conn.execute(
                "INSERT OR REPLACE INTO foods (%s) VALUES (%s)"
                % (",".join(cols), ",".join("?" * len(cols))), vals)
        elif kind == "food_update":
            fields = ev.get("fields") or {}
            fields = {k: v for k, v in fields.items() if k in FOOD_FIELDS}
            if fields:
                conn.execute(
                    "UPDATE foods SET %s WHERE id = ?"
                    % ", ".join("%s = ?" % k for k in fields),
                    list(fields.values()) + [ev.get("target")])
        elif kind == "food_delete":
            conn.execute("DELETE FROM foods WHERE id = ?", (ev.get("target"),))
        elif kind == "entry_add":
            seq += 1
            row = dict((f, ev.get(f)) for f in ENTRY_FIELDS)
            adjust = fiber_adjustment(row["fiber"], row["fiber_soluble"],
                                      row["fiber_insoluble"], mode)
            row["kcal_label"] = row["kcal"]
            row["kcal"] = max(0.0, round((row["kcal"] or 0.0) - adjust, 2))
            row["kcal_adjust"] = adjust
            row["id"], row["seq"] = ev["id"], seq
            cols = list(row.keys())
            conn.execute(
                "INSERT OR REPLACE INTO entries (%s) VALUES (%s)"
                % (",".join(cols), ",".join("?" * len(cols))),
                [row[c] for c in cols])
        elif kind == "entry_delete":
            conn.execute("DELETE FROM entries WHERE id = ?", (ev.get("target"),))
        elif kind == "profile_set":
            conn.execute(
                "INSERT INTO profile (key,value) VALUES (?,?) "
                "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                (ev.get("key"), ev.get("value")))
        elif kind == "day_note":
            conn.execute(
                "INSERT INTO day_notes (day,note) VALUES (?,?) "
                "ON CONFLICT(day) DO UPDATE SET note = excluded.note",
                (ev.get("day"), ev.get("note")))
    conn.commit()
    return conn


# ---------------------------------------------------------------- helpers


def today_str():
    return date.today().isoformat()


def parse_day(value):
    if value is None:
        return today_str()
    v = value.strip().lower()
    if v == "today":
        return today_str()
    if v == "yesterday":
        return (date.today() - timedelta(days=1)).isoformat()
    try:
        return date.fromisoformat(v).isoformat()
    except ValueError:
        die("bad date %r, expected YYYY-MM-DD, 'today' or 'yesterday'" % value)


def parse_qty(text):
    """'150g' / '150 g' / '1.5 servings' / '2 scoops' / '3' -> (qty, unit)."""
    m = re.match(r"^\s*([0-9]*\.?[0-9]+)\s*([a-zA-Z]*)\s*$", text or "")
    if not m:
        die("bad quantity %r, expected something like '150g' or '2 scoops'" % text)
    return float(m.group(1)), (m.group(2) or "serving").lower()


def norm(s):
    return re.sub(r"\s+", " ", (s or "").strip().lower())


def find_food(conn, query):
    q = norm(query)
    rows = conn.execute("SELECT * FROM foods").fetchall()

    by_id = [r for r in rows if r["id"] == q or r["id"].startswith(q)]
    exact = [r for r in rows if norm(r["name"]) == q]
    if len(exact) == 1:
        return exact[0]

    alias_hits = [r for r in rows
                  if q in [norm(a) for a in (r["aliases"] or "").split(",") if a.strip()]]
    if len(alias_hits) == 1:
        return alias_hits[0]

    partial = [r for r in rows if q and q in norm(r["name"])]
    if len(partial) == 1:
        return partial[0]
    if len(by_id) == 1:
        return by_id[0]

    candidates = exact or alias_hits or partial or by_id
    if not candidates:
        die("no food matching %r. Add it with 'food add' first." % query)
    die("%r is ambiguous, matches: %s"
        % (query, ", ".join("%s (%s)" % (r["name"], r["id"]) for r in candidates)))


def find_entry(conn, ref):
    rows = conn.execute("SELECT * FROM entries WHERE id = ? OR id LIKE ?",
                        (ref, ref + "%")).fetchall()
    if not rows:
        die("no entry %r" % ref)
    if len(rows) > 1:
        die("%r matches several entries: %s" % (ref, ", ".join(r["id"] for r in rows)))
    return rows[0]


def scale_micros(raw, factor):
    if not raw:
        return None
    try:
        data = json.loads(raw)
    except (ValueError, TypeError):
        return None
    if not isinstance(data, dict):
        return None
    return json.dumps({k: round(v * factor, 4) for k, v in data.items()
                       if isinstance(v, (int, float))})


def resolve_amount(food, qty, unit):
    """Return (factor, grams). factor multiplies the food's stored macro basis."""
    basis, serving_grams = food["basis"], food["serving_grams"]
    label = norm(food["serving_label"])

    if unit in GRAM_UNITS:
        if basis == "100g":
            return qty / 100.0, qty
        if not serving_grams:
            die("%s is stored per serving with no serving grams, so it cannot be logged "
                "in grams. Log it as servings, or set --serving-grams via 'food update'."
                % food["name"])
        return qty / serving_grams, qty

    plurals = {label, label + "s", label + "es"}
    if label.endswith("y"):
        plurals.add(label[:-1] + "ies")
    matches_label = bool(label) and unit in plurals
    if unit in SERVING_UNITS or matches_label or unit == "":
        if basis == "serving":
            return qty, (qty * serving_grams if serving_grams else None)
        if not serving_grams:
            die("%s is stored per 100g with no serving grams, so '%s' is not convertible. "
                "Log it in grams, or set --serving-grams via 'food update'."
                % (food["name"], unit))
        return qty * serving_grams / 100.0, qty * serving_grams

    die("unknown unit %r for %s" % (unit, food["name"]))


def fmt(value, digits=0):
    if value is None:
        return "-"
    if digits == 0:
        return str(int(round(value)))
    return ("%." + str(digits) + "f") % value


def trim(value):
    return fmt(value, 2).rstrip("0").rstrip(".")


def current_fiber_mode(conn):
    row = conn.execute("SELECT value FROM profile WHERE key = 'fiber_mode'").fetchone()
    if row and row["value"] in FIBER_MODES:
        return row["value"]
    return DEFAULT_FIBER_MODE


def get_targets(conn):
    out = {}
    for r in conn.execute("SELECT key, value FROM profile WHERE key LIKE 'target_%'"):
        try:
            out[r["key"][len("target_"):]] = float(r["value"])
        except ValueError:
            continue
    return out


def totals_for(conn, start, end):
    row = conn.execute(
        "SELECT COUNT(*) AS n, COALESCE(SUM(kcal),0) AS kcal, "
        "COALESCE(SUM(protein),0) AS protein, COALESCE(SUM(carbs),0) AS carbs, "
        "COALESCE(SUM(fat),0) AS fat, COALESCE(SUM(fiber),0) AS fiber, "
        "COALESCE(SUM(kcal_label),0) AS kcal_label, "
        "COALESCE(SUM(kcal_adjust),0) AS kcal_adjust "
        "FROM entries WHERE eaten_on BETWEEN ? AND ?", (start, end)).fetchone()
    return dict(row)


def sum_micros(conn, start, end):
    out = {}
    for r in conn.execute(
            "SELECT micros FROM entries WHERE eaten_on BETWEEN ? AND ? "
            "AND micros IS NOT NULL", (start, end)):
        try:
            data = json.loads(r["micros"])
        except (ValueError, TypeError):
            continue
        for k, v in (data or {}).items():
            if isinstance(v, (int, float)):
                out[k] = out.get(k, 0) + v
    return out


def target_line(conn, totals):
    targets = get_targets(conn)
    if not targets:
        return None
    parts = []
    for key in MACROS:
        if key in targets:
            left = targets[key] - (totals[key] or 0)
            parts.append("%s %s %s" % (key, fmt(abs(left)),
                                       "left" if left >= 0 else "OVER"))
    return "vs target: " + ", ".join(parts)


# ---------------------------------------------------------------- commands


def cmd_init(args, conn):
    if not os.path.exists(EVENTS_PATH):
        open(EVENTS_PATH, "a").close()
    print("log ready at %s (%d events)" % (EVENTS_PATH, len(read_events())))


def cmd_food_add(args, conn):
    if args.micros:
        try:
            json.loads(args.micros)
        except ValueError:
            die("--micros must be valid JSON, e.g. '{\"sodium_mg\": 400}'")
    dupe = conn.execute("SELECT name FROM foods WHERE lower(name) = ?",
                        (norm(args.name),)).fetchone()
    if dupe and not args.force:
        die("a food named %r already exists. Use 'food update', or --force to add anyway."
            % dupe["name"])
    if args.basis == "serving" and args.serving_grams is None:
        sys.stderr.write("note: no --serving-grams, this food can only be logged "
                         "in servings\n")

    ev = {"type": "food_add"}
    for f in FOOD_FIELDS:
        ev[f] = getattr(args, f, None)
    ev["name"] = args.name.strip()
    ev["aliases"] = args.aliases or ""
    ev["source"] = args.source or "manual"
    ev = append_event(ev)
    per = "100g" if args.basis == "100g" else (args.serving_label or "serving")
    print("added %s %s -> per %s: %s kcal, P%s C%s F%s"
          % (ev["id"], ev["name"], per, fmt(args.kcal), fmt(args.protein),
             fmt(args.carbs), fmt(args.fat)))


def cmd_food_update(args, conn):
    food = find_food(conn, args.name)
    fields = {}
    for key in FOOD_FIELDS:
        if key == "name":
            continue
        value = getattr(args, key, None)
        if value is not None:
            fields[key] = value
    if args.rename:
        fields["name"] = args.rename.strip()
    if not fields:
        die("nothing to update, pass at least one field")
    append_event({"type": "food_update", "target": food["id"], "fields": fields})
    print("updated %s (%s)" % (food["name"], ", ".join(sorted(fields))))
    print("note: entries already logged keep the macros they were logged with")


def cmd_food_list(args, conn):
    if args.query:
        q = "%" + norm(args.query) + "%"
        rows = conn.execute("SELECT * FROM foods WHERE lower(name) LIKE ? "
                            "OR lower(aliases) LIKE ? ORDER BY name", (q, q)).fetchall()
    else:
        rows = conn.execute("SELECT * FROM foods ORDER BY name").fetchall()
    if not rows:
        print("no foods yet")
        return
    if args.json:
        print(json.dumps([dict(r) for r in rows], indent=2))
        return
    print("%-8s %-30s %-9s %6s %6s %6s %6s  %s"
          % ("id", "name", "per", "kcal", "P", "C", "F", "aliases"))
    for r in rows:
        per = "100g" if r["basis"] == "100g" else (r["serving_label"] or "serving")
        print("%-8s %-30s %-9s %6s %6s %6s %6s  %s"
              % (r["id"], r["name"][:30], per[:9], fmt(r["kcal"]), fmt(r["protein"]),
                 fmt(r["carbs"]), fmt(r["fat"]), r["aliases"] or ""))


def cmd_food_rm(args, conn):
    food = find_food(conn, args.name)
    append_event({"type": "food_delete", "target": food["id"]})
    print("removed %s (past entries kept)" % food["name"])


def cmd_log(args, conn):
    qty, unit = parse_qty(args.amount)
    food = find_food(conn, args.food)
    factor, grams = resolve_amount(food, qty, unit)

    ev = {
        "type": "entry_add", "food_id": food["id"], "label": food["name"],
        "qty": qty, "unit": unit, "grams": grams,
        "micros": scale_micros(food["micros"], factor),
        "eaten_on": parse_day(args.date), "eaten_at": args.time or now_local(),
        "meal": args.meal, "source": args.source or "text",
        "confidence": args.confidence or "high", "note": args.note,
    }
    for key in SCALED:
        base = food[key]
        ev[key] = None if base is None else round(base * factor, 2)
    ev = append_event(ev)
    adjust = fiber_adjustment(ev["fiber"], ev["fiber_soluble"], ev["fiber_insoluble"],
                              current_fiber_mode(conn))
    net = max(0.0, (ev["kcal"] or 0.0) - adjust)
    print("%s  %s %s%s -> %s kcal%s, P%s C%s F%s  [%s]"
          % (ev["id"], food["name"], trim(qty), unit, fmt(net),
             (" (%s label, -%s fiber)" % (fmt(ev["kcal"]), fmt(adjust))) if adjust else "",
             fmt(ev["protein"]), fmt(ev["carbs"]), fmt(ev["fat"]), ev["eaten_on"]))


def cmd_logx(args, conn):
    if args.micros:
        try:
            json.loads(args.micros)
        except ValueError:
            die("--micros must be valid JSON")
    ev = append_event({
        "type": "entry_add", "food_id": None, "label": args.label.strip(),
        "qty": 1, "unit": "serving", "grams": args.grams,
        "kcal": args.kcal, "protein": args.protein, "carbs": args.carbs,
        "fat": args.fat, "fiber": args.fiber, "micros": args.micros,
        "fiber_soluble": args.fiber_soluble, "fiber_insoluble": args.fiber_insoluble,
        "eaten_on": parse_day(args.date), "eaten_at": args.time or now_local(),
        "meal": args.meal, "source": args.source or "estimate",
        "confidence": args.confidence or "low", "note": args.note,
    })
    adjust = fiber_adjustment(args.fiber, args.fiber_soluble, args.fiber_insoluble,
                              current_fiber_mode(conn))
    net = max(0.0, (args.kcal or 0.0) - adjust)
    print("%s  %s -> %s kcal%s, P%s C%s F%s  [%s, %s confidence]"
          % (ev["id"], ev["label"], fmt(net),
             (" (%s stated, -%s fiber)" % (fmt(args.kcal), fmt(adjust))) if adjust else "",
             fmt(args.protein), fmt(args.carbs), fmt(args.fat), ev["eaten_on"],
             ev["confidence"]))


def cmd_rm(args, conn):
    entry = find_entry(conn, args.id)
    append_event({"type": "entry_delete", "target": entry["id"]})
    print("deleted %s %s (%s kcal)" % (entry["id"], entry["label"], fmt(entry["kcal"])))


def cmd_undo(args, conn):
    row = conn.execute("SELECT * FROM entries ORDER BY seq DESC LIMIT 1").fetchone()
    if not row:
        die("nothing to undo")
    append_event({"type": "entry_delete", "target": row["id"]})
    print("undid %s %s (%s kcal)" % (row["id"], row["label"], fmt(row["kcal"])))


def _print_day(conn, day, show_micros=False):
    rows = conn.execute("SELECT * FROM entries WHERE eaten_on = ? ORDER BY eaten_at, seq",
                        (day,)).fetchall()
    note = conn.execute("SELECT note FROM day_notes WHERE day = ?", (day,)).fetchone()

    print("== %s ==" % day)
    if note:
        print("note: %s" % note["note"])
    if not rows:
        print("(nothing logged)")
    else:
        print("%-8s %-30s %10s %7s %6s %6s %6s"
              % ("id", "item", "amount", "kcal", "P", "C", "F"))
        for r in rows:
            amount = "%s%s" % (trim(r["qty"]), r["unit"])
            print("%-8s %-30s %10s %7s %6s %6s %6s"
                  % (r["id"], r["label"][:30], amount[:10], fmt(r["kcal"]),
                     fmt(r["protein"]), fmt(r["carbs"]), fmt(r["fat"])))

    t = totals_for(conn, day, day)
    print("%-8s %-30s %10s %7s %6s %6s %6s"
          % ("", "TOTAL", "", fmt(t["kcal"]), fmt(t["protein"]), fmt(t["carbs"]),
             fmt(t["fat"])))
    if t["fiber"]:
        print("fiber: %sg%s" % (fmt(t["fiber"]),
                                (", %s kcal deducted (%s mode)"
                                 % (fmt(t["kcal_adjust"]), current_fiber_mode(conn)))
                                if t["kcal_adjust"] else ""))
    line = target_line(conn, t)
    if line:
        print(line)
    if show_micros:
        micros = sum_micros(conn, day, day)
        if micros:
            print("micros: %s" % ", ".join("%s %s" % (k, fmt(v, 1))
                                           for k, v in sorted(micros.items())))


def cmd_today(args, conn):
    day = today_str()
    if args.json:
        rows = conn.execute("SELECT * FROM entries WHERE eaten_on = ? ORDER BY eaten_at, seq",
                            (day,)).fetchall()
        print(json.dumps({"day": day, "entries": [dict(r) for r in rows],
                          "totals": totals_for(conn, day, day),
                          "targets": get_targets(conn),
                          "micros": sum_micros(conn, day, day)}, indent=2))
        return
    _print_day(conn, day, show_micros=args.micros)


def cmd_day(args, conn):
    _print_day(conn, parse_day(args.date), show_micros=args.micros)


def cmd_range(args, conn):
    if args.days:
        end = date.today()
        start = (end - timedelta(days=args.days - 1)).isoformat()
        end = end.isoformat()
    else:
        start, end = parse_day(args.start), parse_day(args.end)

    rows = conn.execute(
        "SELECT eaten_on AS day, COUNT(*) AS n, SUM(kcal) AS kcal, "
        "SUM(protein) AS protein, SUM(carbs) AS carbs, SUM(fat) AS fat FROM entries "
        "WHERE eaten_on BETWEEN ? AND ? GROUP BY eaten_on ORDER BY eaten_on",
        (start, end)).fetchall()

    if args.json:
        print(json.dumps({"start": start, "end": end,
                          "days": [dict(r) for r in rows],
                          "totals": totals_for(conn, start, end),
                          "targets": get_targets(conn),
                          "micros": sum_micros(conn, start, end)}, indent=2))
        return

    print("== %s .. %s ==" % (start, end))
    print("%-12s %5s %7s %6s %6s %6s" % ("day", "items", "kcal", "P", "C", "F"))
    for r in rows:
        print("%-12s %5d %7s %6s %6s %6s"
              % (r["day"], r["n"], fmt(r["kcal"]), fmt(r["protein"]), fmt(r["carbs"]),
                 fmt(r["fat"])))
    if not rows:
        print("(nothing logged)")
        return
    t, n = totals_for(conn, start, end), len(rows)
    print("%-12s %5s %7s %6s %6s %6s"
          % ("avg/day", "", fmt(t["kcal"] / n), fmt(t["protein"] / n),
             fmt(t["carbs"] / n), fmt(t["fat"] / n)))
    targets = get_targets(conn)
    if targets:
        print("targets: %s" % ", ".join("%s %s" % (k, fmt(v))
                                        for k, v in sorted(targets.items())))


def cmd_remaining(args, conn):
    day = parse_day(args.date)
    t = totals_for(conn, day, day)
    targets = get_targets(conn)
    if not targets:
        die("no targets set. Try: targets set --kcal 2600 --protein 180")
    out = {k: round(targets[k] - (t[k] or 0), 1) for k in MACROS if k in targets}
    if args.json:
        print(json.dumps({"day": day, "eaten": t, "targets": targets,
                          "remaining": out}, indent=2))
        return
    print("remaining for %s:" % day)
    for key, left in out.items():
        print("  %-8s %8s %s" % (key, fmt(abs(left), 1),
                                 "left" if left >= 0 else "OVER"))


def cmd_targets_set(args, conn):
    written = []
    for key in MACROS:
        value = getattr(args, key)
        if value is not None:
            append_event({"type": "profile_set", "key": "target_" + key,
                          "value": str(value)})
            written.append(key)
    if not written:
        die("pass at least one of --kcal --protein --carbs --fat --fiber")
    for key in written:
        print("%-8s %s" % (key, fmt(getattr(args, key))))


def cmd_targets_show(args, conn):
    targets = get_targets(conn)
    if not targets:
        print("no targets set")
        return
    for key in MACROS:
        if key in targets:
            print("%-8s %s" % (key, fmt(targets[key])))


def cmd_profile_set(args, conn):
    append_event({"type": "profile_set", "key": args.key, "value": args.value})
    print("%s = %s" % (args.key, args.value))


def cmd_profile_show(args, conn):
    rows = conn.execute("SELECT * FROM profile ORDER BY key").fetchall()
    if not rows:
        print("profile empty")
        return
    for r in rows:
        print("%-20s %s" % (r["key"], r["value"]))


def cmd_note(args, conn):
    day = parse_day(args.date)
    append_event({"type": "day_note", "day": day, "note": args.text})
    print("note for %s: %s" % (day, args.text))


def cmd_fiber(args, conn):
    if args.mode:
        if args.mode not in FIBER_MODES:
            die("unknown mode %r, pick one of: %s"
                % (args.mode, ", ".join(sorted(FIBER_MODES))))
        append_event({"type": "profile_set", "key": "fiber_mode", "value": args.mode})
        print("fiber mode is now %s (%s)" % (args.mode, FIBER_MODES[args.mode]))
        print("every day already logged has been re-scored\n")

    current = args.mode or current_fiber_mode(conn)
    day = parse_day(args.date)
    rows = conn.execute(
        "SELECT kcal_label, fiber, fiber_soluble, fiber_insoluble FROM entries "
        "WHERE eaten_on = ?", (day,)).fetchall()
    if not rows:
        print("nothing logged on %s to compare" % day)
        return

    print("calories on %s under each convention:" % day)
    for name in ("label", "half", "split", "net"):
        total = 0.0
        for r in rows:
            adjust = fiber_adjustment(r["fiber"], r["fiber_soluble"],
                                      r["fiber_insoluble"], name)
            total += max(0.0, (r["kcal_label"] or 0.0) - adjust)
        print("  %-6s %7s kcal   %s%s"
              % (name, fmt(total), FIBER_MODES[name],
                 "   <-- in use" if name == current else ""))
    print("\nLog the same day in Cronometer, then switch with: fiber --mode <name>")


def cmd_export(args, conn):
    out = open(args.out, "w") if args.out else sys.stdout
    try:
        for table in ("foods", "entries", "profile", "day_notes"):
            for row in conn.execute("SELECT * FROM %s" % table):
                record = {"_table": table}
                record.update(dict(row))
                out.write(json.dumps(record) + "\n")
    finally:
        if args.out:
            out.close()
            print("exported to %s" % args.out)


def cmd_sql(args, conn):
    if not re.match(r"^\s*(select|with)\b", args.query, re.IGNORECASE):
        die("only SELECT/WITH queries are allowed here")
    rows = conn.execute(args.query).fetchall()
    if not rows:
        print("(no rows)")
        return
    print(json.dumps([dict(r) for r in rows], indent=2))


def cmd_sync(args, conn):
    """Pull, commit only the event log, push. Keeps Mac and cloud sessions in step."""
    def git(*cmd):
        proc = subprocess.run(("git",) + cmd, cwd=HERE, capture_output=True, text=True)
        return proc.returncode, (proc.stdout + proc.stderr).strip()

    rc, out = git("pull", "--no-rebase", "--no-edit")
    print(out or "pulled")
    if rc != 0:
        die("pull failed, resolve it before syncing:\n%s" % out)

    rc, out = git("status", "--porcelain", "--", EVENTS_PATH)
    if not out:
        print("nothing new to push")
        return

    git("add", "--", EVENTS_PATH)
    rc, out = git("commit", "-m", args.message or "food log")
    if rc != 0:
        die("commit failed:\n%s" % out)
    rc, out = git("push")
    print(out or "pushed")
    if rc != 0:
        die("push failed:\n%s" % out)


# ---------------------------------------------------------------- parser


def add_food_fields(p, required):
    p.add_argument("--basis", choices=["100g", "serving"], required=required,
                   help="are the numbers per 100g or per serving")
    p.add_argument("--kcal", type=float, required=required)
    p.add_argument("--protein", type=float, required=required)
    p.add_argument("--carbs", type=float, required=required)
    p.add_argument("--fat", type=float, required=required)
    p.add_argument("--fiber", type=float)
    p.add_argument("--fiber-soluble", dest="fiber_soluble", type=float,
                   help="grams of the fiber that is soluble, counted at 2 kcal/g")
    p.add_argument("--fiber-insoluble", dest="fiber_insoluble", type=float,
                   help="grams of the fiber that is insoluble, counted at 0 kcal/g")
    p.add_argument("--serving-grams", dest="serving_grams", type=float,
                   help="grams in one serving, enables gram<->serving conversion")
    p.add_argument("--serving-label", dest="serving_label",
                   help="what one serving is called, e.g. scoop, slice, egg")
    p.add_argument("--aliases", help="comma separated alternate names")
    p.add_argument("--micros", help="JSON of extra nutrients, e.g. '{\"sodium_mg\":400}'")
    p.add_argument("--source", help="label_photo | usda | estimate | manual")
    p.add_argument("--notes")


def build_parser():
    p = argparse.ArgumentParser(prog="fl", description="personal food log")
    sub = p.add_subparsers(dest="cmd")

    sub.add_parser("init", help="create the event log").set_defaults(fn=cmd_init)

    food = sub.add_parser("food", help="manage the food library")
    fsub = food.add_subparsers(dest="food_cmd")

    fa = fsub.add_parser("add", help="add a food, usually from a nutrition label")
    fa.add_argument("--name", required=True)
    fa.add_argument("--force", action="store_true", help="allow a duplicate name")
    add_food_fields(fa, required=True)
    fa.set_defaults(fn=cmd_food_add)

    fu = fsub.add_parser("update", help="change a stored food")
    fu.add_argument("name")
    fu.add_argument("--rename")
    add_food_fields(fu, required=False)
    fu.set_defaults(fn=cmd_food_update)

    fls = fsub.add_parser("list", help="list or search foods")
    fls.add_argument("query", nargs="?")
    fls.add_argument("--json", action="store_true")
    fls.set_defaults(fn=cmd_food_list)

    fr = fsub.add_parser("rm", help="delete a food")
    fr.add_argument("name")
    fr.set_defaults(fn=cmd_food_rm)

    lg = sub.add_parser("log", help="log a known food, e.g. log 'chicken breast' 150g")
    lg.add_argument("food")
    lg.add_argument("amount")
    lg.add_argument("--date")
    lg.add_argument("--time")
    lg.add_argument("--meal", choices=["breakfast", "lunch", "dinner", "snack"])
    lg.add_argument("--source", help="text | voice | photo | label")
    lg.add_argument("--confidence", choices=["high", "medium", "low"])
    lg.add_argument("--note")
    lg.set_defaults(fn=cmd_log)

    lx = sub.add_parser("logx", help="log a one-off estimate with no stored food")
    lx.add_argument("label")
    lx.add_argument("--kcal", type=float, required=True)
    lx.add_argument("--protein", type=float, required=True)
    lx.add_argument("--carbs", type=float, required=True)
    lx.add_argument("--fat", type=float, required=True)
    lx.add_argument("--fiber", type=float)
    lx.add_argument("--fiber-soluble", dest="fiber_soluble", type=float)
    lx.add_argument("--fiber-insoluble", dest="fiber_insoluble", type=float)
    lx.add_argument("--grams", type=float)
    lx.add_argument("--micros")
    lx.add_argument("--date")
    lx.add_argument("--time")
    lx.add_argument("--meal", choices=["breakfast", "lunch", "dinner", "snack"])
    lx.add_argument("--source", help="text | voice | photo | estimate")
    lx.add_argument("--confidence", choices=["high", "medium", "low"])
    lx.add_argument("--note")
    lx.set_defaults(fn=cmd_logx)

    rm = sub.add_parser("rm", help="delete one entry by id")
    rm.add_argument("id")
    rm.set_defaults(fn=cmd_rm)

    sub.add_parser("undo", help="delete the most recent entry").set_defaults(fn=cmd_undo)

    td = sub.add_parser("today", help="today's entries and totals")
    td.add_argument("--json", action="store_true")
    td.add_argument("--micros", action="store_true")
    td.set_defaults(fn=cmd_today)

    dy = sub.add_parser("day", help="one day's entries and totals")
    dy.add_argument("date")
    dy.add_argument("--micros", action="store_true")
    dy.set_defaults(fn=cmd_day)

    rg = sub.add_parser("range", help="per-day totals over a window")
    rg.add_argument("--days", type=int, help="last N days including today")
    rg.add_argument("--start")
    rg.add_argument("--end")
    rg.add_argument("--json", action="store_true")
    rg.set_defaults(fn=cmd_range)

    rem = sub.add_parser("remaining", help="what is left against your targets")
    rem.add_argument("--date")
    rem.add_argument("--json", action="store_true")
    rem.set_defaults(fn=cmd_remaining)

    tg = sub.add_parser("targets", help="daily macro targets")
    tsub = tg.add_subparsers(dest="targets_cmd")
    ts = tsub.add_parser("set")
    for key in MACROS:
        ts.add_argument("--" + key, type=float)
    ts.set_defaults(fn=cmd_targets_set)
    tsub.add_parser("show").set_defaults(fn=cmd_targets_show)

    pr = sub.add_parser("profile", help="constraints and preferences")
    psub = pr.add_subparsers(dest="profile_cmd")
    ps = psub.add_parser("set")
    ps.add_argument("key")
    ps.add_argument("value")
    ps.set_defaults(fn=cmd_profile_set)
    psub.add_parser("show").set_defaults(fn=cmd_profile_show)

    nt = sub.add_parser("note", help="attach a note to a day")
    nt.add_argument("text")
    nt.add_argument("--date")
    nt.set_defaults(fn=cmd_note)

    fb = sub.add_parser("fiber", help="compare fiber calorie conventions, or switch")
    fb.add_argument("--mode", choices=sorted(FIBER_MODES),
                    help="switch convention and re-score every day already logged")
    fb.add_argument("--date", help="which day to compare, defaults to today")
    fb.set_defaults(fn=cmd_fiber)

    ex = sub.add_parser("export", help="dump projected state as JSONL")
    ex.add_argument("--out")
    ex.set_defaults(fn=cmd_export)

    sq = sub.add_parser("sql", help="run a read-only query")
    sq.add_argument("query")
    sq.set_defaults(fn=cmd_sql)

    sy = sub.add_parser("sync", help="pull, commit the event log, push")
    sy.add_argument("-m", "--message")
    sy.set_defaults(fn=cmd_sync)

    return p


def main():
    parser = build_parser()
    args = parser.parse_args()
    if not getattr(args, "fn", None):
        parser.print_help()
        sys.exit(1)
    conn = project()
    try:
        args.fn(args, conn)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
