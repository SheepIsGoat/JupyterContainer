################
# STAGE 1 OF 3 #
################ 
ARG CUDA_VERSION
ARG CUDA_TOOLS
FROM nvidia/cuda:$CUDA_VERSION-$CUDA_TOOLS-ubuntu22.04 as base


ARG GPU

ENV DEBIAN_FRONTEND=noninteractive

# Remove any third-party apt sources to avoid issues with expiring keys.
RUN rm -f /etc/apt/sources.list.d/*.list
# Install some basic utilities.
RUN apt-get update \
  && apt-get upgrade --yes \
  && apt-get install --yes --no-install-recommends \
    python3-pip \
    curl \
    ca-certificates \
    git \
    bzip2 \
    libx11-6 \
    dnsutils \
    iputils-ping \
    tini \
 && rm -rf /var/lib/apt/lists/*


RUN mkdir /app ##import
WORKDIR /app ##import

# Create a non-root user and switch to it.
ENV HOME=/home/jovyan \
    NB_USER=jovyan \
    NB_UID=1000
RUN adduser \
  --disabled-password \
  --gecos "Default user" \
  --uid ${NB_UID} \
  --home ${HOME} \
  --force-badname \
  jovyan

# All users can use /home/jovyan as their home directory.
RUN mkdir $HOME/.cache $HOME/.config \
 && chmod -R 777 $HOME


# Download and install Micromamba.
USER root
RUN curl -sL https://micro.mamba.pm/api/micromamba/linux-64/1.5.6 \
  | tar -xvj -C /usr/local bin/micromamba \
  && chown -R jovyan:jovyan /usr/local/bin/micromamba

RUN mkdir -p /opt/micromamba \
  && chown -R jovyan:jovyan /opt/micromamba

USER jovyan
ENV MAMBA_EXE=/usr/local/bin/micromamba \
    MAMBA_ROOT_PREFIX=/opt/micromamba/micromamba \
    CONDA_PREFIX=/opt/micromamba/micromamba \
    PATH=/opt/micromamba/micromamba/bin:$PATH

# Set up the base Conda environment by installing base packages
COPY docker/${GPU}/cuda-$CUDA_VERSION-conda-lock.yml /tmp/conda-lock.yml
RUN export CUDA_HOME=/usr/local/cuda \
  && rm -rf ${MAMBA_ROOT_PREFIX}/* \
  && micromamba create -qy -n base -f /tmp/conda-lock.yml
RUN micromamba shell init --shell=bash --root-prefix="$MAMBA_ROOT_PREFIX" \
  && micromamba clean -qya
ENV PATH=/opt/micromamba/envs/base/bin:$PATH

ENV LD_LIBRARY_PATH=${MAMBA_ROOT_PREFIX}/lib:$LD_LIBRARY_PATH
ENV LD_LIBRARY_PATH=${MAMBA_ROOT_PREFIX}/pkgs/cuda-cudart-11.8.89-0/lib:$LD_LIBRARY_PATH

# Fix for https://github.com/pytorch/pytorch/issues/97041
RUN ln -s "$CONDA_PREFIX/lib/libnvrtc.so.11.8.89" "$CONDA_PREFIX/lib/libnvrtc.so"


# Set the default command to python3.
CMD ["python3"]


################
# STAGE 2 OF 3 #
################ 
FROM base AS builder

# Install local files as pip packagess
# RUN mkdir /home/app
# COPY ./app /home/app/

COPY requirements.txt /tmp/
RUN /opt/micromamba/micromamba/bin/conda init bash
SHELL ["/bin/bash", "-c"]
RUN \
  source /opt/micromamba/micromamba/etc/profile.d/conda.sh \
  && conda activate base \
  && pip3 install --no-cache-dir -r /tmp/requirements.txt
  # python3 /home/app/setup.py install && \
  # rm -rf /home/app/localPackage


################
# STAGE 3 OF 3 #
################ 
FROM builder as APP

USER jovyan
WORKDIR $HOME
COPY . $HOME

ENV SHELL=/bin/bash

ENTRYPOINT ["tini", "--"]
CMD ["jupyter", "lab"]
EXPOSE 8888
