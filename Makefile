# HITL Platform - Build Orchestration Makefile
# Automates the complete build and deployment pipeline

# Configuration
PROJECT_NAME := hitl
AWS_REGION ?= us-east-1
ENVIRONMENT ?= dev
BUILD_VERSION := $(shell date +%Y%m%d-%H%M%S)

# Colors for output
GREEN := \033[0;32m
YELLOW := \033[1;33m
RED := \033[0;31m
NC := \033[0m

# Directories
AMI_BUILDER_DIR := ami-builder
DEMO_APP_DIR := demo-app
LAMBDA_BACKEND_DIR := lambda-backend
TERRAFORM_VPC_DIR := terraform/vpc
TERRAFORM_APP_DIR := terraform/app
CLOUDFORMATION_DIR := cloudformation

.PHONY: help build build-ami build-frontend build-lambda deploy-vpc deploy-app clean status check-deps

# Default target
help: ## Show this help message
	@echo "$(GREEN)HITL Platform Build Pipeline$(NC)"
	@echo ""
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  $(YELLOW)%-20s$(NC) %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo ""
	@echo "Environment variables:"
	@echo "  $(YELLOW)AWS_REGION$(NC)    AWS region (default: us-east-1)"
	@echo "  $(YELLOW)ENVIRONMENT$(NC)   Environment name (default: dev)"
	@echo ""

check-deps: ## Check for required dependencies
	@echo "$(GREEN)Checking dependencies...$(NC)"
	@command -v aws >/dev/null 2>&1 || { echo "$(RED)Error: AWS CLI not installed$(NC)"; exit 1; }
	@command -v terraform >/dev/null 2>&1 || { echo "$(RED)Error: Terraform not installed$(NC)"; exit 1; }
	@command -v node >/dev/null 2>&1 || { echo "$(RED)Error: Node.js not installed$(NC)"; exit 1; }
	@aws sts get-caller-identity >/dev/null 2>&1 || { echo "$(RED)Error: AWS credentials not configured$(NC)"; exit 1; }
	@echo "$(GREEN)All dependencies satisfied! (Using EC2 Image Builder instead of Packer)$(NC)"

build: check-deps build-lambda build-frontend ## Build application components (lambda, frontend)
	@echo "$(GREEN)Application build completed successfully!$(NC)"

deploy-ami-pipeline: deploy-vpc ## Deploy EC2 Image Builder pipeline infrastructure (requires VPC)
	@echo "$(GREEN)Setting up Image Builder pipeline...$(NC)"
	@cd terraform/ami && \
		terraform init && \
		VPC_ID=$$(cd ../vpc && terraform output -raw vpc_id) && \
		SUBNET_ID=$$(cd ../vpc && terraform output -json public_subnet_ids | jq -r '.[0]') && \
		terraform apply -var="vpc_id=$$VPC_ID" -var="public_subnet_id=$$SUBNET_ID" -var="aws_region=$(AWS_REGION)" -var="environment=$(ENVIRONMENT)" -var="project_name=$(PROJECT_NAME)" -auto-approve
	@echo "$(GREEN)Image Builder pipeline deployed! Use 'make build-ami' to start AMI creation.$(NC)"

build-ami: ## Trigger Image Builder pipeline to create AMI
	@echo "$(GREEN)Triggering AMI build...$(NC)"
	@PIPELINE_ARN=$$(cd terraform/ami && terraform output -raw image_pipeline_arn) && \
		aws imagebuilder start-image-pipeline-execution --image-pipeline-arn "$$PIPELINE_ARN" --region $(AWS_REGION)
	@echo "$(GREEN)AMI build triggered! Check AWS Console > EC2 Image Builder for progress.$(NC)"

get-latest-ami: ## Get the latest AMI ID built by Image Builder
	@echo "$(GREEN)Getting latest AMI ID...$(NC)"
	@aws ec2 describe-images --owners self \
		--filters "Name=name,Values=$(PROJECT_NAME)-$(ENVIRONMENT)-nginx-*" \
		--query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
		--output text --region $(AWS_REGION)

build-frontend: ## Build React frontend application
	@echo "$(GREEN)Building frontend application...$(NC)"
	@cd $(DEMO_APP_DIR) && \
		npm install && \
		npm run build
	@echo "$(GREEN)Frontend build completed!$(NC)"

build-lambda: ## Build Lambda backend function
	@echo "$(GREEN)Building Lambda backend...$(NC)"
	@cd $(LAMBDA_BACKEND_DIR) && \
		./build.sh
	@echo "$(GREEN)Lambda build completed!$(NC)"

# Infrastructure deployment targets
deploy-vpc: check-deps ## Deploy VPC infrastructure with Terraform
	@echo "$(GREEN)Deploying VPC infrastructure...$(NC)"
	@cd $(TERRAFORM_VPC_DIR) && \
		terraform init && \
		terraform plan -var-file="../../environments/vpc-$(ENVIRONMENT).tfvars" && \
		terraform apply -var-file="../../environments/vpc-$(ENVIRONMENT).tfvars" -auto-approve
	@echo "$(GREEN)VPC deployment completed!$(NC)"

deploy-app: build ## Build and deploy application infrastructure
	@echo "$(GREEN)Deploying application infrastructure...$(NC)"
	@$(MAKE) update-ami-id
	@cd $(TERRAFORM_APP_DIR) && \
		terraform init && \
		terraform plan -var-file="../../environments/$(ENVIRONMENT).tfvars" && \
		terraform apply -var-file="../../environments/$(ENVIRONMENT).tfvars" -auto-approve
	@echo "$(GREEN)Application deployment completed!$(NC)"

update-ami-id: ## Update Terraform variables with latest AMI ID
	@echo "$(GREEN)Updating AMI ID in Terraform configuration...$(NC)"
	@if [ -f "$(AMI_BUILDER_DIR)/latest-ami-id.txt" ]; then \
		AMI_ID=$$(cat $(AMI_BUILDER_DIR)/latest-ami-id.txt); \
		echo "Latest AMI ID: $$AMI_ID"; \
		if [ -f "environments/$(ENVIRONMENT).tfvars" ]; then \
			sed -i.bak "s/custom_ami_id = .*/custom_ami_id = \"$$AMI_ID\"/" environments/$(ENVIRONMENT).tfvars; \
			echo "$(GREEN)Updated AMI ID in environments/$(ENVIRONMENT).tfvars$(NC)"; \
		else \
			echo "custom_ami_id = \"$$AMI_ID\"" >> environments/$(ENVIRONMENT).tfvars; \
			echo "$(GREEN)Added AMI ID to environments/$(ENVIRONMENT).tfvars$(NC)"; \
		fi; \
	else \
		echo "$(YELLOW)Warning: No AMI ID file found. Run 'make build-ami' first.$(NC)"; \
	fi

# CloudFormation deployment alternatives
deploy-vpc-cf: check-deps ## Deploy VPC with CloudFormation
	@echo "$(GREEN)Deploying VPC with CloudFormation...$(NC)"
	@cd $(CLOUDFORMATION_DIR) && \
		./deploy.sh vpc $(ENVIRONMENT)
	@echo "$(GREEN)VPC CloudFormation deployment completed!$(NC)"

deploy-app-cf: build ## Build and deploy application with CloudFormation
	@echo "$(GREEN)Deploying application with CloudFormation...$(NC)"
	@$(MAKE) update-ami-id-cf
	@cd $(CLOUDFORMATION_DIR) && \
		./deploy.sh app $(ENVIRONMENT)
	@echo "$(GREEN)Application CloudFormation deployment completed!$(NC)"

update-ami-id-cf: ## Update CloudFormation parameters with latest AMI ID
	@echo "$(GREEN)Updating AMI ID in CloudFormation parameters...$(NC)"
	@if [ -f "$(AMI_BUILDER_DIR)/latest-ami-id.txt" ]; then \
		AMI_ID=$$(cat $(AMI_BUILDER_DIR)/latest-ami-id.txt); \
		echo "Latest AMI ID: $$AMI_ID"; \
		PARAM_FILE="$(CLOUDFORMATION_DIR)/app-stack/parameters-$(ENVIRONMENT).json"; \
		if [ -f "$$PARAM_FILE" ]; then \
			jq --arg ami "$$AMI_ID" '(.[] | select(.ParameterKey=="CustomAmiId") | .ParameterValue) = $$ami' "$$PARAM_FILE" > "$$PARAM_FILE.tmp" && mv "$$PARAM_FILE.tmp" "$$PARAM_FILE"; \
			echo "$(GREEN)Updated AMI ID in $$PARAM_FILE$(NC)"; \
		else \
			echo "$(YELLOW)Warning: Parameter file $$PARAM_FILE not found$(NC)"; \
		fi; \
	else \
		echo "$(YELLOW)Warning: No AMI ID file found. Run 'make build-ami' first.$(NC)"; \
	fi

# Upload frontend assets to S3
upload-frontend: build-frontend ## Upload frontend build to S3
	@echo "$(GREEN)Uploading frontend to S3...$(NC)"
	@if [ -z "$$S3_BUCKET" ]; then \
		echo "$(RED)Error: S3_BUCKET environment variable not set$(NC)"; \
		exit 1; \
	fi
	@cd $(DEMO_APP_DIR) && \
		aws s3 sync build/ s3://$$S3_BUCKET/ --delete --region $(AWS_REGION)
	@echo "$(GREEN)Frontend upload completed!$(NC)"

# Status and information
status: ## Show deployment status and information
	@echo "$(GREEN)HITL Platform Status$(NC)"
	@echo "===================="
	@echo "Build Version: $(BUILD_VERSION)"
	@echo "AWS Region: $(AWS_REGION)"
	@echo "Environment: $(ENVIRONMENT)"
	@echo ""
	@echo "$(YELLOW)Latest AMI:$(NC)"
	@if [ -f "$(AMI_BUILDER_DIR)/latest-ami-id.txt" ]; then \
		echo "  AMI ID: $$(cat $(AMI_BUILDER_DIR)/latest-ami-id.txt)"; \
	else \
		echo "  No AMI built yet"; \
	fi
	@echo ""
	@echo "$(YELLOW)Terraform State:$(NC)"
	@if [ -f "$(TERRAFORM_VPC_DIR)/terraform.tfstate" ]; then \
		echo "  VPC: Deployed"; \
	else \
		echo "  VPC: Not deployed"; \
	fi
	@if [ -f "$(TERRAFORM_APP_DIR)/terraform.tfstate" ]; then \
		echo "  App: Deployed"; \
	else \
		echo "  App: Not deployed"; \
	fi

# Cleanup targets
clean: clean-builds clean-terraform ## Clean all build artifacts
	@echo "$(GREEN)Cleanup completed!$(NC)"

clean-builds: ## Clean build artifacts
	@echo "$(GREEN)Cleaning build artifacts...$(NC)"
	@rm -rf $(DEMO_APP_DIR)/build
	@rm -rf $(DEMO_APP_DIR)/node_modules
	@rm -rf $(LAMBDA_BACKEND_DIR)/node_modules
	@rm -f $(LAMBDA_BACKEND_DIR)/deployment.zip
	@rm -f $(AMI_BUILDER_DIR)/latest-ami-id.txt

clean-terraform: ## Clean Terraform state and cache
	@echo "$(GREEN)Cleaning Terraform artifacts...$(NC)"
	@rm -rf $(TERRAFORM_VPC_DIR)/.terraform
	@rm -rf $(TERRAFORM_APP_DIR)/.terraform
	@rm -f $(TERRAFORM_VPC_DIR)/.terraform.lock.hcl
	@rm -f $(TERRAFORM_APP_DIR)/.terraform.lock.hcl

# Development helpers
dev-setup: ## Initial development environment setup
	@echo "$(GREEN)Setting up development environment...$(NC)"
	@cd $(DEMO_APP_DIR) && npm install
	@cd $(LAMBDA_BACKEND_DIR) && npm install
	@echo "$(GREEN)Development setup completed!$(NC)"

validate: ## Validate all configurations
	@echo "$(GREEN)Validating configurations...$(NC)"
	@cd $(AMI_BUILDER_DIR) && packer validate packer-template.pkr.hcl
	@cd $(TERRAFORM_VPC_DIR) && terraform init -backend=false && terraform validate
	@cd $(TERRAFORM_APP_DIR) && terraform init -backend=false && terraform validate
	@cd $(CLOUDFORMATION_DIR)/vpc-stack && aws cloudformation validate-template --template-body file://vpc-template.yaml >/dev/null
	@cd $(CLOUDFORMATION_DIR)/app-stack && aws cloudformation validate-template --template-body file://app-template.yaml >/dev/null
	@echo "$(GREEN)All configurations are valid!$(NC)"

# Complete pipeline targets
pipeline-terraform: ## Run complete Terraform pipeline (build -> deploy VPC -> deploy pipeline -> build AMI -> deploy app)
	@echo "$(GREEN)Running complete Terraform pipeline...$(NC)"
	@$(MAKE) build
	@$(MAKE) deploy-vpc
	@$(MAKE) deploy-ami-pipeline
	@$(MAKE) build-ami
	@$(MAKE) deploy-app
	@$(MAKE) status
	@echo "$(GREEN)Pipeline completed successfully!$(NC)"

pipeline-cloudformation: ## Run complete CloudFormation pipeline (build -> deploy VPC -> deploy app)
	@echo "$(GREEN)Running complete CloudFormation pipeline...$(NC)"
	@$(MAKE) build
	@$(MAKE) deploy-vpc-cf
	@$(MAKE) deploy-app-cf
	@$(MAKE) status
	@echo "$(GREEN)Pipeline completed successfully!$(NC)"