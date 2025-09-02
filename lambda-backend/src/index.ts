import { ALBEvent, ALBResult, Context } from 'aws-lambda';
import { ApiResponse, MetricsData, Application, HealthResponse, DecisionRequest, ServerInfo } from './types';

// Mock instance metadata since Lambda doesn't have EC2 metadata
function getServerInfo(): ServerInfo {
  const functionName = process.env.AWS_LAMBDA_FUNCTION_NAME || 'hitl-api';
  const region = process.env.AWS_REGION || 'us-east-1';
  
  // Simulate different AZs based on function name or random selection
  const azs = ['us-east-1a', 'us-east-1b', 'us-east-1c'];
  const randomAZ = azs[Math.floor(Math.random() * azs.length)];
  
  return {
    instance: {
      id: `lambda-${functionName}-${Date.now().toString().slice(-8)}`,
      type: 'lambda',
      availability_zone: randomAZ,
      region: region
    },
    timestamp: new Date().toISOString()
  };
}

// Sample data for demonstration
const sampleApplications: Application[] = [
  {
    id: 'APP-2025-001234',
    type: 'Business License Application',
    applicant_name: 'Acme Corporation',
    submission_date: '2025-01-25T14:30:00Z',
    status: 'pending'
  },
  {
    id: 'APP-2025-001235', 
    type: 'Grant Proposal',
    applicant_name: 'Tech Innovations LLC',
    submission_date: '2025-01-25T16:45:00Z',
    status: 'pending'
  },
  {
    id: 'APP-2025-001236',
    type: 'Loan Application',
    applicant_name: 'Small Business Partners',
    submission_date: '2025-01-24T09:15:00Z',
    status: 'approved'
  },
  {
    id: 'APP-2025-001237',
    type: 'Permit Request',
    applicant_name: 'Construction Co.',
    submission_date: '2025-01-24T11:20:00Z',
    status: 'rejected'
  },
  {
    id: 'APP-2025-001238',
    type: 'Research Grant',
    applicant_name: 'University Research Lab',
    submission_date: '2025-01-23T13:10:00Z',
    status: 'approved'
  },
  {
    id: 'APP-2025-001239',
    type: 'Export License',
    applicant_name: 'Global Trade Inc.',
    submission_date: '2025-01-23T15:25:00Z',
    status: 'pending'
  }
];

// CORS headers for ALB integration
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'Content-Type,Authorization',
  'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
  'Content-Type': 'application/json'
};

// Create ALB response
function createResponse(statusCode: number, body: any, headers: Record<string, string> = {}): ALBResult {
  return {
    statusCode,
    headers: {
      ...corsHeaders,
      ...headers
    },
    body: typeof body === 'string' ? body : JSON.stringify(body),
    isBase64Encoded: false
  };
}

// Handle health endpoint
function handleHealth(): ALBResult {
  const serverInfo = getServerInfo();
  const healthResponse: HealthResponse = {
    status: 'healthy',
    timestamp: new Date().toISOString(),
    instance: serverInfo.instance,
    services: {
      lambda: {
        status: 'active',
        responding: true
      }
    },
    version: '1.0'
  };

  return createResponse(200, healthResponse);
}

// Handle metrics endpoint
function handleMetrics(): ALBResult {
  const serverInfo = getServerInfo();
  
  // Generate dynamic metrics based on current time for demonstration
  const now = new Date();
  const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
  
  const metricsData: MetricsData = {
    applications_processed: 127 + Math.floor(Math.random() * 10),
    pending_review: sampleApplications.filter(app => app.status === 'pending').length,
    approved_today: 15 + Math.floor(Math.random() * 5),
    rejected_today: 3 + Math.floor(Math.random() * 3)
  };

  const response: ApiResponse<MetricsData> = {
    data: metricsData,
    server_info: serverInfo,
    timestamp: new Date().toISOString()
  };

  return createResponse(200, response);
}

// Handle applications endpoint
function handleApplications(): ALBResult {
  const serverInfo = getServerInfo();
  
  const response: ApiResponse<Application[]> = {
    data: sampleApplications,
    server_info: serverInfo,
    timestamp: new Date().toISOString()
  };

  return createResponse(200, response);
}

// Handle decision submission
function handleDecision(applicationId: string, body: string): ALBResult {
  try {
    const decision: DecisionRequest = JSON.parse(body);
    
    // In a real implementation, this would update a database
    console.log(`Decision received for ${applicationId}:`, {
      decision: decision.decision,
      comments: decision.comments,
      timestamp: decision.timestamp
    });
    
    const serverInfo = getServerInfo();
    const response = {
      message: `Decision ${decision.decision} recorded for application ${applicationId}`,
      server_info: serverInfo,
      timestamp: new Date().toISOString()
    };

    return createResponse(200, response);
  } catch (error) {
    return createResponse(400, { 
      error: 'Invalid request body',
      message: error instanceof Error ? error.message : 'Unknown error'
    });
  }
}

// Handle OPTIONS preflight requests
function handleOptions(): ALBResult {
  return createResponse(204, '', {
    'Access-Control-Max-Age': '86400'
  });
}

// Main Lambda handler
export const handler = async (event: ALBEvent, context: Context): Promise<ALBResult> => {
  console.log('Request received:', JSON.stringify(event, null, 2));
  
  const path = event.path;
  const method = event.httpMethod;
  
  try {
    // Handle CORS preflight
    if (method === 'OPTIONS') {
      return handleOptions();
    }
    
    // Route to appropriate handler
    switch (true) {
      case path === '/health' || path === '/health-detailed':
        if (method === 'GET') {
          return handleHealth();
        }
        break;
        
      case path === '/api/metrics':
        if (method === 'GET') {
          return handleMetrics();
        }
        break;
        
      case path === '/api/applications':
        if (method === 'GET') {
          return handleApplications();
        }
        break;
        
      case path.startsWith('/api/applications/') && path.endsWith('/decision'):
        if (method === 'POST') {
          const applicationId = path.split('/')[3];
          return handleDecision(applicationId, event.body || '{}');
        }
        break;
        
      default:
        return createResponse(404, {
          error: 'Not Found',
          message: `Path ${path} not found`,
          available_endpoints: [
            'GET /health',
            'GET /health-detailed', 
            'GET /api/metrics',
            'GET /api/applications',
            'POST /api/applications/{id}/decision'
          ]
        });
    }
    
    return createResponse(405, {
      error: 'Method Not Allowed',
      message: `Method ${method} not allowed for path ${path}`
    });
    
  } catch (error) {
    console.error('Lambda error:', error);
    
    return createResponse(500, {
      error: 'Internal Server Error',
      message: error instanceof Error ? error.message : 'Unknown error',
      request_id: context.awsRequestId
    });
  }
};