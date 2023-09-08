#!/bin/bash

set -e

source $(dirname "$0")/utils.sh

# Create an ECR repository
create_ecr_repo() {
    local repo_name=$1
    local ecr_repo_exists=$(aws ecr describe-repositories --repository-names "${repo_name}" --region "${AWS_REGION}" --profile "${AWS_PROFILE}" 2>&1)

    trap 'catch_create_ecr_repo_error $? $LINENO' ERR

    if echo "${ecr_repo_exists}" | grep -q 'Exception'; then
        aws ecr create-repository --repository-name "${repo_name}" --region "${AWS_REGION}" --profile "${AWS_PROFILE}" > /dev/null || exit 1
        printf "ECR repo %s created\n" "${repo_name}" > /dev/tty
    else
        printf "ECR repo %s already exists\n" "${repo_name}" > /dev/tty
    fi
}

catch_create_ecr_repo_error() {
    local exit_code=$1
    local line_number=$2
    printf "An error occurred at line %s with exit code %s\n" "${line_number}" "${exit_code}" > /dev/tty
    exit "${exit_code}"
}

get_next_tag() {
    local repo_name=$1
    local latest_tag=$(aws ecr list-images --repository-name "${repo_name}" --region "${AWS_REGION}" --profile "${AWS_PROFILE}" --query 'sort_by(imageIds,&imageTag)[*].imageTag' --output json  | jq -r '.[]' | sort -nr | head -n 1)
    
    if [ -z "${latest_tag}" ]; then
        echo 1
    else
        echo $((latest_tag + 1))
    fi
}

# Build and push a Docker image to the ECR repository
build_and_push_docker_image() {
    local image_name=$1
    local repo_name=$2
    local function_name=$3
    local next_tag=$(get_next_tag "${repo_name}")

    printf "Building Docker image: %s\n" "${image_name}. This may take a few minutes..."  > /dev/tty
    docker buildx build --platform linux/amd64 -t "${image_name}:${next_tag}" "$(dirname "$0")/${function_name}" > /dev/tty

    printf "Logging into AWS ECR\n"  > /dev/tty
    aws ecr get-login-password --region "${AWS_REGION}" --profile "${AWS_PROFILE}" | docker login --username AWS --password-stdin "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com" > /dev/tty

    printf "Tagging Docker image: %s\n" "${image_name}"  > /dev/tty
    docker tag "${image_name}:${next_tag}" "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${repo_name}:${next_tag}" > /dev/tty

    printf "Pushing Docker image to ECR\n"  > /dev/tty 
    docker push "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${repo_name}:${next_tag}" > /dev/tty

    printf "Docker image successfully built and pushed to ECR with tag ${next_tag}!\n"  > /dev/tty
        
    local min_tag=$(aws ecr describe-images --repository-name "${repo_name}" --image-ids imageTag="${next_tag}" --region "${AWS_REGION}" --profile "${AWS_PROFILE}" --query 'imageDetails[*].imageTags' --output json | jq -r '.[][]' | sort -n | head -n 1)
    if [ "${min_tag}" != "${next_tag}" ]; then
        printf "Keep on using tag %s as it's identical image to tag %s\n" "${min_tag}" "${next_tag}" > /dev/tty
    fi

    echo "${min_tag}"
    
}

# Main function
deploy() {
    AMPLIFY_ENV_NAME=$1
    PROJECT_PATH=$2
    
    read -r AMPLIFY_ENV_NAME PROJECT_PATH AMPLIFY_APPID AWS_REGION AWS_PROFILE AWS_ACCOUNT_ID <<< $(get_aws_info $AMPLIFY_ENV_NAME $PROJECT_PATH)
    
    printf "AWS_PROFILE: %s\n" "${AWS_PROFILE}" > /dev/tty
    printf "AMPLIFY_ENV_NAME: %s\n" "${AMPLIFY_ENV_NAME}" > /dev/tty
    printf "AMPLIFY_APPID: %s\n" "${AMPLIFY_APPID}" > /dev/tty
    printf "AWS_ACCOUNT_ID: %s\n" "${AWS_ACCOUNT_ID}" > /dev/tty
    printf "AWS_REGION: %s\n" "${AWS_REGION}" > /dev/tty

    # Create a temporary file to store function names and next tags
    function_tag_mapping_file=$(mktemp)

    for dir in $(dirname "$0")/*/ ; do
        local function_name=$(basename "$dir")
        local repo_name="amplify-${AMPLIFY_APPID}-$(echo ${function_name} | tr '[:upper:]' '[:lower:]')-${AMPLIFY_ENV_NAME}"
        local image_name="$(echo ${function_name} | tr '[:upper:]' '[:lower:]')-${AMPLIFY_ENV_NAME}"

        printf "Deploying %s function to ECR repo %s\n" "${function_name}" "${repo_name}" > /dev/tty
        create_ecr_repo "${repo_name}"
        aws ecr set-repository-policy --repository-name "${repo_name}" --region "${AWS_REGION}" --profile "${AWS_PROFILE}" --policy-text file://$(dirname "$0")/ecr-policy.json > /dev/null
        next_tag=$(build_and_push_docker_image "${image_name}" "${repo_name}" "${function_name}")
        echo "${function_name},${next_tag}" >> "$function_tag_mapping_file"
    done

    # Print the path of the temporary file
    echo "$function_tag_mapping_file"
}

# Read the input parameters
parameters=`cat`

# Extract the environment name from the parameters
environment_name=$(jq -r '.data.amplify.environment.envName' <<< "$parameters")

# Extract the project path from the parameters
project_path=$(jq -r '.data.amplify.environment.projectPath' <<< "$parameters")

# Extract the Amplify App ID from the team-provider-info.json file in the project path
amplify_appid=$(jq -r ".${environment_name}.awscloudformation.AmplifyAppId" <<< "$(cat ${project_path}/amplify/team-provider-info.json)")

source "${project_path}/containers/utils.sh"

# Execute the deploy.sh script located in the containers directory of the project path
function_tag_mapping_file=$(deploy "$environment_name" "$project_path")

# Read the function names and next tags from the temporary file
while IFS=',' read -r function_name next_tag; do
    printf "Function: %s,  Tag: %s\n" "${function_name}" "${next_tag}" > /dev/tty
    cloudformation_template="${project_path}/amplify/backend/custom/${function_name}/${function_name}-cloudformation-template.json"
    # Set repo_name as per the instructions
    repo_name="amplify-${amplify_appid}-$(echo ${function_name} | tr '[:upper:]' '[:lower:]')-${environment_name}"
    $(set_params "$cloudformation_template" "$amplify_appid" "$next_tag" "$repo_name")
done < "$function_tag_mapping_file"

# Delete the temporary file
rm "$function_tag_mapping_file"

# Upload secrets
$(upload_container_secrets $environment_name $project_path)


