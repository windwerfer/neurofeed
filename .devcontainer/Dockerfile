FROM mcr.microsoft.com/devcontainers/python:3.12-trixie

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
    libmpv2 \
    pipewire-bin \
    alsa-utils \
    pulseaudio-utils \
    && rm -rf /var/lib/apt/lists/*




ARG USERNAME=vscode

RUN chsh -s /usr/bin/zsh vscode


# Pre-create volume targets and assign ownership to vscode
RUN mkdir -p /opt/download-cache /home/vscode
RUN chown -R vscode:vscode /home/vscode /opt/download-cache


USER $USERNAME
WORKDIR /workspaces/flutter_muse_ml

RUN mkdir -p /home/vscode/android-sdk /home/vscode/flutter


# additional PATH var - just in case
# These will be populated by named volumes + post-setup.sh
ENV ANDROID_HOME="/home/vscode/android-sdk"
ENV ANDROID_NDK_HOME="${ANDROID_HOME}/ndk/28.2.13676358"
ENV PATH="/home/vscode/flutter/bin:/home/vscode/.cargo/bin:${ANDROID_HOME}/cmdline-tools/latest/bin:${ANDROID_HOME}/platform-tools:${PATH}"
ENV PATH="/workspaces/flutter_muse_ml/.venv/bin:/root/.local/bin:/home/vscode/.local/bin:/home/vscode/.opencode/bin:/home/vscode/.grok/bin:${PATH}"



# Best-effort: mark helper scripts executable in the image.
# Note: the workspace is usually bind-mounted at runtime, so post-setup.sh
# also does a chmod (see post-setup.sh). This helps in some build/copy scenarios.
RUN chmod +x .devcontainer/*.sh 2>/dev/null || true
