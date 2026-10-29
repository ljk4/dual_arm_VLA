# syntax=docker/dockerfile:1
# The NVIDIA driver is supplied by the host through NVIDIA Container Toolkit.
# Python packages, assets and CuRobo are installed at runtime into persistent volumes.
ARG BASE_IMAGE=nvidia/cuda:12.4.1-base-ubuntu22.04
FROM ${BASE_IMAGE}

ARG DEBIAN_FRONTEND=noninteractive

# HTTP_PROXY / HTTPS_PROXY / NO_PROXY are Docker's predefined build arguments.
# Do not redeclare or persist them as ENV: the builder supplies them only to RUN.
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential cmake ninja-build pkg-config \
        ca-certificates curl git wget openssh-client unzip tmux \
        ffmpeg libvulkan1 mesa-vulkan-drivers vulkan-tools \
        libgl1 libegl1 libglib2.0-0 libxext6 libxrender1 libsm6 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL --retry 3 https://astral.sh/uv/install.sh -o /tmp/uv-install.sh \
    && UV_UNMANAGED_INSTALL=/usr/local/bin sh /tmp/uv-install.sh \
    && rm /tmp/uv-install.sh \
    && curl -fsSL --retry 3 \
        https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh \
        -o /tmp/miniconda.sh \
    && bash /tmp/miniconda.sh -b -p /opt/conda \
    && rm /tmp/miniconda.sh \
    && /opt/conda/bin/conda clean -afy \
    && install -d -m 700 /tmp/runtime-root

ENV PATH="/opt/conda/bin:${PATH}" \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics \
    XDG_RUNTIME_DIR=/tmp/runtime-root \
    UV_CACHE_DIR=/root/.cache/uv \
    UV_PYTHON_INSTALL_DIR=/root/.cache/uv/python \
    UV_LINK_MODE=copy \
    HF_HOME=/root/.cache/huggingface \
    CONDA_PKGS_DIRS=/root/.cache/conda/pkgs

COPY gpu-check.sh /usr/local/bin/robotwin-gpu-check
RUN chmod 755 /usr/local/bin/robotwin-gpu-check

WORKDIR /workspace/dual_arm_VLA
CMD ["sleep", "infinity"]
