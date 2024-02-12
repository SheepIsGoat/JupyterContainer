# Jupyter Notebook Experiments in Docker

## Introduction
Run your Jupyter notebook experiments in a Docker environment to ensure consistent experimentation across teams.

## Features
- Mimic production environments with precision by modifying your Dockerfile with your project's public and private packages.
- Use your own hardware to massively speed up processing over cloud offerings like google collab, and keep your data private.
- Isolate code execution from host machine for safer experimentation.

## Usage
Execute the following command
```
# build a conda-lock file for package pinning
./conda-locker.sh

# build or run your container
./run.sh [build/up/down]
```

## Setup
- Default GPU configuration is GPU=nvidia, but this can be changed at the top of run.sh
- **Note**: currently only set up for nvidia, you'd have add other options yourself)
- Set your CUDA version and image type in Dockerfile
  - 'base' image type is best for most uses
  - 'devel' image type is required for packages that need nvcc, like 'flash-attn'
- Mount your local files in the /data, /models, and /notebooks directories to make them accessible from within your container.
- **Packages:**
  - **Docker**: Essential for creating and managing containers.
  - **Docker Compose**: Useful for defining and running multi-container Docker applications.
  - **NVIDIA Drivers**: Necessary for GPU support, particularly if you're using NVIDIA GPUs.
  - **NVIDIA Docker Toolkit**: Allows Docker containers to access the GPU, crucial for computation-heavy tasks.

# Setting up JupyterLab Cluster in AWS
*Adapted from: https://z2jh.jupyter.org/en/stable/kubernetes/amazon/step-zero-aws.html*

Make sure you have an s3 bucket to store your cluster configuration, or create a new one with:
`aws s3api create-bucket --bucket $BUCKET_NAME --region us-west-1 --create-bucket-configuration LocationConstraint=us-west-1`
And enable versioning:
`aws s3api put-bucket-versioning --bucket $BUCKET_NAME --versioning-configuration Status=Enabled`


Show existing key pairs: `aws ec2 describe-key-pairs`
Or create a new key `./aws.sh key [KEY_NAME]`

Find the subnet you'd like to launch the instance in, or create a new one. This is easier from the console.


Run `aws.sh cihost [SUBNET_ID]` to create the CI instance, and take note of the public ipv4 for the next step.

SSH into the instance `ssh -i My-Jupyterlab-K8s-Key_pair.pem alpine@$PUBLIC_IPV4`

Now, set up the instance. Make sure to change the s3 bucket command
```
# install curl
doas apk update
doas apk add curl

# Install kops https://github.com/kubernetes/kops/blob/HEAD/docs/install.md
curl -Lo kops https://github.com/kubernetes/kops/releases/download/$(curl -s https://api.github.com/repos/kubernetes/kops/releases/latest | grep tag_name | cut -d '"' -f 4)/kops-linux-amd64
chmod +x ./kops
doas mv ./kops /usr/local/bin/

# install kubectl
curl -Lo kubectl https://dl.k8s.io/release/$(curl -s -L https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl
chmod +x ./kubectl
doas mv ./kubectl /usr/local/bin/kubectl


# Set environment

export NAME=sheepisgoat.k8s.local
ssh-keygen -t ed25519 -f /home/alpine/.ssh/id_ed25519 -N ""
export KOPS_STATE_STORE="s3://jupyterlab-k8s"
export REGION=`curl -s http://169.254.169.254/latest/dynamic/instance-identity/document|grep region|awk -F\" '{print $4}'`

# Install awscli
doas apk add --no-cache aws-cli
```

```
# again if running just this command
export NAME=sheepisgoat.k8s.local
export KOPS_STATE_STORE="s3://jupyterlab-k8s"

export ZONES="us-west-1b,us-west-1c"
export NODE_SIZE=p2.xlarge # t3.medium if you don't need GPUs
export NODE_VOLUME_SIZE=50
kops create cluster $NAME \
  --zones "$ZONES" \
  --authorization RBAC \
  --control-plane-size t3a.small \
  --control-plane-volume-size 10 \
  --node-size $NODE_SIZE \
  --node-volume-size $NODE_VOLUME_SIZE \
  --networking cilium \
  --yes
```
This will create a base cluster.yaml template we can use later. First, lets make sure we have enabled all the features we want.
- Note that the `--topology private` flag may be important, based on your organization's security requirements.
- Further reading: https://github.com/kubernetes/kops/blob/HEAD/docs/networking.md

`kops validate cluster --wait 10m`
`kubectl get nodes --show-labels`

For encryption in transit we can edit cilium networking.
Create a password
```
cat <<EOF | kops create secret ciliumpassword --name $NAME -f -
keys: $(echo "3 rfc4106(gcm(aes)) $(echo $(dd if=/dev/urandom count=20 bs=1 2> /dev/null| xxd -p -c 64)) 128")
EOF
```
Edit cluster config `kops edit cluster sheepisgoat.k8s.local`
```
  networking:
    cilium:
      enableNodePort: true
      enableEncryption: true
      enableL7Proxy: false
      encryptionType: wireguard
```

Apply the changes `kops update cluster $NAME --yes`
Then update the cluster nodes `kops rolling-update cluster $NAME --yes`

To set up encrypted dynamic storage `vi storageclass.yml`
```
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  annotations:
    storageclass.beta.kubernetes.io/is-default-class: "true"
  name: gp2
provisioner: kubernetes.io/aws-ebs
parameters:
  type: gp2
  encrypted: "true"
```
and run the commands
```
kubectl delete storageclass gp2
kubectl apply -f storageclass.yml
```

Check encryption status of nodes, it should say WireGuard
`kubectl exec -n kube-system -ti $(kubectl get pods -n kube-system -l k8s-app=cilium -o jsonpath='{.items[0].metadata.name}') -- cilium status --verbose | grep Encryption`

Further reading: https://github.com/kubernetes/kops/blob/master/docs/getting_started/aws.md


## Setting Up Helm
```
curl -O https://get.helm.sh/helm-v3.14.0-linux-amd64.tar.gz
tar -zxvf helm-v3.14.0-linux-amd64.tar.gz
doas mv linux-amd64/helm /usr/local/bin/helm
helm version
rm helm-v3.14.0-linux-amd64.tar.gz
rm -r linux-amd64
```

```
export NAMESPACE=sheepisgoat

helm repo add jupyterhub https://hub.jupyter.org/helm-chart/
helm repo update
helm upgrade --cleanup-on-fail \
  --install my-jupyterhub-release jupyterhub/jupyterhub \
  --namespace $NAMESPACE \
  --version=3.2.0 \
  --values config.yaml \
  --create-namespace
kubectl get pod --namespace $NAMESPACE
kubectl config set-context $(kubectl config current-context) --namespace $NAMESPACE
kubectl --namespace $NAMESPACE get service proxy-public
```


Choose jupyterlab as the default UI
Edit the config `vi config.yaml`. Make sure to replace values as needed, especially for your image.
```
singleuser:
  startTimeout: 180
  defaultUrl: "/lab"
  image:
    name: [ACCOUNT_ID].dkr.ecr.[REGION].amazonaws.com/[REPO_NAME]
    tag: "latest"
  extraEnv:
    JUPYTERHUB_SINGLEUSER_APP: "jupyter_server.serverapp.ServerApp"
  extraFiles:
    # jupyter_notebook_config reference: https://jupyter-notebook.readthedocs.io/en/stable/config.html
    jupyter_notebook_config.json:
      mountPath: /etc/jupyter/jupyter_notebook_config.json
      # data is a YAML structure here but will be rendered to JSON file as our
      # file extension is ".json".
      data:
        MappingKernelManager:
          # cull_idle_timeout: timeout (in seconds) after which an idle kernel is
          # considered ready to be culled
          cull_idle_timeout: 1200 # default: 0

          # cull_interval: the interval (in seconds) on which to check for idle
          # kernels exceeding the cull timeout value
          cull_interval: 120 # default: 300

          # cull_connected: whether to consider culling kernels which have one
          # or more connections
          cull_connected: true # default: false

          # cull_busy: whether to consider culling kernels which are currently
          # busy running some code
          cull_busy: false # default: false
  storage:
    type: dynamic
    capacity: 5Gi
    dynamic:
      storageClass: "kops-csi-1-21"  # Specify your desired storage class
    extraVolumes:
      - name: shm-volume
        emptyDir:
          medium: Memory
    extraVolumeMounts:
      - name: shm-volume
        mountPath: /dev/shm

hub:
  networkPolicy:
    egress:
      - ports:
          - port: 443
  config:
    KubeSpawner:
      start_timeout: 600
      http_timeout: 600
    Authenticator:
      admin_users:
        - sheepadmin
        - goatadmin
```

Get the public ip address for your deployment, to access from your browser:
`kubectl --namespace $NAMESPACE get service proxy-public`


### Troubleshooting

**Credentials** require refresh every 18H. If you get a credential error just run `kops export kubecfg --admin`.
You'll also need to export these variables every terminal session.
```
export NAME=sheepisgoat.k8s.local
export KOPS_STATE_STORE="s3://jupyterlab-k8s"
export NAMESPACE=sheepisgoat
```
-Get the pod id for the hub component `export HUB=$(kubectl get pods -n $NAMESPACE -l component=hub -o custom-columns=:metadata.name | tail -n +2)`.
--or run `kubectl get pods -n $NAMESPACE` to list all pods.

**Checking jupyterhub logs**
-View the Logs of the JupyterHub Pod: run `kubectl logs $HUB -n sheepisgoat`.
--If you want to follow the logs in real-time, add the -f flag: `kubectl logs -f $HUB -n sheepisgoat`.

-Review the Logs: Look for any error messages or warnings, particularly those related to PVC creation or storage issues.

**Exec-ing intop pods**
Exec in `kubectl exec -it $HUB -n sheepisgoat -- /bin/bash`
Hit kubetnetes API `curl -k https://kubernetes.default.svc`

