parameters=`cat`

# Extract the project path from the parameters using jq
project_path=$(jq -r '.data.amplify.environment.projectPath' <<< "$parameters")

# Initialize the Amplify App ID variable to blank
amplify_appid="<INJECTED_BY_HOOKS>"
next_tag="<INJECTED_BY_HOOKS>"
repo_name="<INJECTED_BY_HOOKS>"

source "${project_path}/containers/utils.sh"
$(set_params_all "$project_path" "$amplify_appid" "$next_tag" "$repo_name")