# makesweep

Generate audio sweep files using ffmpeg.

May be run with ffmpeg installed locally or using a container image.

## Usage

```
❯ ./make_sweep.sh -h
Usage: make_sweep.sh [options]

Generate a logarithmic sine sweep WAV (48 kHz, 24-bit, mono, 50 ms fades).

Options:
  -p, --preset <name>      Frequency range preset, or 'all' for one file per
                           preset (default: full)
  -s, --start <Hz>         Start frequency (overrides the preset)
  -e, --end <Hz>           End frequency (overrides the preset)
  -t, --seconds <seconds>  Sweep length in seconds, e.g. 30 or 5.5
  -n, --samples <count>    Sweep length in samples at 48000 Hz, e.g. 262144
                           Give either --seconds or --samples, not both.
                           (default: 1440000 samples = 30 s)
  -l, --level <dBFS>       Peak level, 0 or negative (default: -12)
  -P, --padding <time>     Silence added before and after the sweep, with a
                           unit: ms or s, e.g. 500ms or 5s (default: 5s)
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
```

### Examples:

```
❯ ./make_sweep.sh -p 4k -n 1000000
Wrote sweep_20-4000Hz_log_1000000samples.wav (20 Hz -> 4000 Hz, 1000000 samples = 20.833 s, -12 dBFS, 5s padding each end)
```

### Using Docker:

#### Build the Docker Image:
```
❯ docker build -t makesweep .
```

#### Run makesweep:
```
❯ docker run --rm -v ./test:/output makesweep:latest  -p all -n 1000000
Wrote sweep_20-60Hz_log_1000000samples.wav (20 Hz -> 60 Hz, 1000000 samples = 20.833 s, -12 dBFS, 5s padding each end)
Wrote sweep_20-250Hz_log_1000000samples.wav (20 Hz -> 250 Hz, 1000000 samples = 20.833 s, -12 dBFS, 5s padding each end)
Wrote sweep_250-4000Hz_log_1000000samples.wav (250 Hz -> 4000 Hz, 1000000 samples = 20.833 s, -12 dBFS, 5s padding each end)
Wrote sweep_4000-20000Hz_log_1000000samples.wav (4000 Hz -> 20000 Hz, 1000000 samples = 20.833 s, -12 dBFS, 5s padding each end)
Wrote sweep_20-4000Hz_log_1000000samples.wav (20 Hz -> 4000 Hz, 1000000 samples = 20.833 s, -12 dBFS, 5s padding each end)
Wrote sweep_20-20000Hz_log_1000000samples.wav (20 Hz -> 20000 Hz, 1000000 samples = 20.833 s, -12 dBFS, 5s padding each end)

❯ ls -la test
total 52080
drwxr-xr-x@  8 khemani  staff      256 Oct 23 17:55 .
drwxr-xr-x@ 15 khemani  staff      480 Oct 23 17:55 ..
-rw-r--r--@  1 khemani  staff  4440102 Oct 23 17:55 sweep_20-20000Hz_log_1000000samples.wav
-rw-r--r--@  1 khemani  staff  4440102 Oct 23 17:55 sweep_20-250Hz_log_1000000samples.wav
-rw-r--r--@  1 khemani  staff  4440102 Oct 23 17:55 sweep_20-4000Hz_log_1000000samples.wav
-rw-r--r--@  1 khemani  staff  4440102 Oct 23 17:55 sweep_20-60Hz_log_1000000samples.wav
-rw-r--r--@  1 khemani  staff  4440102 Oct 23 17:55 sweep_250-4000Hz_log_1000000samples.wav
-rw-r--r--@  1 khemani  staff  4440102 Oct 23 17:55 sweep_4000-20000Hz_log_1000000samples.wav
```

