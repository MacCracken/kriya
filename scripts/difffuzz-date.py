#!/usr/bin/env python3
"""Differential fuzz: kriya vs GNU over `date -d STRING`, in UTC.

Usage:  python3 scripts/difffuzz-date.py build/kriya [cases] [seed]

Each case is a random date string built from GNU's vocabulary (gnulib's
parse-datetime.y): ISO 8601 dates and times, `MM/DD/YY`, `DD.MM.YYYY`, month
and weekday names in every spelling the tables take, units singular and
plural, ordinals, `ago`/`hence`, `yesterday`/`now`, zone names and offsets,
military letters, `am`/`pm`, `@` seconds, decimals, comments, noise, and numbers at the edges of
GNU's int and intmax_t arithmetic. Both
run under `TZ=UTC LC_ALL=C` with `+%Y-%m-%d %H:%M:%S.%N %s`.

⚠ An answer can depend on the moment it is asked (`5 days`, `10:30`), so GNU
runs twice, before and after kriya. When its two answers agree the string does
not depend on now, and kriya's must match exactly; when they differ, kriya's
must match one of them to the second. A refusal is GNU's exit 1 and kriya's
exit 2 (ADR 0008).

⚠ A string starting `TZ="` is not generated: GNU loads that zone, and kriya,
which keeps no zone data, refuses it (ADR 0007).

NOT part of `cyrius test` or `scripts/fuzz.sh`; run it by hand when
`src/lib/datetime.cyr` changes, and in the containers. GNU before 9.11 has no
`DD.MM.YYYY` dates, so where it refuses one kriya reads, the case is counted
as documented rather than a difference.
"""
import os, random, re, subprocess, sys

KRIYA = sys.argv[1]
N     = int(sys.argv[2]) if len(sys.argv) > 2 else 3000
SEED  = int(sys.argv[3]) if len(sys.argv) > 3 else 1
ENV = {"PATH": "/usr/bin:/bin", "LC_ALL": "C", "TZ": "UTC"}
FMT = "+%Y-%m-%d %H:%M:%S.%N %s"
rnd = random.Random(SEED)

MONTHS = ["jan", "January", "FEB", "feb.", "March", "apr", "May", "june", "Jul", "aug", "sept", "Sep",
          "september", "oct", "Nov", "december", "Dec."]
DAYS = ["mon", "Monday", "tue", "tues", "Wednesday", "wednes", "thu", "thur", "thurs", "Friday",
        "sat", "Sunday", "sun"]
UNITS = ["year", "years", "month", "months", "fortnight", "fortnights", "week", "weeks", "day", "days",
         "hour", "hours", "minute", "minutes", "min", "mins", "second", "seconds", "sec", "secs"]
ORDS = ["last", "this", "next", "first", "third", "fourth", "fifth", "twelfth"]
ZONES = ["UTC", "GMT", "UT", "Z", "EST", "EDT", "PST", "PDT", "CET", "CEST", "IST", "JST", "NZDT",
         "MSK", "A", "M", "N", "Y", "J", "T", "WET", "BST", "EST DST", "e.s.t", "u.t.c"]
SHIFTS = ["now", "today", "yesterday", "tomorrow"]

def n(lo, hi, pad=0):
    v = rnd.randint(lo, hi)
    return ("%0*d" % (pad, v)) if pad else str(v)

def year():
    return rnd.choice([n(1970, 2037), n(1900, 2100), n(0, 99, 2), n(1, 9999, 4), n(10000, 99999)])

def iso_date():
    return "%s-%s-%s" % (year(), n(1, 12, rnd.choice([1, 2])), n(1, 31, rnd.choice([1, 2])))

def time_():
    t = "%s:%s" % (n(0, 23, rnd.choice([1, 2])), n(0, 59, 2))
    r = rnd.random()
    if r < 0.5:
        t += ":" + n(0, 60, 2)
        if rnd.random() < 0.3:
            t += rnd.choice([".", ","]) + "".join(rnd.choice("0123456789") for _ in range(rnd.randint(1, 11)))
    if rnd.random() < 0.15:
        t += rnd.choice([" am", " pm", "pm", " a.m.", " P.M."])
    elif rnd.random() < 0.25:
        t += rnd.choice(["Z", "+05:30", "-0800", " +01", "-12", "+1400", " -05:00", "+99"])
    return t

def rel():
    r = rnd.random()
    if r < 0.4:
        s = "%s%s %s" % (rnd.choice(["", "", "+", "-", "+ ", "- "]), n(0, 400), rnd.choice(UNITS))
    elif r < 0.55:
        s = "%s %s" % (rnd.choice(ORDS), rnd.choice(UNITS))
    elif r < 0.65:
        s = rnd.choice(UNITS)
    elif r < 0.75:
        s = "%s.%s seconds" % (n(-5, 5), n(0, 999))
    else:
        s = rnd.choice(SHIFTS)
    if rnd.random() < 0.25:
        s += rnd.choice([" ago", " hence"])
    return s

# Numbers at the edges of GNU's arithmetic: an int (`tm_mday`, the relative nanoseconds) and an
# intmax_t (every other relative field), where its `ckd_add` / `ckd_sub` checks refuse a string.
EDGES = ["2147483647", "2147483648", "306783377", "306783378", "153391689", "9223372036854775807",
         "9223372036854775808", "-9223372036854775808", "-9223372036854775807", "1317624576693539401",
         "2562047788015215", "153722867280912930", "4294967296", "-2147483648"]

def edge():
    r = rnd.random()
    if r < 0.4:
        return "%s %s" % (rnd.choice(EDGES), rnd.choice(UNITS + DAYS))
    if r < 0.6:
        return " ".join("%s.%s sec%s" % (n(0, 3), n(1, 999999999, 9), rnd.choice(["", " ago"]))
                        for _ in range(rnd.randint(2, 4)))
    if r < 0.8:
        return "%s %s %s" % (n(1, 28), rnd.choice(MONTHS), rnd.choice(EDGES))
    return "%s-%s-%s" % (n(1970, 2037), rnd.choice(EDGES).lstrip("-"), n(1, 28, 2))

def fragment():
    r = rnd.random()
    if r < 0.04: return edge()
    if r < 0.18: return iso_date()
    if r < 0.24: return iso_date() + "T" + time_()
    if r < 0.38: return time_()
    if r < 0.55: return rel()
    if r < 0.60: return "%s/%s/%s" % (n(1, 12), n(1, 31), year())
    if r < 0.63: return "%s/%s" % (n(1, 12), n(1, 31))
    if r < 0.66: return "%s.%s.%s" % (n(1, 31, 2), n(1, 12, 2), year())
    if r < 0.67: return "%s.%s." % (n(1, 31), n(1, 12))
    if r < 0.72: return "%s %s %s" % (n(1, 31), rnd.choice(MONTHS), year())
    if r < 0.75: return "%s %s, %s" % (rnd.choice(MONTHS), n(1, 31), year())
    if r < 0.78: return "%s-%s-%s" % (n(1, 31), rnd.choice(MONTHS), year())
    if r < 0.80: return "%s %s" % (rnd.choice(MONTHS), n(1, 31))
    if r < 0.85: return rnd.choice(["", "", "next ", "last ", "2 ", "this "]) + rnd.choice(DAYS) + rnd.choice(["", ","])
    if r < 0.90: return rnd.choice(ZONES)
    if r < 0.93: return n(0, 99999999)
    if r < 0.95: return "(%s)" % rnd.choice(["x", "a (b) c", "unclosed"])
    if r < 0.97: return rnd.choice(["x", "bogus", "dst", "ago", "pm", ":", ",", "-", "+", "/", "1e3", "."])
    return n(0, 2400)

def case():
    if rnd.random() < 0.06:
        s = "@" + rnd.choice(["", " ", "+", "-"]) + n(0, 4000000000)
        if rnd.random() < 0.4:
            s += "." + "".join(rnd.choice("0123456789") for _ in range(rnd.randint(1, 12)))
        if rnd.random() < 0.1:
            s += " " + fragment()
        return s
    parts = [fragment() for _ in range(rnd.choice([1, 1, 2, 2, 2, 3, 3, 4]))]
    return " ".join(parts) if rnd.random() < 0.9 else "".join(parts)

def run(cmd):
    p = subprocess.run(cmd, env=ENV, capture_output=True, timeout=20)
    return p.stdout.decode("latin-1").strip(), p.returncode

def coarse(o):
    return o[0][:19] if o[1] == 0 else ""

# GNU 9.11 began reading DD.MM.YYYY and DD.MM. dates (its NEWS); before that it refuses them.
DOTTED = run(["/usr/bin/date", "-d", "15.01.2024", FMT])[1] == 0
DOTRE = re.compile(r"(^|[^0-9.])[0-9]+[.,][0-9]+[.]")
documented = 0
diff = 0
dep = 0
for i in range(N):
    s = case()
    g1 = run(["/usr/bin/date", "-d", s, FMT])
    k = run([KRIYA, "date", "-d", s, FMT])
    g2 = run(["/usr/bin/date", "-d", s, FMT])
    kk = (k[0], 1 if k[1] == 2 else k[1])
    if g1[1] != 0:
        g1 = ("", g1[1])
    if g2[1] != 0:
        g2 = ("", g2[1])
    if kk[1] != 0:
        kk = ("", kk[1])
    if g1 == g2:
        ok = kk == g1
    else:
        dep += 1
        ok = kk[1] == g1[1] and coarse(kk) in (coarse(g1), coarse(g2))
    if not ok and not DOTTED and g1[1] == 1 and kk[1] == 0 and DOTRE.search(s):
        documented += 1
        continue
    if not ok:
        diff += 1
        if diff <= 25:
            print("DIFF %r\n  gnu %r\n  kri %r" % (s, g1, kk))
print("date -d: %d cases (%d depend on now), %d differ" % (N, dep, diff))
if documented:
    print("%d documented: a DD.MM. date this GNU predates (9.11 reads them; kriya follows)" % documented)
sys.exit(1 if diff else 0)
