#!/usr/bin/env bash
# Generate a logarithmic sine sweep WAV (48 kHz, 24-bit, mono) with ffmpeg.
set -euo pipefail

VERSION=0.0.1
MIN_FFMPEG=9.0
SAMPLE_RATE=48000
NYQUIST=$((SAMPLE_RATE / 2))
FADE=0.05
PRESETS="subbass low mid high 4k full"

PRESET=full
LENGTH=1440000   # default sweep length in samples (30 s at 48 kHz)
SAMPLES_ARG=""
SECONDS_ARG=""
LEVEL=-12
PAD=5s
START=""
END=""
OUT=""

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Generate a logarithmic sine sweep WAV (48 kHz, 24-bit, mono, 50 ms fades).

Options:
  -p, --preset <name>      Frequency range preset, or 'all' for one file per
                           preset (default: $PRESET)
  -s, --start <Hz>         Start frequency (overrides the preset)
  -e, --end <Hz>           End frequency (overrides the preset)
  -t, --seconds <seconds>  Sweep length in seconds, e.g. 30 or 5.5
  -n, --samples <count>    Sweep length in samples at $SAMPLE_RATE Hz, e.g. 262144
                           Give either --seconds or --samples, not both.
                           (default: $LENGTH samples = $((LENGTH / SAMPLE_RATE)) s)
  -l, --level <dBFS>       Peak level, 0 or negative (default: $LEVEL)
  -P, --padding <time>     Silence added before and after the sweep, with a
                           unit: ms or s, e.g. 500ms or 5s (default: $PAD)
  -o, --output <file>      Output file
                           (default: sweep_<start>-<end>Hz_log_<samples>samples.wav)
  -v, --version            Show version
  -h, --help               Show this help

Long options also accept the --name=value form.

Presets:
  subbass   20 Hz - 60 Hz
  low       20 Hz - 250 Hz
  mid       250 Hz - 4 kHz
  high      4 kHz - 20 kHz
  4k        20 Hz - 4 kHz
  full      20 Hz - 20 kHz
  all       every preset above (--start, --end and --output cannot be used)
EOF
}

die() {
  echo "Error: $*" >&2
  exit 1
}

is_number() {
  [[ $1 =~ ^-?[0-9]+(\.[0-9]+)?$ ]]
}

# to_seconds <number>ms|<number>s -> seconds on stdout
to_seconds() {
  [[ $1 =~ ^([0-9]+(\.[0-9]+)?)(ms|s)$ ]] \
    || die "padding must be a number with a unit, ms or s (e.g. 500ms, 5s): '$1'"
  awk -v n="${BASH_REMATCH[1]}" -v u="${BASH_REMATCH[3]}" \
    'BEGIN { printf "%.6f", (u == "ms" ? n / 1000 : n) }'
}

# Rewrite long options (--name value / --name=value) as their short forms in
# the global array ARGS, so getopts can parse everything. Values of options
# are copied untouched, so "-o --help" treats --help as a file name.
translate_args() {
  ARGS=()
  local short
  while (( $# )); do
    case $1 in
      --preset|--start|--end|--samples|--seconds|--level|--padding|--output)
        case $1 in
          --preset) short=-p ;;  --start) short=-s ;;   --end) short=-e ;;
          --samples) short=-n ;; --seconds) short=-t ;;  --level) short=-l ;;
          --padding) short=-P ;; --output) short=-o ;;
        esac
        (( $# >= 2 )) || die "option $1 requires an argument"
        ARGS+=("$short" "$2")
        shift 2 ;;
      --preset=*|--start=*|--end=*|--samples=*|--seconds=*|--level=*|--padding=*|--output=*)
        case ${1%%=*} in
          --preset) short=-p ;;  --start) short=-s ;;   --end) short=-e ;;
          --samples) short=-n ;; --seconds) short=-t ;;  --level) short=-l ;;
          --padding) short=-P ;; --output) short=-o ;;
        esac
        ARGS+=("$short" "${1#*=}")
        shift ;;
      --version) ARGS+=(-v); shift ;;
      --help)    ARGS+=(-h); shift ;;
      --)        ARGS+=("$@"); return 0 ;;
      --*)       die "unknown option ${1%%=*}" ;;
      -[pseltnPo])
        # Short option that takes a value: copy the value as-is.
        ARGS+=("$1")
        shift
        if (( $# )); then ARGS+=("$1"); shift; fi ;;
      *) ARGS+=("$1"); shift ;;
    esac
  done
}

# Exit with a clear message unless ffmpeg is installed and at least MIN_FFMPEG.
check_ffmpeg() {
  command -v ffmpeg >/dev/null || die "ffmpeg not found in PATH (need $MIN_FFMPEG or newer)"

  local line major minor
  line=$(ffmpeg -version 2>/dev/null | sed -n 1p)
  if [[ $line =~ ^ffmpeg\ version\ n?([0-9]+)\.([0-9]+) ]]; then
    major=${BASH_REMATCH[1]}
    minor=${BASH_REMATCH[2]}
  else
    # Git/snapshot builds have no release number, so they cannot be compared.
    echo "Warning: cannot determine the ffmpeg version from '$line'; continuing" >&2
    return 0
  fi

  if (( major < ${MIN_FFMPEG%%.*} || (major == ${MIN_FFMPEG%%.*} && minor < ${MIN_FFMPEG#*.}) )); then
    die "ffmpeg $major.$minor is too old (need $MIN_FFMPEG or newer)"
  fi
}

# Sets P_START and P_END for a preset name.
preset_range() {
  case $1 in
    subbass) P_START=20;   P_END=60 ;;
    low)     P_START=20;   P_END=250 ;;
    mid)     P_START=250;  P_END=4000 ;;
    high)    P_START=4000; P_END=20000 ;;
    4k)      P_START=20;   P_END=4000 ;;
    full)    P_START=20;   P_END=20000 ;;
    *) die "unknown preset '$1' (use $PRESETS, all)" ;;
  esac
}

# generate <start Hz> <end Hz> <output file or empty>
generate() {
  local start=$1 end=$2 out=$3

  is_number "$start" || die "start frequency must be a number: '$start'"
  is_number "$end"   || die "end frequency must be a number: '$end'"

  awk -v s="$start" -v e="$end" 'BEGIN { exit !(s > 0 && e > 0) }' \
    || die "frequencies must be greater than 0"
  awk -v s="$start" -v e="$end" -v n="$NYQUIST" 'BEGIN { exit !(s < n && e < n) }' \
    || die "frequencies must be below Nyquist ($NYQUIST Hz)"
  awk -v s="$start" -v e="$end" 'BEGIN { exit !(s != e) }' \
    || die "start and end frequencies must differ"

  local amp dur fade_out_start expr pad_samples filters
  amp=$(awk -v l="$LEVEL" 'BEGIN { printf "%.6f", 10 ^ (l / 20) }')
  dur=$(awk -v n="$LENGTH" -v r="$SAMPLE_RATE" 'BEGIN { printf "%.9f", n / r }')
  fade_out_start=$(awk -v d="$dur" -v f="$FADE" 'BEGIN { printf "%.6f", d - f }')

  # phase(t) = 2*pi*f0*T/ln(k) * (k^(t/T) - 1), k = f1/f0, so f(t) = f0 * k^(t/T)
  expr="${amp}*sin(2*PI*${start}*${dur}/log(${end}/${start})*(pow(${end}/${start},t/${dur})-1))"

  filters="afade=t=in:d=${FADE},afade=t=out:st=${fade_out_start}:d=${FADE}"
  if awk -v p="$PAD_S" 'BEGIN { exit !(p > 0) }'; then
    pad_samples=$(awk -v p="$PAD_S" -v r="$SAMPLE_RATE" 'BEGIN { printf "%d", p * r + 0.5 }')
    filters="${filters},adelay=${pad_samples}S:all=1,apad=pad_dur=${PAD_S}"
  fi

  if [[ -z $out ]]; then
    out="sweep_${start}-${end}Hz_log_${LENGTH}samples.wav"
  fi

  # ffmpeg would read an output name starting with "-" as an option.
  [[ $out == -* ]] && out="./$out"

  ffmpeg -hide_banner -loglevel error -y \
    -f lavfi -i "aevalsrc='${expr}':s=${SAMPLE_RATE}:d=${dur}" \
    -af "$filters" \
    -c:a pcm_s24le -ac 1 "$out"

  echo "Wrote $out (${start} Hz -> ${end} Hz, ${LENGTH} samples = $(awk -v d="$dur" 'BEGIN { printf "%.3f", d }') s, ${LEVEL} dBFS, ${PAD} padding each end)"
}

translate_args "$@"
set -- ${ARGS[@]+"${ARGS[@]}"}

while getopts ":p:s:e:n:t:l:P:o:vh" opt; do
  case $opt in
    p) PRESET=$OPTARG ;;
    s) START=$OPTARG ;;
    e) END=$OPTARG ;;
    n) SAMPLES_ARG=$OPTARG ;;
    t) SECONDS_ARG=$OPTARG ;;
    l) LEVEL=$OPTARG ;;
    P) PAD=$OPTARG ;;
    o) OUT=$OPTARG ;;
    v) echo "$(basename "$0") $VERSION"; exit 0 ;;
    h) usage; exit 0 ;;
    :) echo "Error: option -$OPTARG requires an argument" >&2; usage >&2; exit 1 ;;
    \?) echo "Error: unknown option -$OPTARG" >&2; usage >&2; exit 1 ;;
  esac
done

check_ffmpeg

[[ -z $SAMPLES_ARG || -z $SECONDS_ARG ]] \
  || die "give either -n/--samples or -t/--seconds, not both"
if [[ -n $SAMPLES_ARG ]]; then
  LENGTH=$SAMPLES_ARG
  [[ $LENGTH =~ ^[0-9]+$ ]] || die "samples must be a whole number: '$LENGTH'"
elif [[ -n $SECONDS_ARG ]]; then
  [[ $SECONDS_ARG =~ ^[0-9]+(\.[0-9]+)?$ ]] \
    || die "seconds must be a positive number: '$SECONDS_ARG'"
  LENGTH=$(awk -v s="$SECONDS_ARG" -v r="$SAMPLE_RATE" 'BEGIN { printf "%d", s * r + 0.5 }')
fi
is_number "$LEVEL"    || die "level must be a number: '$LEVEL'"
PAD_S=$(to_seconds "$PAD")

MIN_LENGTH=$(awk -v f="$FADE" -v r="$SAMPLE_RATE" 'BEGIN { printf "%d", 2 * f * r }')
(( LENGTH > MIN_LENGTH )) || die "length must be greater than $MIN_LENGTH samples ($(awk -v f="$FADE" 'BEGIN { print 2 * f }') s, the two fades); got $LENGTH"
awk -v l="$LEVEL" 'BEGIN { exit !(l <= 0) }' \
  || die "level must be 0 dBFS or below"

if [[ $PRESET == all ]]; then
  [[ -z $START && -z $END ]] || die "-s/--start and -e/--end cannot be used with -p/--preset all"
  [[ -z $OUT ]] || die "-o/--output cannot be used with -p/--preset all"
  for p in $PRESETS; do
    preset_range "$p"
    generate "$P_START" "$P_END" ""
  done
else
  preset_range "$PRESET"
  generate "${START:-$P_START}" "${END:-$P_END}" "$OUT"
fi
