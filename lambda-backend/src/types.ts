export interface ServerInfo {
  instance: {
    id: string;
    type: string;
    availability_zone: string;
    region: string;
  };
  timestamp: string;
}

export interface MetricsData {
  applications_processed: number;
  pending_review: number;
  approved_today: number;
  rejected_today: number;
}

export interface Application {
  id: string;
  type: string;
  applicant_name: string;
  submission_date: string;
  status: 'pending' | 'approved' | 'rejected';
  pdf_url?: string;
}

export interface HealthResponse {
  status: 'healthy' | 'degraded' | 'unhealthy';
  timestamp: string;
  instance: {
    id: string;
    type: string;
    availability_zone: string;
    region: string;
  };
  services?: {
    lambda: {
      status: string;
      responding: boolean;
    };
  };
  version: string;
}

export interface ApiResponse<T> {
  data: T;
  server_info: ServerInfo;
  timestamp: string;
}

export interface DecisionRequest {
  decision: 'approve' | 'reject';
  comments?: string;
  timestamp: string;
}