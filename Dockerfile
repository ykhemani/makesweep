# Build:  docker build -t makesweep .
# Run:    docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/output" makesweep --preset low --seconds 60
# Help:   docker run --rm makesweep -h
FROM linuxserver/ffmpeg:9.0.2

COPY make_sweep.sh /usr/local/bin/make_sweep.sh

# Generated files are written here; mount a host directory on it.
WORKDIR /output

# Replaces the base image's ffmpeg wrapper entrypoint.
ENTRYPOINT ["/usr/local/bin/make_sweep.sh"]
