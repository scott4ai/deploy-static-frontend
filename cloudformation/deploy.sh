#!/bin/bash

# HITL Platform - CloudFormation Deployment Script
# Equivalent to the three Terraform stacks: VPC, Image Builder, and App

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
ENVIRONMENT="dev"
AWS_REGION="us-east-1"
ACTION="deploy"
STACK="all"

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
    -s, --stack        Stack to deploy (vpc, image-builder, app, all) [default: all]
    -h, --help         Show this help message

DEPLOYMENT ORDER:
    The stacks must be deployed in this specific order:
    1. VPC Stack          - Network foundation
    2. Image Builder      - Creates golden AMI (15-20 min build time)
    3. Application Stack  - Uses VPC and AMI from previous stacks

EXAMPLES:
    # Deploy all stacks to dev (recommended)
    $0 -e dev

    # Deploy only VPC stack to stage
    $0 -e stage -s vpc

    # Deploy Image Builder stack to prod
    $0 -e prod -s image-builder

    # Check status of all stacks
    $0 -e dev -a status

    # Delete all stacks from dev (WARNING: Destructive)
    $0 -e dev -a delete

    # Update app stack in production
    $0 -e prod -s app -a update

NOTES:
    - VPC stack creates: VPC, subnets, IGW, VPC endpoints, security groups
    - Image Builder stack creates: S3 buckets, AMI build pipeline, IAM roles
    - App stack creates: ALB, ASG, Lambda, CloudWatch, Auto Scaling
    - Image Builder AMI build takes 15-20 minutes
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
if [[ ! "$STACK" =~ ^(vpc|image-builder|app|all)$ ]]; then
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

PROJECT_NAME="hitl"
VPC_STACK_NAME="${PROJECT_NAME}-${ENVIRONMENT}-vpc"
IMAGE_BUILDER_STACK_NAME="${PROJECT_NAME}-${ENVIRONMENT}-image-builder"
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

# Deploy Image Builder stack
deploy_image_builder_stack() {
    log "Deploying Image Builder stack..."
    
    # Check VPC stack dependency
    if ! stack_exists "$VPC_STACK_NAME"; then
        error "VPC stack ($VPC_STACK_NAME) must exist before deploying Image Builder stack"
    fi
    
    TEMPLATE_FILE="$SCRIPT_DIR/image-builder-stack/image-builder-template.yaml"
    PARAMS_FILE="$SCRIPT_DIR/image-builder-stack/parameters-${ENVIRONMENT}.json"
    
    if [ ! -f "$TEMPLATE_FILE" ]; then
        error "Image Builder template not found: $TEMPLATE_FILE"
    fi
    
    if [ ! -f "$PARAMS_FILE" ]; then
        error "Image Builder parameters file not found: $PARAMS_FILE"
    fi
    
    local operation="create"
    if stack_exists "$IMAGE_BUILDER_STACK_NAME"; then
        operation="update"
        info "Image Builder stack exists, performing update"
    fi
    
    aws cloudformation deploy \
        --template-file "$TEMPLATE_FILE" \
        --stack-name "$IMAGE_BUILDER_STACK_NAME" \
        --parameter-overrides file://"$PARAMS_FILE" \
        --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
        --region "$AWS_REGION" \
        --no-fail-on-empty-changeset
    
    log "Image Builder stack deployed successfully"
    
    # Get Image Builder Pipeline ARN
    PIPELINE_ARN=$(aws cloudformation describe-stacks \
        --stack-name "$IMAGE_BUILDER_STACK_NAME" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`ImageBuilderPipelineArn`].OutputValue' \
        --output text)
    
    info "Image Builder Pipeline ARN: $PIPELINE_ARN"
    warn "AMI build will be triggered automatically and takes 15-20 minutes"
    warn "Monitor progress: aws imagebuilder list-images --region $AWS_REGION"
}

# Deploy Application stack
deploy_app_stack() {
    log "Deploying Application stack..."
    
    # Check dependencies
    if ! stack_exists "$VPC_STACK_NAME"; then
        error "VPC stack ($VPC_STACK_NAME) must exist before deploying Application stack"
    fi
    
    if ! stack_exists "$IMAGE_BUILDER_STACK_NAME"; then
        error "Image Builder stack ($IMAGE_BUILDER_STACK_NAME) must exist before deploying Application stack"
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
    
    aws cloudformation deploy \
        --template-file "$TEMPLATE_FILE" \
        --stack-name "$APP_STACK_NAME" \
        --parameter-overrides file://"$PARAMS_FILE" \
        --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
        --region "$AWS_REGION" \
        --no-fail-on-empty-changeset
    
    log "Application stack deployed successfully"
    
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
    
    APPLICATION_URL=$(aws cloudformation describe-stacks \
        --stack-name "$APP_STACK_NAME" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`ApplicationURL`].OutputValue' \
        --output text)
    
    echo ""
    echo "======================================"
    echo "HITL Platform Deployed Successfully!"
    echo "======================================"
    echo "Application URL: $APPLICATION_URL"
    echo "ALB DNS Name:    $ALB_DNS"
    echo "S3 Bucket:       $S3_BUCKET"
    echo "Environment:     $ENVIRONMENT"
    echo "Region:          $AWS_REGION"
    echo "======================================"
    echo ""
    echo "Next Steps:"
    echo "1. Upload your React app build files to S3:"
    echo "   aws s3 sync ./demo-app/build/ s3://$S3_BUCKET/"
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
        
        if [ "$STACK" == "image-builder" ] || [ "$STACK" == "all" ]; then
            show_stack_status "$IMAGE_BUILDER_STACK_NAME" "Image Builder"
        fi
        
        if [ "$STACK" == "app" ] || [ "$STACK" == "all" ]; then
            show_stack_status "$APP_STACK_NAME" "Application"
        fi
        ;;
        
    deploy|update)
        info "Deploying in correct order: VPC → Image Builder → Application"
        echo ""
        
        if [ "$STACK" == "vpc" ] || [ "$STACK" == "all" ]; then
            deploy_vpc_stack
            echo ""
        fi
        
        if [ "$STACK" == "image-builder" ] || [ "$STACK" == "all" ]; then
            deploy_image_builder_stack
            echo ""
        fi
        
        if [ "$STACK" == "app" ] || [ "$STACK" == "all" ]; then
            # Wait a moment to ensure Image Builder stack is fully ready
            if [ "$STACK" == "all" ]; then
                info "Waiting 30 seconds for Image Builder stack to stabilize..."
                sleep 30
            fi
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
        
        info "Deleting in reverse order: Application → Image Builder → VPC"
        echo ""
        
        if [ "$STACK" == "app" ] || [ "$STACK" == "all" ]; then
            delete_stack "$APP_STACK_NAME"
            echo ""
        fi
        
        if [ "$STACK" == "image-builder" ] || [ "$STACK" == "all" ]; then
            delete_stack "$IMAGE_BUILDER_STACK_NAME"
            echo ""
        fi
        
        if [ "$STACK" == "vpc" ] || [ "$STACK" == "all" ]; then
            # Only delete VPC if app and image-builder stacks are also being deleted or don't exist
            if [ "$STACK" == "all" ] || \
               ([ "$STACK" == "vpc" ] && ! stack_exists "$APP_STACK_NAME" && ! stack_exists "$IMAGE_BUILDER_STACK_NAME"); then
                delete_stack "$VPC_STACK_NAME"
            else
                warn "VPC stack not deleted because dependent stacks still exist"
                warn "Delete app and image-builder stacks first, or use '--stack all'"
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
    info "• Image Builder Stack provides golden AMI and S3 buckets"
    info "• App Stack provides ALB, ASG, Lambda, and application components"
    echo ""
    info "Equivalent to Terraform:"
    info "• terraform/vpc/        → cloudformation/vpc-stack/"
    info "• terraform/image-builder/ → cloudformation/image-builder-stack/"
    info "• terraform/app/        → cloudformation/app-stack/"
    echo ""
    info "For more details, see README.md"
fi