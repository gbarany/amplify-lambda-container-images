# Read the input parameters
parameters=`cat`
echo "$parameters" | "$(jq -r '.data.amplify.environment.projectPath' <<< "$parameters")/containers/deploy.sh"
