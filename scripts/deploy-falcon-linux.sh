#!/usr/bin/env bash

# This script is used to deploy the falcon sensor via the ec2 image builder pipeline.
# It is intended to be run as a build step in the component.
#
# Author: CrowdStrike Cloud Integration Solution Architects

SECRET_STORAGE_METHOD="${1:-}"
SECRETS_MANAGER_SECRET_NAME="${2:-}"
SSM_FALCON_CLOUD="${3:-}"
SSM_FALCON_CLIENT_ID="${4:-}"
SSM_FALCON_CLIENT_SECRET="${5:-}"
SENSOR_VERSION_DECREMENT="${6:-}"
PROVISIONING_TOKEN="${7:-}"
SENSOR_UPDATE_POLICY_NAME="${8:-}"
TAGS="${9:-}"
PROXY_HOST="${10:-}"
PROXY_PORT="${11:-}"
BILLING="${12:-}"
AWS_CLI_REGION="${13:-}"
# INSTALLED_AWS_CLI=false

## DEBUG INPUTS ##
# For each of the input parameters, lets print them out
# declare -a input_params=(
#     "SECRET_STORAGE_METHOD"
#     "SECRETS_MANAGER_SECRET_NAME"
#     "SSM_FALCON_CLOUD"
#     "SSM_FALCON_CLIENT_ID"
#     "SSM_FALCON_CLIENT_SECRET"
#     "SENSOR_VERSION_DECREMENT"
#     "PROVISIONING_TOKEN"
#     "SENSOR_UPDATE_POLICY_NAME"
#     "TAGS"
#     "PROXY_HOST"
#     "PROXY_PORT"
#     "BILLING"
# )

# for param in "${input_params[@]}"; do
#     echo "$param: ${!param}"
# done
## END DEBUG ##

log() {
    local log_level=${2:-INFO}
    echo "[$(date +'%Y-%m-%dT%H:%M:%S')] $log_level: $1" >&2
}

die() {
    log "$1" "ERROR"
    exit 1
}

sanitize_input_params() {
    local -a input_params=(
        "SECRET_STORAGE_METHOD"
        "SECRETS_MANAGER_SECRET_NAME"
        "SSM_FALCON_CLOUD"
        "SSM_FALCON_CLIENT_ID"
        "SSM_FALCON_CLIENT_SECRET"
        "SENSOR_VERSION_DECREMENT"
        "PROVISIONING_TOKEN"
        "SENSOR_UPDATE_POLICY_NAME"
        "TAGS"
        "PROXY_HOST"
        "PROXY_PORT"
        "BILLING"
    )

    for param in "${input_params[@]}"; do
        local param_value=${!param}
        param_value=$(echo "$param_value" | xargs)
        eval "$param=\"$param_value\""
    done
}

validate_storage_method() {
    if [[ -z "$SECRET_STORAGE_METHOD" ]]; then
        die "Secret storage method is not provided."
    fi

    if [[ "$SECRET_STORAGE_METHOD" != "SecretsManager" && "$SECRET_STORAGE_METHOD" != "ParameterStore" ]]; then
        die "Invalid secret storage method: $SECRET_STORAGE_METHOD. Must be either 'SecretsManager' or 'ParameterStore'."
    fi
}

validate_auth_input() {
    validate_storage_method

    # Once we know the secret storage method, we can validate the rest of the input
    case $SECRET_STORAGE_METHOD in
        "SecretsManager")
            if [[ -z "$SECRETS_MANAGER_SECRET_NAME" ]]; then
                die "Secrets Manager secret name is not provided."
            fi
            ;;
        "ParameterStore")
            local invalid=false
            local -a required_input=(
                "SSM_FALCON_CLOUD"
                "SSM_FALCON_CLIENT_ID"
                "SSM_FALCON_CLIENT_SECRET"
            )
            for input in "${required_input[@]}"; do
                local input_value=${!input}
                if [[ -z "$input_value" ]]; then
                    log "Missing required input for SSM: $input" "ERROR"
                    invalid=true
                fi
            done
            [[ "$invalid" == true ]] && exit 1
            ;;
    esac
}

set_cli_region() {
    # Validate AWS_CLI_REGION then set
    if [[ -z "$AWS_CLI_REGION" ]]; then
        die "AWSRegion parameter was not provided."
    else
        log "Setting AWS CLI region to: $AWS_CLI_REGION"
        export AWS_DEFAULT_REGION="$AWS_CLI_REGION"
    fi
}

### Validate AWS CLI
# check_aws_cli() {
#     if ! command -v aws &>/dev/null; then
#         # die "AWS CLI is not installed. Please install AWS CLI."
#         log "AWS CLI is not installed. Installing AWS CLI..."
#         install_aws_cli
#     else
#         log "AWS CLI is installed."
#     fi
# }

# install_aws_cli() {
#     curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
#     unzip awscliv2.zip
#     sudo ./aws/install
#     rm -rf aws awscliv2.zip
#     # if /usr/local/bin is not in the PATH, add it
#     if [[ ":$PATH:" != *":/usr/local/bin:"* ]]; then
#         export PATH=$PATH:/usr/local/bin
#     fi
#     # check if we can run aws command
#     if ! command -v aws &>/dev/null; then
#         die "Failed to install AWS CLI."
#     fi
#     log "AWS CLI has been installed."
#     INSTALLED_AWS_CLI=true
# }

# remove_aws_cli() {
#     if [[ "$INSTALLED_AWS_CLI" == true ]]; then
#         log "Removing AWS CLI..."
#         sudo rm /usr/local/bin/aws
#         sudo rm /usr/local/bin/aws_completer
#         sudo rm -rf /usr/local/aws-cli
#         log "AWS CLI has been removed."
#     fi
# }

## SSM Parameter Store
get_ssm_parameter() {
    local parameter_name=$1
    local parameter_value

    if ! parameter_value=$(aws ssm get-parameter --name "$parameter_name" --with-decryption --query 'Parameter.Value' --output text 2>/dev/null); then
        die "Failed to retrieve SSM parameter: $parameter_name"
    fi
    echo "$parameter_value"
}

## Secrets Manager
get_secret() {
    local secret_name=$1
    local secret_value

    if ! secret_value=$(aws secretsmanager get-secret-value --secret-id "$secret_name" --query 'SecretString' --output text 2>/dev/null); then
        die "Failed to retrieve Secrets Manager secret: $secret_name"
    fi
    echo "$secret_value"
}

get_value_from_secret() {
    local secret=$1
    local key=$2
    local value

    # Could use jq here, but not sure if we want to make it a dependency/assumption
    value=$(echo "$secret" | grep -oiP "\"$key\": *\K\"[^\"]*\"" | sed 's/"//g')
    if [[ -z "$value" ]]; then
        die "Failed to retrieve $key from secret."
    fi
    echo "$value"
}

## Install Falcon Sensor
setup_env_vars() {
    local script_args=(
        "FALCON_CLIENT_ID:$CLIENT_ID"
        "FALCON_CLIENT_SECRET:$CLIENT_SECRET"
        "FALCON_CLOUD:$CLOUD"
        "FALCON_SENSOR_VERSION_DECREMENT:$SENSOR_VERSION_DECREMENT"
        "FALCON_PROVISIONING_TOKEN:$PROVISIONING_TOKEN"
        "FALCON_SENSOR_UPDATE_POLICY_NAME:$SENSOR_UPDATE_POLICY_NAME"
        "FALCON_TAGS:$TAGS"
        "FALCON_APH:$PROXY_HOST"
        "FALCON_APP:$PROXY_PORT"
        "FALCON_BILLING:$BILLING"
        "PREP_GOLDEN_IMAGE:true"
    )

    for param in "${script_args[@]}"; do
        local param_name=${param%%:*}
        local value=${param#*:}
        if [[ -n "$value" ]]; then
            log "Setting environment variable: $param_name"
            export "$param_name"="$value"
        fi
    done

    # Set FALCON_APD if proxy host and port are provided
    if [[ -n "$PROXY_HOST" && -n "$PROXY_PORT" ]]; then
        log "Setting environment variable: FALCON_APD"
        export FALCON_APD="false"
    fi
}

install_falcon_sensor() {
    local script_path=$1
    setup_env_vars
    log "Executing Falcon sensor installation script..."
    sudo -E "$script_path"
}

main() {
    sanitize_input_params
    validate_auth_input
    set_cli_region

    case $SECRET_STORAGE_METHOD in
        "SecretsManager")
            local secret
            secret=$(get_secret "$SECRETS_MANAGER_SECRET_NAME")
            CLIENT_ID=$(get_value_from_secret "$secret" "ClientId")
            CLIENT_SECRET=$(get_value_from_secret "$secret" "ClientSecret")
            CLOUD=$(get_value_from_secret "$secret" "Cloud")
            ;;
        "ParameterStore")
            CLIENT_ID=$(get_ssm_parameter "$SSM_FALCON_CLIENT_ID")
            CLIENT_SECRET=$(get_ssm_parameter "$SSM_FALCON_CLIENT_SECRET")
            CLOUD=$(get_ssm_parameter "$SSM_FALCON_CLOUD")
            ;;
    esac

    local script_path="/tmp/falcon-linux-install.sh"
    chmod +x "$script_path"
    install_falcon_sensor "$script_path"
}

main
