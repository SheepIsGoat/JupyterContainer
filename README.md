Run your Jupyter notebook experiments in a docker environment for consistent experimentation across teams.

Mimic production environments with precision by modifying your Dockerfile with your project's public and private packages.

Use your own hardware to massively speed up processing over cloud offerings like google collab, and keep your data private.

Isolate code execution from host machine for safer experimentation.



Usage:

./run.sh [build/up/down]


Setup:

By default GPU=nvidia, but can be changed at the top of run.sh. (Note: currently only set up for nvidia, you'd have add other options yourself)

Mount local files in the /data, /models, and /notebooks directories to be accessible from your container.


