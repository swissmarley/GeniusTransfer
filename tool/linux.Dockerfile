ARG BASE_IMAGE=debian:bookworm
FROM ${BASE_IMAGE}

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl git unzip xz-utils zip clang cmake ninja-build \
    pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev dpkg-dev \
    libgl1-mesa-dri libegl1 libgl1 libgles2 xvfb xauth dbus-x11 xdg-utils xdg-user-dirs \
    python3 file desktop-file-utils xdg-desktop-portal xdg-desktop-portal-gtk \
    && rm -rf /var/lib/apt/lists/*

ARG FLUTTER_VERSION=3.47.7
RUN git clone --depth 1 --branch "${FLUTTER_VERSION}" \
    https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}"
RUN flutter config --no-analytics --enable-linux-desktop && flutter precache --linux

WORKDIR /work
