# HITL Lambda Backend

Backend API Lambda function for the HITL infrastructure demonstration.

## Overview

This Lambda function provides a single endpoint handler that simulates microservice APIs for the HITL demo. It includes proper CORS headers for ALB integration and demonstrates load balancing by returning different "instance" identifiers.

## API Endpoints

### Health Checks
- `GET /health` - Basic health check
- `GET /health-detailed` - Detailed health check with instance metadata

### Application APIs  
- `GET /api/metrics` - Dashboard metrics (applications processed, pending, etc.)
- `GET /api/applications` - List of sample PDF applications
- `POST /api/applications/{id}/decision` - Submit approval/rejection decision

## Features

- **Route-based handling** - Single Lambda handles multiple API endpoints
- **CORS support** - Proper headers for ALB integration
- **Load balancing simulation** - Returns different AZ identifiers for visual demo
- **Error handling** - Proper HTTP status codes and error responses
- **TypeScript** - Full type safety and IntelliSense support

## Build and Deploy

### Prerequisites
- Node.js 22+ 
- TypeScript
- AWS CLI configured

### Build
```bash
# Install dependencies
npm install

# Build and package
./build.sh
```

This creates `deployment.zip` ready for Lambda deployment.

### Deploy via AWS CLI
```bash
# Create IAM role
aws iam create-role --role-name hitl-lambda-role --assume-role-policy-document file://iam-role.json

# Attach policy
aws iam attach-role-policy --role-name hitl-lambda-role --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole

# Create Lambda function
aws lambda create-function \
  --function-name hitl-api \
  --runtime nodejs22.x \
  --role arn:aws:iam::ACCOUNT-ID:role/hitl-lambda-role \
  --handler index.handler \
  --zip-file fileb://deployment.zip

# Update function (after changes)
aws lambda update-function-code \
  --function-name hitl-api \
  --zip-file fileb://deployment.zip
```

### Deploy via Terraform
The Lambda function will be deployed automatically as part of the main infrastructure stack in `terraform/app/`.

## Configuration

### Environment Variables
- `AWS_LAMBDA_FUNCTION_NAME` - Function name (set automatically)
- `AWS_REGION` - AWS region (set automatically)

### ALB Integration
The function is designed to work behind an Application Load Balancer with path-based routing:
- ALB routes `/api/*` and `/health*` paths to this Lambda
- CORS headers allow cross-origin requests from the React frontend
- Proper ALB event handling and response formatting

## Response Format

### API Endpoints
```json
{
  "data": { ... },
  "server_info": {
    "instance_id": "lambda-hitl-api-12345678",
    "availability_zone": "us-east-1a", 
    "instance_type": "lambda",
    "timestamp": "2025-01-27T10:30:00Z"
  },
  "timestamp": "2025-01-27T10:30:00Z"
}
```

### Health Endpoints
```json
{
  "status": "healthy",
  "timestamp": "2025-01-27T10:30:00Z",
  "instance_id": "lambda-hitl-api-12345678",
  "availability_zone": "us-east-1a",
  "instance_type": "lambda",
  "services": {
    "lambda": {
      "status": "active",
      "responding": true
    }
  },
  "version": "1.0"
}
```

## Load Balancing Demo

The Lambda function simulates different availability zones by randomly selecting from:
- `us-east-1a` (displays as blue badge in React app)
- `us-east-1b` (displays as green badge in React app)  
- `us-east-1c` (displays as orange badge in React app)

This allows the frontend to visually demonstrate load balancing even when running on Lambda (which doesn't have traditional instance-based load balancing).

## Security

- **IAM roles** with minimal required permissions
- **VPC integration** ready (if needed for private subnets)
- **CloudWatch logging** for audit trails
- **Input validation** on POST endpoints
- **CORS configuration** restricts origins appropriately

## Monitoring

The function automatically logs to CloudWatch with:
- Request/response details
- Error handling
- Performance metrics
- Decision submissions (for audit trails)

## Development

### Local Testing
```bash
# Install dependencies
npm install

# Build
npm run build

# Run tests (when added)
npm test
```

### File Structure
```
lambda-backend/
├── src/
│   ├── index.ts          # Main Lambda handler
│   └── types.ts          # TypeScript interfaces
├── package.json          # Dependencies and scripts
├── tsconfig.json         # TypeScript configuration
├── build.sh             # Build and package script
├── iam-role.json        # IAM role trust policy
└── iam-policy.json      # IAM permissions policy
```