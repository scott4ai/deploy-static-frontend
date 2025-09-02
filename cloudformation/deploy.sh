#!/bin/bash

# HITL - CloudFormation Deployment Script

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
ENVIRONMENT="dev"
AWS_REGION="us-east-1"
ACTION="deploy"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Deploy HITL CloudFormation stacks

OPTIONS:
    -e, --environment  Environment (dev, stage, prod) [default: dev]
    -r, --region       AWS region [default: us-east-1]
    -a, --action       Action (deploy, update, delete) [default: deploy]
    -s, --stack        Stack to deploy (vpc, app, both) [default: both]
    -h, --help         Show this help message

EXAMPLES:
    # Deploy both stacks to dev
    $0 -e dev

    # Deploy only VPC stack to stage
    $0 -e stage -s vpc

    # Delete stacks from dev
    $0 -e dev -a delete

    # Update app stack in production
    $0 -e prod -s app -a update
EOF
}

# Parse command line arguments
STACK="both"
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
if [[ ! "$ACTION" =~ ^(deploy|update|delete)$ ]]; then
    error "Invalid action: $ACTION"
fi

# Validate stack
if [[ ! "$STACK" =~ ^(vpc|app|both)$ ]]; then
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
APP_STACK_NAME="${PROJECT_NAME}-${ENVIRONMENT}-app"

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
    
    aws cloudformation deploy \
        --template-file "$TEMPLATE_FILE" \
        --stack-name "$VPC_STACK_NAME" \
        --parameter-overrides file://"$PARAMS_FILE" \
        --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
        --region "$AWS_REGION" \
        --no-fail-on-empty-changeset
    
    log "VPC stack deployed successfully"
}

deploy_app_stack() {
    log "Deploying application stack..."
    
    TEMPLATE_FILE="$SCRIPT_DIR/app-stack/app-template.yaml"
    PARAMS_FILE="$SCRIPT_DIR/app-stack/parameters-${ENVIRONMENT}.json"
    
    if [ ! -f "$TEMPLATE_FILE" ]; then
        error "App template not found: $TEMPLATE_FILE"
    fi
    
    if [ ! -f "$PARAMS_FILE" ]; then
        error "App parameters file not found: $PARAMS_FILE"
    fi
    
    # Check if VPC stack exists
    if ! aws cloudformation describe-stacks \
        --stack-name "$VPC_STACK_NAME" \
        --region "$AWS_REGION" &> /dev/null; then
        error "VPC stack does not exist. Deploy VPC stack first."
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
        --query 'Stacks[0].Outputs[?OutputKey==`ALBDNSName`].OutputValue' \
        --output text)
    
    S3_BUCKET=$(aws cloudformation describe-stacks \
        --stack-name "$APP_STACK_NAME" \
        --region "$AWS_REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`S3BucketName`].OutputValue' \
        --output text)
    
    echo ""
    echo "======================================"
    echo "Application Stack Deployed!"
    echo "======================================"
    echo "ALB URL: http://$ALB_DNS"
    echo "S3 Bucket: $S3_BUCKET"
    echo "Environment: $ENVIRONMENT"
    echo "Region: $AWS_REGION"
    echo "======================================"
}

delete_stack() {
    local stack_name=$1
    log "Deleting stack: $stack_name"
    
    aws cloudformation delete-stack \
        --stack-name "$stack_name" \
        --region "$AWS_REGION"
    
    log "Waiting for stack deletion to complete..."
    aws cloudformation wait stack-delete-complete \
        --stack-name "$stack_name" \
        --region "$AWS_REGION"
    
    log "Stack deleted: $stack_name"
}

# Main execution
log "Starting CloudFormation deployment"
log "Environment: $ENVIRONMENT"
log "Region: $AWS_REGION"
log "Action: $ACTION"
log "Stack: $STACK"

case $ACTION in
    deploy|update)
        if [ "$STACK" == "vpc" ] || [ "$STACK" == "both" ]; then
            deploy_vpc_stack
        fi
        
        if [ "$STACK" == "app" ] || [ "$STACK" == "both" ]; then
            deploy_app_stack
        fi
        ;;
        
    delete)
        if [ "$STACK" == "app" ] || [ "$STACK" == "both" ]; then
            delete_stack "$APP_STACK_NAME"
        fi
        
        if [ "$STACK" == "vpc" ] || [ "$STACK" == "both" ]; then
            # Only delete VPC if app stack is also being deleted or doesn't exist
            if [ "$STACK" == "both" ] || ! aws cloudformation describe-stacks \
                --stack-name "$APP_STACK_NAME" \
                --region "$AWS_REGION" &> /dev/null; then
                delete_stack "$VPC_STACK_NAME"
            else
                warn "VPC stack not deleted because app stack still exists"
            fi
        fi
        ;;
esac

log "CloudFormation deployment completed successfully!"