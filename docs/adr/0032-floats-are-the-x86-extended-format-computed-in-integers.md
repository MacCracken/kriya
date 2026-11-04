# 0032 — Floats are GNU's x86 `long double`, computed in integers on every target

**Status**: Accepted
**Date**: 2026-11-04

## Context

`printf`'s `%e %f %g %a` and `seq`'s operands are floating point, and kriya refused both until 1.9.0.
Which floating point is the choice.

- **POSIX** says a float argument to `printf` "shall be evaluated as if by the `strtod()` function": a
  binary64 `double`.
- **GNU's `printf` and `seq`** read with `strtold` and print with glibc's `printf` of a `long double`.
  On x86_64 that is the 80-bit extended format: a 64-bit significand, exponents -16382..16383,
  subnormals down to 2^-16445. On aarch64 it is binary128, a 113-bit significand.
- **GNU's `find`** reads `-mtime` and `-mmin` with `strtod`, binary64, and computes in `double`.
- **Cyrius** has binary64 `f64` in hardware, through SSE2 and NEON, and nothing wider.

The difference shows in ordinary use, measured at 1.9.0:

- 40 of 3,000 short decimals print differently with `%.2f` in binary64 and on GNU x86_64:
  `738.495` is `738.49` there and `738.50` in binary64. The halfway cases round the other way at 64
  bits. `%.1f`, `%.3f` and `%g` are the same, about 1.3%.
- glibc prints a value's exact decimal expansion: `%.30f 0.1` is `0.100000000000000000001355252716`,
  and `%f 1e4000` writes all 4,001 digits. binary64 overflows at 1.8e308.

## Decision

**kriya's `printf` and `seq` compute in GNU's x86_64 `long double`, emulated exactly in integer
arithmetic, so the answer is the same on every target. `find`'s `-mtime` and `-mmin` are binary64, as
findutils' are.** One module, `src/lib/xfloat.cyr`, does all of it:

- **Reading**: glibc's `strtold` and `strtod` in the C locale. That covers blanks, a sign, decimal
  and hex significands, `inf`, `infinity`, `nan` and `nan(chars)`. Results are correctly rounded,
  half to even. ERANGE is set as glibc sets it on x86: on overflow, and on an inexact result that is
  still tiny after rounding.
- **Writing**: glibc's `%e %E %f %F %g %G %a %A` of an extended value, exact, half to even, with
  every flag, width and precision.
- **Arithmetic for `seq`**: add, multiply and compare, each rounded once, as the x87 rounds
  `first + i * step`.

It is a big-integer computation: binary limbs for reading and arithmetic, base-10^9 limbs for
writing. kriya does not use the hardware's binary64 for `printf` or `seq` at all.

This is a deviation from the letter of POSIX's "as if by `strtod()`", in GNU's direction. Every
binary64 value is exactly representable in the extended format, so the change is precision and
range, never a different reading of an exact value.

## Consequences

- **Positive**
  - Byte-identical to GNU on x86_64. On 1.9.0's final build, `scripts/difffuzz-float.py` ran 180,000
    random `printf` cases and 18,000 `seq` runs against coreutils 9.4, 9.7 and 9.12, with 0
    differences.
  - The same digits on aarch64 and agnos, which have no extended format of their own.
  - The ranges are GNU's: `%f 1e4932` prints, and `seq 1e4932 1e4932` too.
- **Negative**
  - On aarch64, kriya's digits are not the local GNU's. Its `long double` is binary128 and prints more
    digits of the same value: `%.30f 0.1` differs from the 20th digit. kriya gives the x86_64
    answer there, and says so.
  - It is slower than GNU:
    - `printf '%.2f\n'` over 100,000 arguments takes 302 ms against GNU's 125 ms. kriya's plain
      `%s` path already takes 187 ms, so floats add about 1.1 µs an argument.
    - `seq 0 0.001 1000`, a million values, takes 1.15 s against 0.19 s. Roadmap 1.10.x carries it.
  - About 1,300 lines of big-integer and formatting code to maintain, covered by unit tests in
    `tests/kriya.tcyr`, the fuzz and the smoke comparisons.
  - One glibc behaviour is not copied. `%If` prints only the decimal point in GNU, because glibc's
    digits flag drops a `long double`'s digits, measured on 9.4 to 9.12. kriya prints the number.
- **Neutral**
  - GNU 9.4's `seq` refused an operand that underflows to a subnormal (`1e-4950`), and 9.12 reads it.
    kriya follows 9.12, and `smoke-seq.sh` asserts it rather than comparing.

## Alternatives considered

- **binary64, through Cyrius's `f64`.** It is POSIX's letter and the hardware does it. But it
  disagrees with GNU on about 1.3% of ordinary two-place values, and stops at 1.8e308, where GNU goes
  to 1.2e4932. Every halfway case would be a wrong-looking answer next to GNU's.
- **binary128, as GNU on aarch64.** There is no binary128 oracle on the x86_64 machines where kriya is
  measured, and CI is x86_64. Matching the platform GNU runs on would give two answers on two targets.
- **Keep refusing floats.** That leaves `printf %f` and `seq 0 0.1 1` unusable, the most common float
  needs in shell. The refusal was only ever meant to stand until a formatter existed.
