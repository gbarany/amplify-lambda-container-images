#!/bin/bash

set -e
# Get the current Amplify environment name
get_amplify_env_name() {
    amplify status | grep "Current Environment:" | awk '{print $4}' | sed 's/\x1b\[[0-9;]*m//g'
}


# Find the Amplify configuration and extract the profile name
find_project_path() {
  local amplify_env_name=${AMPLIFY_ENV_NAME}
  local cur_dir=$(pwd)

  while [[ "$cur_dir" != "" && ! -d "$cur_dir/amplify" ]]; do
    cur_dir=${cur_dir%/*}
  done

  echo "$cur_dir"
}

get_aws_info() {
    local AMPLIFY_ENV_NAME=$1
    local PROJECT_PATH=$2
    local AMPLIFY_APPID=$3
    local AWS_REGION=$4
    local AWS_PROFILE=$5
    local AWS_ACCOUNT_ID=$6

    # If AMPLIFY_ENV_NAME is blank, get the value from get_amplify_env_name
    if [ -z "$AMPLIFY_ENV_NAME" ]; then
        AMPLIFY_ENV_NAME=$(get_amplify_env_name)
    fi

    # If PROJECT_PATH is blank, get the value from find_project_path
    if [ -z "$PROJECT_PATH" ]; then
        PROJECT_PATH=$(find_project_path)
    fi

    if [ -z "$AMPLIFY_APPID" ]; then
        AMPLIFY_APPID=$(jq -r ".${AMPLIFY_ENV_NAME}.awscloudformation.AmplifyAppId" <<< "$(cat ${PROJECT_PATH}/amplify/team-provider-info.json)")
    fi

    if [ -z "$AWS_REGION" ]; then
      AWS_REGION=$(jq -r ".${AMPLIFY_ENV_NAME}.awscloudformation.Region" <<< "$(cat ${PROJECT_PATH}/amplify/team-provider-info.json)")
    fi
    
    if [ -z "$AWS_PROFILE" ]; then
      AWS_PROFILE=$(jq -r ".${AMPLIFY_ENV_NAME}.profileName" <<< "$(cat ${PROJECT_PATH}/amplify/.config/local-aws-info.json)")
    fi
    
    if [ -z "$AWS_ACCOUNT_ID" ]; then
      AWS_ACCOUNT_ID=$(jq -r ".${AMPLIFY_ENV_NAME}.awscloudformation.UnauthRoleArn" <<< "$(cat ${PROJECT_PATH}/amplify/team-provider-info.json)" | cut -d':' -f5)
    fi

    echo "$AMPLIFY_ENV_NAME $PROJECT_PATH $AMPLIFY_APPID $AWS_REGION $AWS_PROFILE $AWS_ACCOUNT_ID"
}


set_params() {
  local cloudformation_template=$1
  local amplify_appid=$2
  local next_tag=$3
  local repo_name=$4
  if [ -f "$cloudformation_template" ]; then
    if jq -e '.Parameters.amplifyAppId.Default' $cloudformation_template > /dev/null; then
      printf "Updating Amplify App ID in %s\n" "$cloudformation_template" > /dev/tty
      jq --arg amplify_appid "$amplify_appid" '.Parameters.amplifyAppId.Default = $amplify_appid' $cloudformation_template > temp.json && mv temp.json $cloudformation_template
    fi
    if jq -e '.Parameters.imageTag.Default' $cloudformation_template > /dev/null; then
      printf "Updating image tag in %s\n" "$cloudformation_template" > /dev/tty
      jq --arg next_tag "$next_tag" '.Parameters.imageTag.Default = $next_tag' $cloudformation_template > temp.json && mv temp.json $cloudformation_template
    fi
    if jq -e '.Parameters.repositoryName.Default' $cloudformation_template > /dev/null; then
      printf "Updating repository name in %s\n" "$cloudformation_template" > /dev/tty
      jq --arg repo_name "$repo_name" '.Parameters.repositoryName.Default = $repo_name' $cloudformation_template > temp.json && mv temp.json $cloudformation_template
    fi

  fi
}


# Function to update cloudformation templates
set_params_all() {
  # The first argument to the function is the project path
  local project_path=$1
  # The second argument to the function is the Amplify App ID
  local amplify_appid=$2
  local next_tag=$3
  local repo_name=$3
  # Loop over all directories in the custom backend directory of the Amplify project
  for dir in ${project_path}/amplify/backend/custom/*/
  do
    # Remove trailing slash from directory path
    dir=${dir%*/}
    # Loop over all JSON files in the current directory that match the pattern *-cloudformation-template.json
    for cloudformation_template in "${dir}"/*-cloudformation-template.json
    do
      $(set_params "$cloudformation_template" "$amplify_appid" "$next_tag" "$repo_name")
    done
  done
}

upload_container_secrets() {
    
    # Check if ssm-diff is installed
    if ! command -v ssm-diff &> /dev/null
    then
        printf "ssm-diff could not be found. Installing it now.\n" > /dev/tty
        pip install ssm-diff || { printf "Failed to install ssm-diff. Run 'pip install ssm-diff' manually.\n" > /dev/tty; exit 1; }
    fi

    local AMPLIFY_ENV_NAME=$1
    local PROJECT_PATH=$2
    
    printf $(get_aws_info $AMPLIFY_ENV_NAME $PROJECT_PATH)  > /dev/tty

    read -r AMPLIFY_ENV_NAME PROJECT_PATH AMPLIFY_APPID AWS_REGION AWS_PROFILE AWS_ACCOUNT_ID <<< $(get_aws_info $AMPLIFY_ENV_NAME $PROJECT_PATH)
        
    printf "AWS_PROFILE: %s\n" "${AWS_PROFILE}" > /dev/tty
    printf "AMPLIFY_ENV_NAME: %s\n" "${AMPLIFY_ENV_NAME}" > /dev/tty
    printf "AMPLIFY_APPID: %s\n" "${AMPLIFY_APPID}" > /dev/tty
    printf "AWS_ACCOUNT_ID: %s\n" "${AWS_ACCOUNT_ID}" > /dev/tty
    printf "AWS_REGION: %s\n" "${AWS_REGION}" > /dev/tty

    # Initialize params
    sed -i '' "s/<INJECTED_BY_HOOKS>/${AMPLIFY_APPID}/g" "${PROJECT_PATH}/containers/container-secrets.yml"
    params="-f ${PROJECT_PATH}/containers/container-secrets.yml --profile ${AWS_PROFILE}"

    for dir in ${PROJECT_PATH}/containers/*/ ; do
        local function_name=$(basename "$dir")
        params+=" -p /amplify/${AMPLIFY_APPID}/${AMPLIFY_ENV_NAME}/${function_name}"
    done
    
    AWS_DEFAULT_REGION=${AWS_REGION} ssm-diff ${params} apply > /dev/tty
    sed -i '' "s/${AMPLIFY_APPID}/<INJECTED_BY_HOOKS>/g" "${PROJECT_PATH}/containers/container-secrets.yml"
}