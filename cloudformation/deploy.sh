#!/bin/bash

# HITL Platform - CloudFormation Deployment Script
# Equivalent to the three Terraform stacks: VPC, AMI, and App

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
ENVIRONMENT="dev"
AWS_REGION="us-east-1"
ACTION="deploy"
STACK="all"
BUILD_AMI=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
    exit 1
}

info() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')] INFO:${NC} $1"
}

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy HITL Platform CloudFormation stacks (equivalent to Terraform deployment)

OPTIONS:
    -e, --environment  Environment (dev, stage, prod) [default: dev]
    -r, --region       AWS region [default: us-east-1]
    -a, --action       Action (deploy, update, delete, status) [default: deploy]
    -s, --stack        Stack to deploy (vpc, ami, app, all) [default: all]
    -b, --build-ami    Build a new AMI (default: use latest existing AMI)
    -h, --help         Show this help message

DEPLOYMENT ORDER:
    The stacks must be deployed in this specific order:
    1. VPC Stack          - Network foundation
    2. AMI                - Creates golden AMI (15-20 min build time)
    3. Application Stack  - Uses VPC and AMI from previous stacks

EXAMPLES:
    # Deploy all stacks with new AMI build (slow, 20+ min)
    $0 -e dev --build-ami

    # Deploy all stacks using existing AMI (fast)
    $0 -e dev

    # Deploy only app stack (uses latest existing AMI)
    $0 -e dev -s app

    # Deploy only VPC stack to stage
    $0 -e stage -s vpc

    # Deploy AMI stack infrastructure only (no build)
    $0 -e prod -s ami

    # Check status of all stacks
    $0 -e dev -a status

    # Delete all stacks from dev (WARNING: Destructive)
    $0 -e dev -a delete

    # Update app stack in production
    $0 -e prod -s app -a update

NOTES:
    - VPC stack creates: VPC, subnets, IGW, VPC endpoints, security groups
    - AMI stack creates: S3 buckets, AMI build pipeline, IAM roles
    - App stack creates: ALB, ASG, Lambda, CloudWatch, Auto Scaling
    - AMI build takes 15-20 minutes
    - All stacks use CloudFormation exports for cross-stack references
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -e|--environment)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -r|--region)
            AWS_REGION="$2"
            shift 2
            ;;
        -a|--action)
            ACTION="$2"
            shift 2
            ;;
        -s|--stack)
            STACK="$2"
            shift 2
            ;;
        -b|--build-ami)
            BUILD_AMI=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            ;;
    esac
done

# Validate environment
if [[ ! "$ENVIRONMENT" =~ ^(dev|stage|prod)$ ]]; then
    error "Invalid environment: $ENVIRONMENT"
fi

# Validate action
if [[ ! "$ACTION" =~ ^(deploy|update|delete|status)$ ]]; then
    error "Invalid action: $ACTION"
fi

# Validate stack
if [[ ! "$STACK" =~ ^(vpc|ami|app|all)$ ]]; then
    error "Invalid stack: $STACK"
fi

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    error "AWS CLI is not installed"
fi

# Check AWS credentials
if ! aws sts get-caller-identity &> /dev/null; then
    error "AWS credentials not configured or invalid"
fi

PROJECT_NAME="hitl-cf"
VPC_STACK_NAME="${PROJECT_NAME}-${ENVIRONMENT}-vpc"
AMI_STACK_NAME="${PROJECT_NAME}-${ENVIRONMENT}-ami"
APP_STACK_NAME="${PROJECT_NAME}-${ENVIRONMENT}-app"

# Check if stack exists
stack_exists() {
    local stack_name=$1
    aws cloudformation describe-stacks --stack-name "$stack_name" --region "$AWS_REGION" &> /dev/null
}

# Wait for stack operation to complete
wait_for_stack() {
    local stack_name=$1
    local operation=$2
    
    info "Waiting for $stack_name to complete $operation operation..."
    
    case $operation in
        create|update)
            aws cloudformation wait stack-${operation}-complete --stack-name "$stack_name" --region "$AWS_REGION"
            ;;
        delete)
            aws cloudformation wait stack-delete-complete --stack-name "$stack_name" --region "$AWS_REGION"
            ;;
    esac
    
    if [ $? -eq 0 ]; then
        log "$stack_name $operation completed successfully"
    else
        error "$stack_name $operation failed"
    fi
}

# Deploy VPC stack
deploy_vpc_stack() {
    log "Deploying VPC stack..."
    
    TEMPLATE_FILE="$SCRIPT_DIR/vpc-stack/vpc-template.yaml"
    PARAMS_FILE="$SCRIPT_DIR/vpc-stack/parameters-${ENVIRONMENT}.json"
    
    if [ ! -f "$TEMPLATE_FILE" ]; then
        error "VPC template not found: $TEMPLATE_FILE"
    fi
    
    if [ ! -f "$PARAMS_FILE" ]; then
        error "VPC parameters file not found: $PARAMS_FILE"
    fi
    
    local operation="create"
    if stack_exists "$VPC_STACK_NAME"; then
        operation="update"
        info "VPC stack exists, performing update"
    fi
    
    aws cloudformation deploy \
        --template-file "$TEMPLATE_FILE" \
        --stack-name "$VPC_STACK_NAME" \
        --parameter-overrides file://"$PARAMS_FILE" \
        --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
        --region "$AWS_REGION" \
        --no-fail-on-empty-changeset
    
    log "VPC stack deployed successfully"
}

# Deploy AMI stack (legacy function name for compatibility)
deploy_ami_stack() {
    log "Deploying AMI stack..."
    
    # Check VPC stack dependency
    if ! stack_exists "$VPC_STACK_NAME"; then
        error "VPC stack ($VPC_STACK_NAME) must exist before deploying AMI stack"
    fi
    
    TEMPLATE_FILE="$SCRIPT_DIR/ami-stack/ami-template.yaml"
    PARAMS_FILE="$SCRIPT_DIR/ami-stack/parameters-${ENVIRONMENT}.json"
    
    if [ ! -f "$TEMPLATE_FILE" ]; then
        error "AMI template not found: $TEMPLATE_FILE"
    fi
    
    if [ ! -f "$PARAMS_FILE" ]; then
        error "AMI parameters file not found: $PARAMS_FILE"
    fi
    
    local operation="create"
    if stack_exists "$AMI_STACK_NAME"; then
        operation="update"
        info "AMI stack exists, performing update"
    fi
    
    aws cloudformation deploy \
        --template-file "$TEMPLATE_FILE" \
        --stack-name "$AMI_STACK_NAME" \
        --parameter-overrides file://"$PARAMS_FILE" \
        --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
        --region "$AWS_REGION" \
        --no-fail-on-empty-changeset
    
    log "AMI stack deployed successfully"
    
    # Upload scripts to S3 bucket for AMI build
    sync_scripts_to_s3
    
    # Get AMI Pipeline ARN
    PIPELINE_ARN=$(aws cloudformation describe-stacks \
        --stack-name "$AMI_STACK_NAME" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`AmiPipelineArn`].OutputValue' \
        --output text)
    
    info "AMI Pipeline ARN: $PIPELINE_ARN"
    warn "AMI build will be triggered automatically and takes 15-20 minutes"
    warn "Monitor progress: aws imagebuilder list-images --region $AWS_REGION"
}

# Get the latest AMI ID from Image Builder
get_latest_ami() {
    info "Getting latest AMI from Image Builder..." >&2
    
    local ami_id=$(aws ec2 describe-images \
        --owners self \
        --filters "Name=name,Values=${PROJECT_NAME}-${ENVIRONMENT}-nginx-*" \
        --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
        --output text \
        --region "$AWS_REGION" 2>/dev/null)
    
    if [ -z "$ami_id" ] || [ "$ami_id" == "None" ]; then
        return 1
    else
        echo "$ami_id"
        return 0
    fi
}

# Always trigger instance refresh on app stack updates
trigger_instance_refresh_on_app_update() {
    info "Triggering instance refresh to ensure all app stack changes are applied..."
    
    # Get ASG name from stack outputs
    local asg_name=$(aws cloudformation describe-stacks \
        --stack-name "$APP_STACK_NAME" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`AutoScalingGroupName`].OutputValue' \
        --output text 2>/dev/null)
    
    if [ -z "$asg_name" ] || [ "$asg_name" == "None" ]; then
        warn "Could not get ASG name from stack outputs, skipping instance refresh"
        return 0
    fi
    
    # Check if there's already an instance refresh in progress
    local active_refresh=$(aws autoscaling describe-instance-refreshes \
        --auto-scaling-group-name "$asg_name" \
        --region "$AWS_REGION" \
        --query 'InstanceRefreshes[?Status==`InProgress` || Status==`Pending`] | length(@)' \
        --output text 2>/dev/null)
    
    if [ "$active_refresh" != "0" ]; then
        info "Instance refresh already in progress for ASG: $asg_name"
        info "Monitor progress with: aws autoscaling describe-instance-refreshes --auto-scaling-group-name $asg_name --region $AWS_REGION"
        return 0
    fi
    
    # Trigger instance refresh (0% = replace all instances at once for quick deployment)
    info "Starting instance refresh for ASG: $asg_name"
    local refresh_id=$(aws autoscaling start-instance-refresh \
        --auto-scaling-group-name "$asg_name" \
        --region "$AWS_REGION" \
        --preferences '{"MinHealthyPercentage": 0, "InstanceWarmup": 60}' \
        --query 'InstanceRefreshId' \
        --output text 2>/dev/null)
    
    if [ $? -eq 0 ] && [ -n "$refresh_id" ] && [ "$refresh_id" != "None" ]; then
        log "✅ Instance refresh started with ID: $refresh_id"
        info "Reason: App stack update - ensuring latest Launch Template changes are applied"
        info "Monitor progress with: aws autoscaling describe-instance-refreshes --auto-scaling-group-name $asg_name --region $AWS_REGION"
        
        # Optionally wait for refresh to complete (commenting out as it can take a while)
        # info "Waiting for instance refresh to complete (this may take several minutes)..."
        # aws autoscaling wait instance-refresh-complete \
        #     --auto-scaling-group-name "$asg_name" \
        #     --instance-refresh-id "$refresh_id" \
        #     --region "$AWS_REGION"
        # log "Instance refresh completed successfully"
    else
        warn "Failed to start instance refresh, instances may need to be manually refreshed"
    fi
}

# Upload scripts to S3 bucket for AMI build
sync_scripts_to_s3() {
    info "Uploading AMI build scripts to S3..."
    
    # Get the S3 bucket name from the AMI stack output
    local bucket_name=$(aws cloudformation describe-stacks \
        --stack-name "$AMI_STACK_NAME" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`FrontendAssetsBucket`].OutputValue' \
        --output text 2>/dev/null)
    
    if [ -z "$bucket_name" ] || [ "$bucket_name" == "None" ]; then
        error "Could not get S3 bucket name from AMI stack"
    fi
    
    info "Syncing scripts to s3://$bucket_name/scripts/"
    
    # Sync scripts directory to S3
    aws s3 sync "$SCRIPT_DIR/../scripts/" "s3://$bucket_name/scripts/" \
        --region "$AWS_REGION" \
        --exclude "*" \
        --include "*.sh"
    
    if [ $? -eq 0 ]; then
        log "✅ Scripts uploaded successfully to S3"
    else
        error "Failed to upload scripts to S3"
    fi
}

# Wait for AMI build completion and return AMI ID
wait_for_ami_completion() {
    local pipeline_arn="$1"
    local max_wait_time=1800  # 30 minutes
    local wait_interval=60    # 1 minute
    local elapsed_time=0
    
    info "Starting AMI build and waiting for completion..." >&2
    info "Pipeline ARN: $pipeline_arn" >&2
    
    # Start pipeline execution
    local execution_response=$(aws imagebuilder start-image-pipeline-execution \
        --image-pipeline-arn "$pipeline_arn" \
        --region "$AWS_REGION" 2>/dev/null)
    
    if [ $? -ne 0 ]; then
        error "Failed to start AMI pipeline execution"
    fi
    
    local image_build_version_arn=$(echo "$execution_response" | jq -r '.imageBuildVersionArn')
    
    if [ "$image_build_version_arn" == "null" ] || [ -z "$image_build_version_arn" ]; then
        error "Failed to get image build version ARN from pipeline execution"
    fi
    
    info "Image build started: $image_build_version_arn" >&2
    info "This will take approximately 15-20 minutes..." >&2
    
    while [ $elapsed_time -lt $max_wait_time ]; do
        # Get image build status
        local image_response=$(aws imagebuilder get-image \
            --image-build-version-arn "$image_build_version_arn" \
            --region "$AWS_REGION" 2>/dev/null)
        
        if [ $? -eq 0 ]; then
            local status=$(echo "$image_response" | jq -r '.image.state.status')
            local reason=$(echo "$image_response" | jq -r '.image.state.reason // "No reason provided"')
            
            info "AMI build status: $status (elapsed: ${elapsed_time}s)" >&2
            
            case "$status" in
                "AVAILABLE")
                    local ami_id=$(echo "$image_response" | jq -r '.image.outputResources.amis[0].image')
                    if [ "$ami_id" != "null" ] && [ -n "$ami_id" ]; then
                        # Verify AMI exists in EC2
                        local ami_check=$(aws ec2 describe-images --image-ids "$ami_id" --region "$AWS_REGION" 2>/dev/null)
                        if [ $? -eq 0 ]; then
                            local ami_name=$(echo "$ami_check" | jq -r '.Images[0].Name // "Unknown"')
                            log "✅ Golden AMI built successfully!" >&2
                            log "AMI ID: $ami_id" >&2
                            log "AMI Name: $ami_name" >&2
                            echo "$ami_id"  # Return the AMI ID
                            return 0
                        else
                            error "AMI $ami_id was reported as available but not found in EC2"
                        fi
                    else
                        error "Image marked as available but no AMI ID found"
                    fi
                    ;;
                "BUILDING"|"TESTING"|"DISTRIBUTING")
                    # Still in progress
                    ;;
                "FAILED"|"CANCELLED"|"DEPRECATED")
                    error "AMI build failed with status: $status. Reason: $reason"
                    ;;
                *)
                    warn "Unknown AMI build status: $status" >&2
                    ;;
            esac
        else
            warn "Failed to get image build status (will retry)" >&2
        fi
        
        sleep $wait_interval
        elapsed_time=$((elapsed_time + wait_interval))
    done
    
    error "Timeout waiting for AMI build after $max_wait_time seconds"
}

# Build and upload frontend assets to S3
upload_frontend_assets() {
    info "Building and uploading frontend assets..."
    
    # Get the S3 bucket name from the AMI stack output
    local bucket_name=$(aws cloudformation describe-stacks \
        --stack-name "$AMI_STACK_NAME" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`FrontendAssetsBucket`].OutputValue' \
        --output text 2>/dev/null)
    
    if [ -z "$bucket_name" ] || [ "$bucket_name" == "None" ]; then
        error "Could not get S3 bucket name from AMI stack"
    fi
    
    # Check if demo-app directory exists
    local demo_app_dir="$SCRIPT_DIR/../demo-app"
    if [ ! -d "$demo_app_dir" ]; then
        warn "Demo app directory not found at $demo_app_dir, skipping frontend upload"
        return 0
    fi
    
    # Build the frontend app
    info "Building React frontend application..."
    cd "$demo_app_dir"
    
    # Install dependencies if needed
    if [ ! -d "node_modules" ]; then
        info "Installing npm dependencies..."
        npm install
    fi
    
    # Build the production bundle
    npm run build
    if [ $? -ne 0 ]; then
        error "Failed to build frontend application"
    fi
    
    # Upload to S3
    info "Uploading frontend to s3://$bucket_name/build/"
    aws s3 sync build/ "s3://$bucket_name/build/" \
        --region "$AWS_REGION" \
        --delete \
        --cache-control "public, max-age=31536000" \
        --exclude "index.html"
    
    # Upload index.html without cache
    aws s3 cp build/index.html "s3://$bucket_name/build/" \
        --region "$AWS_REGION" \
        --cache-control "no-cache, no-store, must-revalidate" \
        --content-type "text/html"
    
    cd "$SCRIPT_DIR"
    log "✅ Frontend assets uploaded successfully"
}

# Deploy Application stack
deploy_app_stack() {
    log "Deploying Application stack..."
    
    # Check dependencies
    if ! stack_exists "$VPC_STACK_NAME"; then
        error "VPC stack ($VPC_STACK_NAME) must exist before deploying Application stack"
    fi
    
    if ! stack_exists "$AMI_STACK_NAME"; then
        error "AMI stack ($AMI_STACK_NAME) must exist before deploying Application stack"
    fi
    
    TEMPLATE_FILE="$SCRIPT_DIR/app-stack/app-template.yaml"
    PARAMS_FILE="$SCRIPT_DIR/app-stack/parameters-${ENVIRONMENT}.json"
    
    if [ ! -f "$TEMPLATE_FILE" ]; then
        error "App template not found: $TEMPLATE_FILE"
    fi
    
    if [ ! -f "$PARAMS_FILE" ]; then
        error "App parameters file not found: $PARAMS_FILE"
    fi
    
    local operation="create"
    if stack_exists "$APP_STACK_NAME"; then
        operation="update"
        info "Application stack exists, performing update"
    fi
    
    # Build parameter overrides
    local params=""
    if [ -f "$PARAMS_FILE" ]; then
        # Read parameters from JSON file and convert to Key=Value format
        if [ -n "$GOLDEN_AMI_ID" ]; then
            # Exclude CustomAmiId from JSON params since we'll add it explicitly
            params=$(jq -r '.[] | select(.ParameterKey != "CustomAmiId") | "\(.ParameterKey)=\(.ParameterValue)"' "$PARAMS_FILE" | tr '\n' ' ')
        else
            params=$(jq -r '.[] | "\(.ParameterKey)=\(.ParameterValue)"' "$PARAMS_FILE" | tr '\n' ' ')
        fi
    fi
    
    # Add AMI ID if available
    if [ -n "$GOLDEN_AMI_ID" ]; then
        info "Using golden AMI ID: $GOLDEN_AMI_ID"
        params="$params CustomAmiId=$GOLDEN_AMI_ID"
    fi
    
    # Deploy the stack
    aws cloudformation deploy \
        --template-file "$TEMPLATE_FILE" \
        --stack-name "$APP_STACK_NAME" \
        --parameter-overrides $params \
        --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
        --region "$AWS_REGION" \
        --no-fail-on-empty-changeset
    
    log "Application stack deployed successfully"
    
    # Always trigger instance refresh on app stack updates to ensure latest changes are applied
    trigger_instance_refresh_on_app_update
    
    # Upload frontend assets to S3
    upload_frontend_assets
    
    # Get outputs
    ALB_DNS=$(aws cloudformation describe-stacks \
        --stack-name "$APP_STACK_NAME" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDNSName`].OutputValue' \
        --output text)
    
    S3_BUCKET=$(aws cloudformation describe-stacks \
        --stack-name "$APP_STACK_NAME" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
        --output text)
    
    # Get domain name from parameters
    DOMAIN_NAME=$(jq -r '.[] | select(.ParameterKey=="DomainName") | .ParameterValue' "$PARAMS_FILE")
    
    echo ""
    echo "======================================"
    echo "HITL Platform Deployed Successfully!"
    echo "======================================"
    echo "Application URL: https://$DOMAIN_NAME"
    echo "ALB DNS Name:    $ALB_DNS"
    echo "S3 Bucket:       $S3_BUCKET"
    echo "Environment:     $ENVIRONMENT"
    echo "Region:          $AWS_REGION"
    echo "======================================"
    echo ""
    echo "📝 Note: Configure DNS to point $DOMAIN_NAME to $ALB_DNS"
    echo ""
    echo "Next Steps:"
    echo "1. Frontend assets automatically uploaded to S3"
    echo ""
    echo "2. Files will auto-sync to EC2 instances within 2 minutes"
    echo ""
    echo "3. Monitor deployment:"
    echo "   curl $APPLICATION_URL/health"
    echo "   curl $APPLICATION_URL/health-detailed"
    echo ""
    echo "4. View S3 sync status in the React app at $APPLICATION_URL"
    echo "======================================"
}

# Delete a stack
delete_stack() {
    local stack_name=$1
    log "Deleting stack: $stack_name"
    
    if ! stack_exists "$stack_name"; then
        warn "Stack $stack_name does not exist, skipping deletion"
        return 0
    fi
    
    aws cloudformation delete-stack \
        --stack-name "$stack_name" \
        --region "$AWS_REGION"
    
    wait_for_stack "$stack_name" "delete"
}

# Show stack status
show_stack_status() {
    local stack_name=$1
    local stack_type=$2
    
    if stack_exists "$stack_name"; then
        local status=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --region "$AWS_REGION" \
            --query 'Stacks[0].StackStatus' \
            --output text)
        
        local created=$(aws cloudformation describe-stacks \
            --stack-name "$stack_name" \
            --region "$AWS_REGION" \
            --query 'Stacks[0].CreationTime' \
            --output text)
        
        log "$stack_type Stack: $stack_name - Status: $status - Created: $created"
    else
        warn "$stack_type Stack: $stack_name - Status: NOT FOUND"
    fi
}

# Main execution
log "Starting HITL Platform CloudFormation deployment"
log "Environment: $ENVIRONMENT"
log "Region: $AWS_REGION"
log "Action: $ACTION"
log "Stack: $STACK"
echo ""

case $ACTION in
    status)
        log "Checking stack status..."
        if [ "$STACK" == "vpc" ] || [ "$STACK" == "all" ]; then
            show_stack_status "$VPC_STACK_NAME" "VPC"
        fi
        
        if [ "$STACK" == "ami" ] || [ "$STACK" == "all" ]; then
            show_stack_status "$AMI_STACK_NAME" "AMI"
        fi
        
        if [ "$STACK" == "app" ] || [ "$STACK" == "all" ]; then
            show_stack_status "$APP_STACK_NAME" "Application"
        fi
        ;;
        
    deploy|update)
        info "Deploying in correct order: VPC → AMI → Application"
        echo ""
        
        if [ "$STACK" == "vpc" ] || [ "$STACK" == "all" ]; then
            deploy_vpc_stack
            echo ""
        fi
        
        # Step 1: Deploy AMI stack infrastructure
        if [ "$STACK" == "ami" ] || [ "$STACK" == "all" ]; then
            deploy_ami_stack
            echo ""
        fi
        
        # Step 2: Trigger AMI build if --build-ami flag is set
        if [ "$BUILD_AMI" == true ] && ([ "$STACK" == "ami" ] || [ "$STACK" == "all" ]); then
            info "Building new AMI as requested (--build-ami flag set)"
            
            # Get the pipeline ARN from the ami stack
            pipeline_arn=$(aws cloudformation describe-stacks \
                --stack-name "$AMI_STACK_NAME" \
                --region "$AWS_REGION" \
                --query 'Stacks[0].Outputs[?OutputKey==`AmiPipelineArn`].OutputValue' \
                --output text 2>/dev/null)
            
            if [ -n "$pipeline_arn" ] && [ "$pipeline_arn" != "None" ]; then
                # Trigger AMI build and wait for completion
                if ! GOLDEN_AMI_ID=$(wait_for_ami_completion "$pipeline_arn"); then
                    error "Failed to build golden AMI"
                fi
                info "AMI build completed successfully"
                info "Golden AMI ID: $GOLDEN_AMI_ID"
            else
                error "Could not get AMI pipeline ARN from stack"
            fi
            echo ""
        fi
        
        # Step 3: Get latest AMI ID if deploying app (whether just built or existing)
        if [ "$STACK" == "app" ] || [ "$STACK" == "all" ]; then
            if [ -z "$GOLDEN_AMI_ID" ]; then
                info "Getting latest AMI for deployment..."
                GOLDEN_AMI_ID=$(get_latest_ami)
                if [ $? -ne 0 ] || [ -z "$GOLDEN_AMI_ID" ]; then
                    error "No AMI found. Build an AMI first with: ./deploy.sh -e $ENVIRONMENT --build-ami"
                fi
            fi
            info "Using AMI: $GOLDEN_AMI_ID"
            echo ""
        fi
        
        # Step 4: Deploy app stack using the retrieved AMI ID
        if [ "$STACK" == "app" ] || [ "$STACK" == "all" ]; then
            deploy_app_stack
        fi
        ;;
        
    delete)
        warn "WARNING: This will delete infrastructure and may result in data loss!"
        read -p "Are you sure you want to delete stacks for environment '$ENVIRONMENT'? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "Deletion cancelled"
            exit 0
        fi
        
        info "S3 buckets will be emptied automatically by Lambda cleanup functions"
        info "Deleting in reverse order: Application → AMI → VPC"
        echo ""
        
        if [ "$STACK" == "app" ] || [ "$STACK" == "all" ]; then
            delete_stack "$APP_STACK_NAME"
            echo ""
        fi
        
        if [ "$STACK" == "ami" ] || [ "$STACK" == "all" ]; then
            delete_stack "$AMI_STACK_NAME"
            echo ""
        fi
        
        if [ "$STACK" == "vpc" ] || [ "$STACK" == "all" ]; then
            # Only delete VPC if app and ami stacks are also being deleted or don't exist
            if [ "$STACK" == "all" ] || \
               ([ "$STACK" == "vpc" ] && ! stack_exists "$APP_STACK_NAME" && ! stack_exists "$AMI_STACK_NAME"); then
                delete_stack "$VPC_STACK_NAME"
            else
                warn "VPC stack not deleted because dependent stacks still exist"
                warn "Delete app and ami stacks first, or use '--stack all'"
            fi
        fi
        ;;
esac

echo ""
log "CloudFormation operation completed successfully!"

# Show helpful information
if [ "$ACTION" == "deploy" ] || [ "$ACTION" == "update" ]; then
    echo ""
    info "Stack Dependencies:"
    info "• VPC Stack provides network foundation"
    info "• AMI Stack provides golden AMI and S3 buckets"
    info "• App Stack provides ALB, ASG, Lambda, and application components"
    echo ""
    info "Equivalent to Terraform:"
    info "• terraform/vpc/        → cloudformation/vpc-stack/"
    info "• terraform/ami/ → cloudformation/ami-stack/"
    info "• terraform/app/        → cloudformation/app-stack/"
    echo ""
    info "For more details, see README.md"
fi