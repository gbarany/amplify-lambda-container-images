#!/bin/bash

set -e

source $(dirname "$0")/utils.sh

# Delete an ECR repository
delete_ecr_repo() {
    local repo_name=$1
    local ecr_repo_exists=$(aws ecr describe-repositories --repository-names "${repo_name}" --region "${AWS_REGION}" --profile "${AWS_PROFILE}" 2>&1)

    if echo "${ecr_repo_exists}" | grep -q 'repository'; then
        aws ecr delete-repository --repository-name "${repo_name}" --region "${AWS_REGION}" --profile "${AWS_PROFILE}" --force > /dev/tty
        printf "ECR repo %s deleted\n" "${repo_name}"
    else
        printf "ECR repo %s does not exist\n" "${repo_name}"
    fi
}


# Remove function
remove() {
    AMPLIFY_ENV_NAME=$1
    PROJECT_PATH=$2
    AMPLIFY_APPID=$3
    AWS_REGION=$4
    AWS_PROFILE=$5
    AWS_ACCOUNT_ID=$6

    read -r AMPLIFY_ENV_NAME PROJECT_PATH AMPLIFY_APPID AWS_REGION AWS_PROFILE AWS_ACCOUNT_ID <<< $(get_aws_info $AMPLIFY_ENV_NAME $PROJECT_PATH $AMPLIFY_APPID $AWS_REGION $AWS_PROFILE $AWS_ACCOUNT_ID)
    
    printf "AWS_PROFILE: %s\n" "${AWS_PROFILE}" > /dev/tty
    printf "AMPLIFY_ENV_NAME: %s\n" "${AMPLIFY_ENV_NAME}" > /dev/tty
    printf "AMPLIFY_APPID: %s\n" "${AMPLIFY_APPID}" > /dev/tty
    printf "AWS_ACCOUNT_ID: %s\n" "${AWS_ACCOUNT_ID}" > /dev/tty
    printf "AWS_REGION: %s\n" "${AWS_REGION}" > /dev/tty

    for dir in $(dirname "$0")/*/ ; do
        local function_name=$(basename "$dir")
        local repo_name="amplify-${AMPLIFY_APPID}-$(echo ${function_name} | tr '[:upper:]' '[:lower:]')-${AMPLIFY_ENV_NAME}"
        local image_name="$(echo ${function_name} | tr '[:upper:]' '[:lower:]')-${AMPLIFY_ENV_NAME}"

        delete_ecr_repo "${repo_name}"
        
        # delete secrets from ssm parameter store
        aws ssm describe-parameters --profile "${AWS_PROFILE}" --region "${AWS_REGION}" --query 'Parameters[].Name' --output text | tr '\t' '\n' | grep "/amplify/${AMPLIFY_APPID}/${AMPLIFY_ENV_NAME}/${function_name}/"  | xargs -n 5 -I {} sh -c 'export AWS_PROFILE='"${AWS_PROFILE}"'; export AWS_REGION='"${AWS_REGION}"'; aws ssm delete-parameter --profile "${AWS_PROFILE}" --region "${AWS_REGION}" --name {}; sleep 2' > /dev/tty
    done
}

parameters=`cat`

# Extract the sub command from the parameters
sub_command=$(jq -r '.data.amplify.subCommand' <<< "$parameters")

# Check if the sub command is 'env'
if [ "$sub_command" = "env" ]; then
    # Extract the environment name from the parameters
    ENVIRONMENT_NAME_TO_DELETE=$(jq -r '.data.amplify.argv[-1]' <<< "$parameters")
    ENVIRONMENT_NAME_CURRENT=$(jq -r '.data.amplify.environment.envName' <<< "$parameters")

    printf "Environment to delete: %s\n" ${ENVIRONMENT_NAME_TO_DELETE} > /dev/tty
    printf "Current environment: %s\n" ${ENVIRONMENT_NAME_CURRENT} > /dev/tty
    # Extract the project path from the parameters
    PROJECT_PATH=$(jq -r '.data.amplify.environment.projectPath' <<< "$parameters")

    source ${PROJECT_PATH}/containers/utils.sh

    # Extract the Amplify App ID from the team provider info JSON file
    AMPLIFY_APPID=$(jq -r ".${ENVIRONMENT_NAME_CURRENT}.awscloudformation.AmplifyAppId" <<< "$(cat ${PROJECT_PATH}/amplify/team-provider-info.json)")
    
    read -r AMPLIFY_ENV_NAME PROJECT_PATH AMPLIFY_APPID AWS_REGION AWS_PROFILE AWS_ACCOUNT_ID <<< $(get_aws_info $ENVIRONMENT_NAME_CURRENT $PROJECT_PATH )
    
    # Run the delete script with the environment name and project path as arguments
    remove "$ENVIRONMENT_NAME_TO_DELETE" "$PROJECT_PATH" "$AMPLIFY_APPID" "$AWS_REGION" "$AWS_PROFILE" "$AWS_ACCOUNT_ID"
fi

