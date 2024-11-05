ARG CUDA_VERSION=11.8.0
ARG OS_VERSION=22.04
ARG UID=1007

# Define base image.
FROM nvidia/cuda:${CUDA_VERSION}-devel-ubuntu${OS_VERSION}
ARG CUDA_VERSION
ARG OS_VERSION
ARG UID

# metainformation
LABEL org.opencontainers.image.version="0.1.18"
LABEL org.opencontainers.image.licenses="Apache License 2.0"
LABEL org.opencontainers.image.base.name="docker.io/library/nvidia/cuda:${CUDA_VERSION}-devel-ubuntu${OS_VERSION}"

ENV CUDA_ARCHITECTURES=89

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Berlin
ENV CUDA_HOME="/usr/local/cuda"

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    curl \
    ffmpeg \
    git \
    libatlas-base-dev \
    libboost-filesystem-dev \
    libboost-graph-dev \
    libboost-program-options-dev \
    libboost-system-dev \
    libboost-test-dev \
    libhdf5-dev \
    libcgal-dev \
    libeigen3-dev \
    libflann-dev \
    libfreeimage-dev \
    libgflags-dev \
    libglew-dev \
    libgoogle-glog-dev \
    libmetis-dev \
    libprotobuf-dev \
    libqt5opengl5-dev \
    libsqlite3-dev \
    libsuitesparse-dev \
    nano \
    protobuf-compiler \
    python-is-python3 \
    python3 \
    python3-dev \
    python3-distutils \
    python3-pip \
    qtbase5-dev \
    sudo \
    vim-tiny \
    wget && \
    rm -rf /var/lib/apt/lists/*

# Install GLOG (required by ceres).
RUN git clone --branch v0.6.0 https://github.com/google/glog.git --single-branch && \
    cd glog && \
    mkdir build && \
    cd build && \
    cmake .. && \
    make -j "$(nproc)" && \
    make install && \
    cd ../.. && \
    rm -rf glog

ENV LD_LIBRARY_PATH="${LD_LIBRARY_PATH}:/usr/local/lib"

# Install Ceres-solver (required by colmap).
RUN git clone --branch 2.1.0 https://ceres-solver.googlesource.com/ceres-solver.git --single-branch && \
    cd ceres-solver && \
    git checkout "$(git describe --tags)" && \
    mkdir build && \
    cd build && \
    cmake .. -DBUILD_TESTING=OFF -DBUILD_EXAMPLES=OFF && \
    make -j "$(nproc)" && \
    make install && \
    cd ../.. && \
    rm -rf ceres-solver

# Install colmap.
RUN git clone --branch 3.8 https://github.com/colmap/colmap.git --single-branch && \
    cd colmap && \
    mkdir build && \
    cd build && \
    cmake .. -DCUDA_ENABLED=ON \
             -DCMAKE_CUDA_ARCHITECTURES=${CUDA_ARCHITECTURES} && \
    make -j "$(nproc)" && \
    make install && \
    cd ../.. && \
    rm -rf colmap

# # Create non-root user and set up environment.
# RUN useradd -m -d /home/user -g root -G sudo -u ${UID} user
# RUN usermod -aG sudo user
# RUN echo "user:user" | chpasswd
# RUN echo '%sudo ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers


ARG UID=1007
ARG GID=1007
ARG USERNAME=developer
RUN apt-get update \
&& apt-get install -y \
   sudo \
&& rm -rf /var/lib/apt/lists/* \
&& groupadd --gid 998 docker \
&& groupadd --gid 1013 oxford_spires \
&& groupadd --gid 1014 nerfstudio \
&& addgroup --gid ${GID} ${USERNAME} \
&& adduser --disabled-password --gecos '' --uid ${UID} --gid ${GID} ${USERNAME} \
&& usermod -aG docker,oxford_spires,nerfstudio ${USERNAME} \
&& echo ${USERNAME} ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/${USERNAME} 
# && chown -R ${UID}:${GID} /home/${USERNAME} \
# && chown -R ${UID}:${GID} ${SOURCE_DIR}


WORKDIR /home/docker_dev
SHELL ["/bin/bash", "-c"]

RUN python3 -m pip install --upgrade pip setuptools pathtools promise pybind11

RUN CUDA_VER=${CUDA_VERSION%.*} && CUDA_VER=${CUDA_VER//./} && python3 -m pip install \
    torch==2.0.0+cu${CUDA_VER} \
    torchvision==0.15.0+cu${CUDA_VER} \
        --extra-index-url https://download.pytorch.org/whl/cu${CUDA_VER}


RUN git clone --branch v0.4.0 --recursive https://github.com/colmap/pycolmap.git && \
    cd pycolmap && \
    python3 -m pip install . && \
    cd ..

RUN git clone --branch master --recursive https://github.com/cvg/Hierarchical-Localization.git && \
    cd Hierarchical-Localization && \
    python3 -m pip install -e . && \
    cd ..

RUN python3 -m pip install omegaconf

ENV TORCH_CUDA_ARCH_LIST="6.0;6.1;7.0;7.5;8.0+PTX"
ARG GAUSSIAN_SPLATTING_DIR=/home/gaussian-splatting
WORKDIR ${GAUSSIAN_SPLATTING_DIR}
COPY ./submodules ${GAUSSIAN_SPLATTING_DIR}/submodules
# Install submodules. Permission issue or CUDA ENV, architecture issue 
RUN pip install --no-cache-dir submodules/diff-gaussian-rasterization && \
    pip install --no-cache-dir submodules/simple-knn && \
    pip install --no-cache-dir submodules/fused-ssim

COPY requirements.txt ${GAUSSIAN_SPLATTING_DIR}/requirements.txt
RUN pip install -r ${GAUSSIAN_SPLATTING_DIR}/requirements.txt

# USER root
# RUN chsh -s /bin/bash user

WORKDIR /home/docker_dev
USER ${USERNAME}
RUN echo "PS1='${debian_chroot:+($debian_chroot)}\[\033[01;33m\]\u@docker-\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '" >> ~/.bashrc