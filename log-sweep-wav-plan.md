# Log Sweep WAV Generation Plan

## Top-Level Overview

Create `make_sweep.sh`, a bash script that generates logarithmic sine sweep WAV files for speaker testing using a single `ffmpeg` command (no Python). The script takes command line options and supports named presets.

Fixed parameters (confirmed with user):
- Sweep shape: logarithmic, instantaneous frequency f(t) = f0 * k^(t/T), with k = f1/f0
- Source: `ffmpeg -f lavfi` with `aevalsrc`. Phase expression: `sin(2*PI*f0*T/log(k)*(pow(k,t/T)-1))` (`log()` is the natural log in ffmpeg)
- Format: 48 kHz, mono, `pcm_s24le`
- Requires ffmpeg 9.0 or newer (`MIN_FFMPEG` in the script). The script checks this after option parsing, so `-h` and `-v` work without ffmpeg
- 50 ms fade-in and fade-out via `afade` to avoid clicks (fixed; not affected by padding)

Defaults (confirmed with user; these supersede the earlier 60 s / -3 dBFS / 5-250 Hz values):
- Sweep length: 1440000 samples (30 s at 48 kHz)
- Level: -12 dBFS peak (amplitude = 10^(level/20), computed in the script, e.g. with `awk`)
- Preset: `full`
- Padding: 5 s of silence before and after the sweep

Presets (ranges supplied by user):

| Preset | Range | Purpose |
|---|---|---|
| `subbass` | 20 - 60 Hz | Sub-bass extension, room modes, port noise |
| `low` | 20 - 250 Hz | Subwoofer/woofer range |
| `mid` | 250 Hz - 4 kHz | Midrange driver, crossover regions, cabinet resonances |
| `high` | 4 - 20 kHz | Tweeter output, breakup, sibilance |
| `4k` | 20 Hz - 4 kHz | Woofer plus midrange in one pass, up to typical tweeter crossover (user chose to keep `4k` and drop `lowmid`) |
| `full` | 20 Hz - 20 kHz | Full-range check |

Proposed options (final names chosen at implementation, kept minimal):
- `-p` / `--preset <name>`: select a preset, or `all` to generate one file per preset (`-s`, `-e` and `-o` are rejected with `all`)
- `-s` / `--start <Hz>` and `-e` / `--end <Hz>`: custom start/end frequency (override the preset's values)
- `-n` / `--samples <count>` or `-t` / `--seconds <seconds>`: sweep length, either as a whole number of samples at 48 kHz or in seconds (decimals allowed, rounded to the nearest sample). Giving both is an error. Default 1440000 samples = 30 s. The old `-d` flag was removed. A sweep must be longer than the two 50 ms fades (4800 samples)
- `-l` / `--level <dBFS>`: peak level (default -12)
- `-P` / `--padding <time>`: silence added before and after the sweep, as a number with a required unit, `ms` or `s` (e.g. `500ms`, `5s`, `1.5s`; default `5s`; `0s` disables). Uppercase because `-p` is the preset. The total file length is the sweep duration plus twice the padding
- `-o` / `--output <file>`: output file (default auto-named, e.g. `sweep_20-250Hz_log_30s.wav`)
- `-h` / `--help`: usage
- `-v` / `--version`: print version (0.0.1)

Every option has a long form, and long options accept both `--name value` and `--name=value`. `getopts` has no long-option support, so the script first rewrites long options to their short forms and then runs `getopts`. A value that looks like an option (`--output --help`) is treated as the value.

Outputs in the workspace root: `make_sweep.sh` and the generated WAV files. The workspace contains only this plan, so there are no existing conventions to follow.

## Sub-Tasks

### 1. Create `make_sweep.sh` with options and presets

**Intent** — One reusable script that builds the ffmpeg command from presets or custom values.

**Expected Outcomes**
- `make_sweep.sh` exists in the workspace root and is executable.
- `./make_sweep.sh` with no arguments produces the `full` preset at 1440000 samples (30 s) and -12 dBFS, with 5 s of silence at each end (40 s total).
- `-p`, `-s`, `-e`, `-n`, `-t`, `-l`, `-P`, `-o`, `-h` and `-v` work, and each has a long form, with explicit `-s`/`-e` overriding the preset.
- Invalid input gives a clear error and non-zero exit.

**Todo List**
1. Write the script with `#!/usr/bin/env bash` and `set -euo pipefail`.
2. Define the preset table (`subbass`, `low`, `mid`, `high`, `4k`, `full`) and defaults (1440000 samples, -12 dBFS, `full`).
3. Translate long options to short forms, then parse with `getopts`. Apply the preset first, then let `-s`/`-e` override it.
4. Validate inputs:
   - start and end are positive numbers and different
   - both are below Nyquist (24 kHz)
   - `--samples` and `--seconds` are not both given; samples is a whole number, seconds a positive number; the resulting length is greater than the two fades (4800 samples)
   - level is at most 0
   - preset name is known
   - padding matches `<number>ms` or `<number>s`
   - ffmpeg is installed and is version 9.0 or newer. Git/snapshot builds have no release number, so they only produce a warning
5. Compute the amplitude from the dBFS level.
6. Build the default output name from the final start, end and length in samples (e.g. `sweep_20-250Hz_log_1440000samples.wav`).
7. Run `ffmpeg -y -f lavfi -i "aevalsrc=<expr>:s=48000:d=<dur>"` with `-af "afade=t=in:d=0.05,afade=t=out:st=<dur-0.05>:d=0.05"`, then `-c:a pcm_s24le -ac 1 <out>`. Quote the expression so the shell leaves `*`, `(` and `)` alone.
8. Add a usage/help text listing the options, defaults and presets with their ranges. Use it for `-h` and for usage errors.
8a. Add padding after the fades with `adelay=<samples>S:all=1,apad=pad_dur=<seconds>`, skipped when padding is 0.
9. Mark the file executable (`chmod +x`).

**Relevant Context**
- Expression and parameters are in the Top-Level Overview.
- The `aevalsrc` expression contains a comma (in `pow(a,b)`), so it must be wrapped in single quotes inside the lavfi string (`aevalsrc='<expr>':s=...`). Without them ffmpeg's filtergraph parser fails. The commas in the `-af` chain separate filters, as intended.
- The fade-out start time depends on the sweep length converted to seconds (not the padding), so compute it in the script. Padding filters come after the fades in the chain, so the fades stay on the sweep itself.
- A sweep with start equal to end would divide by `log(1)` = 0, hence the validation.
- A descending sweep (start > end) also works with the same formula (k < 1). Decide at implementation whether to allow it. Default: allow.

**Status** — [x] done

### 2. Generate and verify the WAVs

**Intent** — Confirm the script works for every preset and the output matches the spec.

**Expected Outcomes**
- WAV files for all presets are created.
- Format, duration and peak level match the spec.
- Error handling and overrides behave as expected.

**Todo List**
1. Confirm `ffmpeg` and `ffprobe` are installed (`ffmpeg -version`). Report to the user if they are missing.
2. Run `./make_sweep.sh` with no arguments, then once per preset.
3. For each file, run `ffprobe` and check codec `pcm_s24le`, 48000 Hz, 1 channel, and the expected duration.
4. Run `ffmpeg -i <file> -af volumedetect -f null -` and check max_volume is about -12.0 dB (±0.1 dB).
5. Check that the first and last 50 ms are faded, for example with `atrim` plus `volumedetect` showing a much lower peak than -12 dB.
6. Check overrides: `--seconds 60 --level -3` gives 60 s and about -3 dB, and `-s 100 -e 1000` gives a custom range.
7. Check that `-h` prints the usage, `-v` prints the version, and both exit 0 without running ffmpeg. Check that `-p all` writes one file per preset and rejects `-s`, `-e` and `-o`.
7b. Check padding: default gives sweep length + 10 s, `-P 500ms` and `-P 1.5s` give the expected lengths, the padded regions are silent, the sweep still fades over 50 ms, and bad values (`5`, `s`, `-1s`, `5sec`) fail with a clear message.
7a. Check that bad input (`-s 1000 -e 1000`, `-e 30000`, `-p nope`) fails with a clear message.
8. Optional frequency sanity check at the start and end of a sweep (zero-crossing count or spectrogram). Skip if it is not easy with ffmpeg alone.

**Relevant Context**
- `make_sweep.sh` from sub-task 1.
- Tolerance: peak level within about ±0.1 dB of the requested level.

**Status** — [x] done

### 3. Provide a Dockerfile

**Intent** — Let the script run without installing ffmpeg locally. Only the `Dockerfile` is provided; users build it themselves.

**Expected Outcomes**
- `Dockerfile` and `.dockerignore` exist in the workspace root.
- `docker build -t makesweep .` builds an image from `linuxserver/ffmpeg:9.0.2`.
- The image runs `make_sweep.sh` with all its options and writes WAVs to a mounted `/output`.

**Todo List**
1. `FROM linuxserver/ffmpeg:9.0.2`. Copy `make_sweep.sh` to `/usr/local/bin`.
2. Set `WORKDIR /output` and `ENTRYPOINT` to the script, which replaces the base image's ffmpeg wrapper entrypoint.
3. Add a `.dockerignore` that sends only `make_sweep.sh` to the build context, so the generated WAVs and `.git` are not copied.
4. Build on the host and test `-v`, `-h`, a single sweep, `-p all`, and an error exit code.

**Relevant Context**
- The base image already has `bash`, `awk` (mawk) and `ffmpeg` 9.0.2. The script needed no changes.
- Multi-platform images (amd64 and arm64) were tried and not needed. The Dockerfile has no platform-specific steps, and the base image publishes both platforms, so `docker build` gives a native image on either. Both variants produced byte-identical WAVs.
- Run with `--user "$(id -u):$(id -g)"` so output files are owned by the host user instead of root.

**Status** — [x] done

## Notes / Risks
- Sweep length is exact. `ffprobe` reports the requested number of samples for 18 lengths tried (odd, prime, power-of-two and 30 s), with and without padding. Counting must use `duration_ts`; `nb_read_frames` counts decoder packets, not samples.
- The 9.0 minimum is a decision, not a measured limit. It was run on 9.0.1, 9.0.2, 8.0.1, 8.1.2, and 4.4.5, all of which worked, and failed on 4.0.6, 3.4.13, 3.2.19 and 2.8.15 (the `adelay` `all` option and another filter option are missing there). Versions 4.1 to 4.3 and 5 to 7 were not individually bisected, apart from 5.1, 6.1 and 7.1, which worked. The true minimum is somewhere between 4.0 and 4.4.
- The `high` preset (up to 20 kHz) is below the 24 kHz Nyquist, so no aliasing concern at 48 kHz.
- `subbass` (20-60 Hz, 1.58 octaves) at 30 s is slow (about 0.05 octaves/s). That is fine for finding rattles. Use `--seconds` or `--samples` for a longer or shorter sweep (e.g. `--seconds 60`).
- At 20 Hz the first cycle lasts 50 ms, so the 50 ms fade covers one cycle at the start.
- Output is not dithered when converted to 24-bit. This is fine for a synthetic test signal.
- Generated WAVs are not tracked by any convention yet. Decide later whether to commit them or just the script.
