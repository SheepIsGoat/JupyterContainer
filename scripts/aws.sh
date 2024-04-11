#!/bin/bash
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PARENT_DIR=$(dirname "$SCRIPT_DIR")
DIR_NAME=$(basename "$SCRIPT_DIR")

# set to root of repo
PROJECT_DIR="$PARENT_DIR"
PROJECT_NAME=$(basename "$PROJECT_DIR")

COMMAND=$1  # The first argument, should be 'create', 'attach', or 'somethingelse'
shift


GPU=nvidia
TRUST_POLICY="eks-trust-policy.json"
AWS_REGION="us-west-1"
# VERSION="1.0"
TOKEN="passwd"

IMG_TEMP="${PROJECT_NAME}_${GPU}_jupyterbox"
IMG="${IMG_TEMP,,}"  # makes it lowercase

###########################
# docker-compose commands #
###########################
composeUp () {
    VERSION=$1
    if [ -z "$VERSION" ]; then
        VERSION="latest"
    fi

    IMAGE_NAME="$IMG:$VERSION" \
        GPU=$GPU \
        docker-compose -f "$PROJECT_DIR/docker/$GPU/docker-compose.yml" up &
    
    DOCKER_COMPOSE_PID=$!
    export DOCKER_COMPOSE_PID

    URL="http://127.0.0.1:8888/lab?token=$TOKEN"
    while ! curl -s "$URL" > /dev/null; do
        echo "Waiting for $URL to become available..."
        sleep 1
    done

    xdg-open "$URL"

    trap 'composeDown; exit 130' SIGINT

    wait $DOCKER_COMPOSE_PID
}

composeDown() {
    VERSION=$1
    if [ -z "$VERSION" ]; then
        VERSION="latest"
    fi

    for dir in "data" "models" "notebooks"; do
        chown -R $(id -u):$(id -g) "$PROJECT_DIR/$dir"
    done

    IMAGE_NAME="$IMG:$VERSION" GPU=$GPU docker-compose -f "$PROJECT_DIR/docker/$GPU/docker-compose.yml" down
}

composeBuild () {
    VERSION=$1
    if [ -z "$VERSION" ]; then
        echo "Version not specified, cannot push."
        exit 1
    fi
    echo Building Image Version: $VERSION ...
    IMAGE_NAME="$IMG:$VERSION" \
        GPU=$GPU \
        docker-compose -f "$PROJECT_DIR/docker/$GPU/docker-compose.yml" build \
        && docker tag "$IMG:$VERSION" "$IMG:latest"
}

showImage () {
    echo "Your ECR fully qualified image name is:"
    echo "$FULLY_QUALIFIED_IMAGE_NAME"
}


#######################################
# AWS ECR container registry commands #
#######################################

ecrPushImage () {
    # Pushes the latest version of the image both with the `latest` and specific version tags
    AWS_ACCOUNT_ID=$1
    VERSION=$2
    REPOSITORY_PATH="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com" #TODO: set this to the path of your ECS repository
    FULLY_QUALIFIED_IMAGE_NAME="$REPOSITORY_PATH/$IMG"

    if [ -z "$AWS_ACCOUNT_ID" ]; then
        echo "AWS account id not specified, cannot push. Look for a 12 digit number in the top right of your AWS browser console."
        exit 1
    fi

    if [ -z "$VERSION" ]; then
        echo "Version not specified, cannot push."
        exit 1
    fi



    docker tag "$IMG:latest" "$FULLY_QUALIFIED_IMAGE_NAME:latest"
    docker tag "$IMG:$VERSION" "$FULLY_QUALIFIED_IMAGE_NAME:$VERSION"  # should this be $IMG:$IMG on the left? fixed it don't know why it was $IMG:$IMG before
    aws ecr get-login-password --region "$AWS_REGION" | \
        docker login \
        --username AWS \
        --password-stdin "$REPOSITORY_PATH"
    docker push "$FULLY_QUALIFIED_IMAGE_NAME:latest"
    docker push "$FULLY_QUALIFIED_IMAGE_NAME:$VERSION"
}

ecrCreateRepo () {
    aws ecr create-repository --repository-name "$IMG"
    echo Created ECR repository: "$IMG".
}


###########
# Helpers #
###########

condaLocker() {
    # Create a conda-lock file for precise package control
    ENV_YAML_PATH="$PROJECT_DIR/docker/$GPU/environment.yaml"

    # Check if path to environment.yml is provided as $1
    if [ "$#" -ne 0 ]; then
        ENV_YAML_PATH=$1
    fi
    ENV_NAME=$(grep 'name:' $ENV_YAML_PATH | cut -d ' ' -f 2)
    echo "Using environment.yaml at path $ENV_YAML_PATH with name $ENV_NAME"

    # Docker image to use
    LOCKER_IMAGE="continuumio/miniconda3"
    CONTAINER_NAME="conda-locker"

    # Check if the container already exists
    EXISTING_CONTAINER=$(docker ps -q -f name=$CONTAINER_NAME)

    if [ -z "$EXISTING_CONTAINER" ]; then
        type=new
        CONTAINER_ID=$(docker run -d -it --name $CONTAINER_NAME --rm $LOCKER_IMAGE /bin/bash)
    else
        type=existing
        CONTAINER_ID="$EXISTING_CONTAINER"
    fi
    echo "Starting $type container with id $CONTAINER_ID"

    # Install conda-lock in the container (if not already installed)
    # Check if conda-lock is installed
#     if ! docker exec $CONTAINER_ID conda list conda-lock; then
#         # Install conda-lock if not found
#         docker exec $CONTAINER_ID conda install -c conda-forge conda-lock -y
#     fi
    docker exec $CONTAINER_ID conda install -c conda-forge conda-lock -y


    # Copy the environment.yml to the container
    docker cp "$ENV_YAML_PATH" "$CONTAINER_ID:/environment.yml"

    # Generate the conda-lock file
    LOCKFILE_NAME="${ENV_NAME}-conda-lock.yml"  #-linux-64.conda-lock"
    if docker exec $CONTAINER_ID conda-lock -f /environment.yml -p linux-64; then
        # Copy the conda-lock file back to the host
        docker cp "$CONTAINER_ID:/conda-lock.yml" "$PROJECT_DIR/docker/$GPU/$LOCKFILE_NAME"
        echo "Conda-lock file generated: $LOCKFILE_NAME"
    else
        echo "Failed to generate the conda-lock file."
    fi
}


#######################################################
# Commands for creating kubernetes cluster on AWS EC2 #
#######################################################

createRole () {
    # create an IAM role and attach appropriate permissions

    ROLE_NAME=JupyterHub
    ROLE_TYPE=$1

    if [ "$ROLE_TYPE" = "eks" ]; then
        POLICIES=("AmazonEKSClusterPolicy" "AmazonEKSServicePolicy" "AmazonEC2ContainerRegistryReadOnly")
        TRUST_POLICY="eks-trust-policy.json"
    elif [ "$ROLE_TYPE" = "k8s" ]; then
        POLICIES=(
            "AmazonEC2FullAccess"
            "IAMFullAccess"
            "AmazonS3FullAccess"
            "AmazonVPCFullAccess"
            "AmazonRoute53FullAccess"
            "AmazonSQSFullAccess"
            "AmazonEventBridgeFullAccess"
            "AmazonEC2ContainerRegistryReadOnly"
        ) #Route53 optional
        TRUST_POLICY="k8s-trust-policy.json"
    else
        echo "Error: missing ROLE_TYPE"
        echo "Usage: aws.sh role [eks|k8s] [ROLE_NAME] to create a role"
        exit 1
    fi

    aws iam create-role --role-name "$ROLE_NAME" --assume-role-policy-document "file://$TRUST_POLICY"

    for POLICY in "${POLICIES[@]}"; do
        aws iam attach-role-policy --role-name "$ROLE_NAME" --policy-arn arn:aws:iam::aws:policy/$POLICY
    done
    echo "Attached ${#POLICIES[@]} policies to eks role $ROLE_NAME: ${POLICIES[*]}"
}

createProfile() {
    # Create an instance profile and attach an IAM role to it. This will later be assigned to the EC2 k8s CI node.
    ROLE_NAME=JupyterHub
    PROFILE_NAME="$ROLE_NAME"
    aws iam create-instance-profile --instance-profile-name "$PROFILE_NAME"
    echo "Created instance-profile $NAME"

    aws iam add-role-to-instance-profile --instance-profile-name "$PROFILE_NAME" --role-name "$ROLE_NAME"
    echo "Added role"
}

createKey() {
    # create a key pair for EC2 ssh access
    KEY_NAME=$1

    if [ -z "$KEY_NAME" ]; then
        KEY_NAME="My-Jupyterlab-K8s-Key"
        echo "No key name provided, using default"
    fi
    echo "Creating key $KEY_NAME"
    aws ec2 create-key-pair --key-name $KEY_NAME --query 'KeyMaterial' --output text > ${KEY_NAME}_pair.pem
    chmod 600 "${KEY_NAME}_pair.pem"
    echo "Key pair saved to ${KEY_NAME}_pair.pem"
}


createKubernetesCiNode() {
    # Creates the k8s CI node for configuring your cluster using kops. Uses alpine image.
    ROLE_NAME=JupyterHub
    KEY_NAME=My-Jupyterlab-K8s-Key
    SUBNET_ID=$1
    AWS_REGION="us-west-1"
    ACCT_ID=538276064493  # ID for alpine account  https://gitlab.alpinelinux.org/alpine/cloud/alpine-cloud-images
    INSTANCE_TYPE="t2.micro"
    BLOCK_SIZE=5

    # Search for the latest Alpine Linux AMI
    AMI_ID=$(aws ec2 describe-images \
        --owners $ACCT_ID \
        --filters \
            "Name=architecture,Values=x86_64" \
            "Name=root-device-type,Values=ebs" \
            "Name=virtualization-type,Values=hvm" \
            "Name=state,Values=available" \
            "Name=name,Values='alpine-3.*-x86_64-bios-tiny-*'" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --region $AWS_REGION \
        --output text)

    # swap query with this to see all images
#             --query 'reverse(sort_by(Images, &CreationDate))[].[ImageId,Name,CreationDate]' \

    # Output the AMI ID
    echo "Creating new $INSTANCE_TYPE instance with latest Alpine Linux AMI ID in $AWS_REGION: $AMI_ID"

    INSTANCE_ID=$(aws ec2 run-instances \
        --image-id "$AMI_ID" \
        --instance-type "$INSTANCE_TYPE" \
        --subnet-id "$SUBNET_ID" \
        --iam-instance-profile Name="$ROLE_NAME" \
        --key-name "$KEY_NAME" \
        --block-device-mappings "[{\"DeviceName\":\"/dev/xvda\",\"Ebs\":{\"VolumeSize\":$BLOCK_SIZE,\"Encrypted\":true}}]" \
        --associate-public-ip-address \
        | jq -r '.Instances[0].InstanceId')

    PUBLIC_IPV4=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
    echo "Created instance with id $INSTANCE_ID and public ipv4 $PUBLIC_IPV4"
    echo "Consider running the command: ssh -i ${KEY_NAME}_pair.pem alpine@$PUBLIC_IPV4"
}


#########################
# Control flow and help #
#########################

usage() {
    echo "Usage: $0 COMMAND"
    echo "Commands:"
    echo "  up        - Starts the Docker Compose services"
    echo "  down      - Stops the Docker Compose services"
    echo "  build     - Builds the Docker image"
    echo "  push      - Pushes the Docker image to ECR"
    echo "  buildpush - Builds and pushes the Docker image to ECR"
    echo "  repo      - Creates an ECR repository"
    echo "  conda     - Create a conda-lock file"
    echo "  role      - Creates an IAM role for AWS"
    echo "  profile   - Creates an instance profile for AWS IAM role"
    echo "  key       - Creates an EC2 key pair"
    echo "  cihost    - Creates a Kubernetes CI node on AWS EC2"
}

case $COMMAND in
    up)
        VERSION=$1
        composeUp $VERSION
        ;;
    down)
        VERSION=$1
        composeDown $VERSION
        ;;
    build)
        VERSION=$1
        composeBuild $VERSION
        ;;
    push)
        AWS_ACCOUNT_ID=$1
        VERSION=$2
        ecrPushImage $AWS_ACCOUNT_ID $VERSION
        ;;
    buildpush)
        AWS_ACCOUNT_ID=$1
        VERSION=$2
        composeBuild $VERSION
        ecrPushImage $AWS_ACCOUNT_ID $VERSION
        ;;
    repo)
        ecrCreateRepo
        ;;
    conda)
        condaLocker $1  # path to environment.yaml file
        ;;
    role)
        ROLE_TYPE=$1
        createRole $ROLE_TYPE  # eks or k8s
        ;;

    profile)
        createProfile
        ;;

    key)
        KEY_NAME=$1
        createKey $KEY_NAME
        ;;

    cihost)
        SUBNET=$1
        createKubernetesCiNode $SUBNET
        ;;

    help)
        usage
        ;;

    *)
        echo "Invalid command"
        usage
        exit 1
        ;;
esac
