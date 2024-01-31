################
# STAGE 1 OF 3 #
################ 
ARG CUDA_VERSION
ARG CUDA_TOOLS
FROM nvidia/cuda:$CUDA_VERSION-$CUDA_TOOLS-ubuntu22.04 as base

ARG GPU

# Remove any third-party apt sources to avoid issues with expiring keys.
RUN rm -f /etc/apt/sources.list.d/*.list

# Install some basic utilities.
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    sudo \
    git \
    bzip2 \
    libx11-6 \
 && rm -rf /var/lib/apt/lists/*

# Create a working directory.
RUN mkdir /app
WORKDIR /app

# Create a non-root user and switch to it.
RUN adduser --disabled-password --gecos '' --shell /bin/bash user \
 && chown -R user:user /app
RUN echo "user ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/90-user
USER user

# All users can use /home/user as their home directory.
ENV HOME=/home/user
RUN mkdir $HOME/.cache $HOME/.config \
 && chmod -R 777 $HOME

# Download and install Micromamba.
RUN curl -sL https://micro.mamba.pm/api/micromamba/linux-64/1.1.0 \
  | sudo tar -xvj -C /usr/local bin/micromamba
ENV MAMBA_EXE=/usr/local/bin/micromamba \
    MAMBA_ROOT_PREFIX=/home/user/micromamba \
    CONDA_PREFIX=/home/user/micromamba \
    PATH=/home/user/micromamba/bin:$PATH

# Set up the base Conda environment by installing base packages
COPY docker/${GPU}/cuda-$CUDA_VERSION-conda-lock.yml /app/conda-lock.yml
RUN echo $CUDA_HOME && export CUDA_HOME=/usr/local/cuda && micromamba create -qy -n base -f /app/conda-lock.yml \
  && rm /app/conda-lock.yml \
  && micromamba shell init --shell=bash --prefix="$MAMBA_ROOT_PREFIX" \
  && micromamba clean -qya


ENV LD_LIBRARY_PATH=/home/user/micromamba/lib:$LD_LIBRARY_PATH
ENV LD_LIBRARY_PATH=/home/user/micromamba/pkgs/cuda-cudart-11.8.89-0/lib:$LD_LIBRARY_PATH

# Fix for https://github.com/pytorch/pytorch/issues/97041
RUN ln -s "$CONDA_PREFIX/lib/libnvrtc.so.11.8.89" "$CONDA_PREFIX/lib/libnvrtc.so"

# Set the default command to python3.
CMD ["python3"]


################
# STAGE 2 OF 3 #
################ 
FROM base AS builder

COPY requirements.txt /tmp/

USER root

# Activate the Conda environment
RUN /home/user/micromamba/bin/conda init bash
SHELL ["/bin/bash", "-c"]
RUN source /home/user/micromamba/etc/profile.d/conda.sh && conda activate base

WORKDIR /app

# Install local files as pip packagess
# COPY ./app /app/LoLLMsWebUI_server
# COPY ./api /app/api

RUN \
  apt-get update && \
  apt-get install -y python3-pip && \
  # python3 /app/LoLLMsWebUI_server/setup.py install && \
  # python3 /app/api/setup.py install && \
  pip install --no-cache-dir \
    -r /tmp/requirements.txt && \
  rm /tmp/requirements.txt
  # rm -rf /srv/LoLLMsWebUI_server \
        #  /srv/api


################
# STAGE 3 OF 3 #
################ 
FROM builder as APP

WORKDIR /app
COPY . /app

# COPY ./app /srv/app
# COPY ./static /srv/static
# COPY ./templates /srv/templates
# COPY ./web /srv/web
# COPY ./assets /srv/assets
# COPY ./configs /src/configs
# COPY ./restart_script.py /srv/restart_script.py
# COPY ./docker/global_paths_cfg.yaml /srv/global_paths_cfg.yaml


ENV SHELL=/bin/bash

CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--allow-root", "--no-browser"]
EXPOSE 8888
