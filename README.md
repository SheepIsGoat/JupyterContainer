# Jupyter Notebook Experiments in Docker

## Introduction
Run your Jupyter notebook experiments in a Docker environment to ensure consistent experimentation across teams.

## Features
- Mimic production environments accurately by customizing your Dockerfile with your project's public and private packages.
- Utilize your own hardware for faster processing compared to cloud services like Google Colab, while maintaining data privacy.
- Isolate code execution from your host machine, enhancing the safety of your experiments.

## Usage
Execute the following command:

## Features
- Mimic production environments with precision by modifying your Dockerfile with your project's public and private packages.
- Use your own hardware to massively speed up processing over cloud offerings like google collab, and keep your data private.
- Isolate code execution from host machine for safer experimentation.

## Usage
Execute the following command
'''
./run.sh [build/up/down]
'''

## Setup
- Default GPU configuration is GPU=nvidia, but this can be changed at the top of run.sh
- **Note**: currently only set up for nvidia, you'd have add other options yourself)
- Mount your local files in the /data, /models, and /notebooks directories to make them accessible from within your container.
- **Packages:**
  - **Docker**: Essential for creating and managing containers.
  - **Docker Compose**: Useful for defining and running multi-container Docker applications.
  - **NVIDIA Drivers**: Necessary for GPU support, particularly if you're using NVIDIA GPUs.
  - **NVIDIA Docker Toolkit**: Allows Docker containers to access the GPU, crucial for computation-heavy tasks.

