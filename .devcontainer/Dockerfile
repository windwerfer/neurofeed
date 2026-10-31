FROM mcr.microsoft.com/devcontainers/python:3.13-trixie

# Best way in Docker: copy the pre-built binary
COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /usr/local/bin/

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    clang \
    cmake \
    ninja-build \
    pkg-config \
    libgtk-3-dev \
    liblzma-dev \
    libsecret-1-0 \
    openjdk-21-jdk \
    zstd \
    libpulse0 \
    pipewire-bin \
    alsa-utils \
    libasound2-dev \
    libasound2-plugins \
    pulseaudio-utils \
    libdbus-1-dev \
    libx11-dev \
    libxkbcommon-dev \
    libwayland-dev \
    libegl1-mesa-dev \
    libgl1-mesa-dev \
    && rm -rf /var/lib/apt/lists/*

# Container has no ALSA card: route ALSA's default PCM through the
# PulseAudio/PipeWire socket mounted at /tmp/pulse-socket (PULSE_SERVER is set
# in devcontainer.json). Desktop feedback audio is cpal. libasound2-plugins
# ships the config only as a ".example", so activate it here — otherwise the
# ALSA backend fails with "Unknown PCM default" and no sound plays.
RUN cp /etc/alsa/conf.d/99-pulseaudio-default.conf.example \
      /etc/alsa/conf.d/99-pulseaudio-default.conf

ARG USERNAME=vscode

RUN chsh -s /usr/bin/zsh vscode

# Pre-create volume targets and assign ownership to vscode
RUN mkdir -p /opt/download-cache /home/vscode
RUN chown -R vscode:vscode /home/vscode /opt/download-cache

USER $USERNAME
WORKDIR /workspaces/neurofeed

RUN mkdir -p /home/vscode/android-sdk

# Populated by the neurofeed_home volume + rust-setup.sh / android-setup.sh.
# NDK matches apps/neurofeed-android/android/app/build.gradle.kts (ndkVersion).
ENV ANDROID_HOME="/home/vscode/android-sdk"
ENV ANDROID_NDK_HOME="${ANDROID_HOME}/ndk/27.2.12479018"
ENV JAVA_HOME="/usr/lib/jvm/java-21-openjdk-amd64"
ENV PATH="/home/vscode/.cargo/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"
ENV PATH="/workspaces/neurofeed/.venv/bin:/root/.local/bin:/home/vscode/.local/bin:/home/vscode/.opencode/bin:/home/vscode/.grok/bin:${PATH}"

# Best-effort: mark helper scripts executable in the image.
# The workspace is bind-mounted at runtime, so post-setup.sh also chmod's.
RUN chmod +x .devcontainer/*.sh 2>/dev/null || true
