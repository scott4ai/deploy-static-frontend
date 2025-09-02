import React, { useState, useEffect } from 'react';
import './App.css';

interface HealthData {
  status: string;
  timestamp: string;
  instance: {
    id: string;
    type: string;
    availability_zone: string;
    region: string;
    private_ip: string;
  };
  services?: {
    openresty?: {
      status: string;
      responding: boolean;
      version?: string;
      uptime_seconds?: number;
    };
    lambda?: {
      status: string;
      responding: boolean;
    };
    s3_sync?: {
      status: string;
      last_sync: string;
      seconds_since_last_sync?: number | null;
    };
  };
  system?: {
    load_average: string;
    memory_used_percent: number;
    disk_used: string;
    uptime_seconds: number;
  };
  environment?: {
    environment: string;
    project: string;
    s3_bucket: string;
  };
}

interface EC2Data {
  instance_id: string;
  served_by: string;
  served_at: string;
}


function App() {
  const [healthData, setHealthData] = useState<HealthData | null>(null);
  const [ec2Data, setEC2Data] = useState<EC2Data | null>(null);
  const [lambdaData, setLambdaData] = useState<any>(null);  // For Lambda API response
  const [loading, setLoading] = useState(true);
  const [lastRefresh, setLastRefresh] = useState(new Date());
  const [refreshCount, setRefreshCount] = useState(0);

  const captureEC2Data = async () => {
    try {
      // Make a request to capture response headers from EC2 instance
      const response = await fetch('/', { method: 'HEAD' });
      const instanceId = response.headers.get('X-Instance-ID') || 'unknown';
      const serverHeader = response.headers.get('Server') || 'unknown';
      
      setEC2Data({
        instance_id: instanceId,
        served_by: serverHeader,
        served_at: new Date().toISOString()
      });
    } catch (error) {
      console.error('Failed to capture EC2 data:', error);
      setEC2Data({
        instance_id: 'error',
        served_by: 'error',
        served_at: new Date().toISOString()
      });
    }
  };


  const fetchHealthData = async () => {
    try {
      const response = await fetch('/health-detailed');
      if (response.ok) {
        const data = await response.json();
        setHealthData(data);
      } else {
        // Fallback to simple health endpoint
        const simpleResponse = await fetch('/health');
        if (simpleResponse.ok) {
          const text = await simpleResponse.text();
          setHealthData({
            status: text.includes('healthy') ? 'healthy' : 'unknown',
            timestamp: new Date().toISOString(),
            instance: {
              id: 'unknown',
              type: 'unknown',
              availability_zone: 'unknown',
              region: 'unknown',
              private_ip: 'unknown'
            }
          });
        }
      }
    } catch (error) {
      console.error('Failed to fetch health data:', error);
      setHealthData({
        status: 'error',
        timestamp: new Date().toISOString(),
        instance: {
          id: 'error',
          type: 'error',
          availability_zone: 'error',
          region: 'error',
          private_ip: 'error'
        }
      });
    } finally {
      setLoading(false);
    }
  };

  const refreshData = () => {
    setLoading(true);
    setRefreshCount(prev => prev + 1);
    setLastRefresh(new Date());
    fetchHealthData();
    // Also refresh Lambda data
    fetch('/api/metrics').then(res => res.json()).then(data => setLambdaData(data.server_info)).catch(console.error);
  };

  useEffect(() => {
    captureEC2Data();
    fetchHealthData();
    // Also fetch initial Lambda data
    fetch('/api/metrics').then(res => res.json()).then(data => setLambdaData(data.server_info)).catch(console.error);
    // Refresh every 30 seconds
    const interval = setInterval(fetchHealthData, 30000);
    return () => clearInterval(interval);
  }, []);

  const getStatusColor = (status: string) => {
    switch (status.toLowerCase()) {
      case 'healthy': return '#28a745';
      case 'degraded': return '#ffc107';
      case 'unhealthy': return '#dc3545';
      default: return '#6c757d';
    }
  };

  const formatSyncTime = (seconds: number | null | undefined) => {
    if (seconds === null || seconds === undefined) return 'Unknown';
    if (seconds < 60) return `${seconds} seconds ago`;
    if (seconds < 120) return '1 minute ago';
    if (seconds < 3600) return `${Math.floor(seconds / 60)} minutes ago`;
    if (seconds < 7200) return '1 hour ago';
    return `${Math.floor(seconds / 3600)} hours ago`;
  };

  const getSyncStatusColor = (seconds: number | null | undefined) => {
    if (seconds === null || seconds === undefined) return '#6c757d'; // gray for unknown
    if (seconds < 300) return '#28a745'; // green if < 5 minutes
    if (seconds < 600) return '#ffc107'; // yellow if 5-10 minutes
    return '#dc3545'; // red if > 10 minutes
  };

  const getInstanceColor = (instanceId: string) => {
    // Generate consistent color based on instance ID
    let hash = 0;
    for (let i = 0; i < instanceId.length; i++) {
      const char = instanceId.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash;
    }
    const hue = Math.abs(hash) % 360;
    return `hsl(${hue}, 70%, 50%)`;
  };

  if (loading && !healthData) {
    return (
      <div style={{ 
        display: 'flex', 
        justifyContent: 'center', 
        alignItems: 'center', 
        height: '100vh',
        fontFamily: 'system-ui, -apple-system, sans-serif'
      }}>
        <div style={{ textAlign: 'center' }}>
          <div style={{ 
            border: '4px solid #f3f3f3',
            borderTop: '4px solid #007bff',
            borderRadius: '50%',
            width: '50px',
            height: '50px',
            animation: 'spin 1s linear infinite',
            margin: '0 auto 20px'
          }}></div>
          <p>Loading HITL Platform...</p>
        </div>
      </div>
    );
  }

  return (
    <div style={{
      fontFamily: 'system-ui, -apple-system, sans-serif',
      backgroundColor: '#f8f9fa',
      minHeight: '100vh',
      padding: '20px'
    }}>
      <div style={{
        maxWidth: '1200px',
        margin: '0 auto'
      }}>
        {/* Header */}
        <div style={{
          background: 'linear-gradient(135deg, #007bff, #0056b3)',
          color: 'white',
          padding: '30px',
          borderRadius: '8px',
          marginBottom: '20px',
          boxShadow: '0 4px 6px rgba(0,0,0,0.1)'
        }}>
          <h1 style={{ margin: 0, fontSize: '2.5rem' }}>HITL Platform</h1>
          <p style={{ margin: '10px 0 0', opacity: 0.9 }}>
            Human-in-the-Loop Interface • FedRAMP High Compliant Architecture
          </p>
        </div>

        {/* Infrastructure Status */}
        <div style={{
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))',
          gap: '20px',
          marginBottom: '30px'
        }}>
          {/* EC2 Instance Information */}
          <div style={{
            backgroundColor: 'white',
            padding: '25px',
            borderRadius: '8px',
            boxShadow: '0 2px 4px rgba(0,0,0,0.1)',
            border: `3px solid ${ec2Data ? getInstanceColor(ec2Data.instance_id) : '#ddd'}`
          }}>
            <h3 style={{ 
              margin: '0 0 15px',
              color: ec2Data ? getInstanceColor(ec2Data.instance_id) : '#333'
            }}>
              EC2 Frontend Server
            </h3>
            <div style={{ display: 'grid', gap: '10px' }}>
              <div><strong>Instance ID:</strong> {ec2Data?.instance_id || 'Loading...'}</div>
              <div><strong>Server:</strong> {ec2Data?.served_by || 'Loading...'}</div>
              <div><strong>Served At:</strong> {ec2Data ? new Date(ec2Data.served_at).toLocaleTimeString() : 'Loading...'}</div>
              <button 
                onClick={captureEC2Data}
                style={{
                  backgroundColor: '#28a745',
                  color: 'white',
                  border: 'none',
                  padding: '8px 16px',
                  borderRadius: '4px',
                  cursor: 'pointer',
                  fontSize: '0.9rem',
                  marginTop: '10px'
                }}
              >
                Refresh EC2 Data
              </button>
            </div>
          </div>

          {/* Lambda API Instance */}
          <div style={{
            backgroundColor: 'white',
            padding: '25px',
            borderRadius: '8px',
            boxShadow: '0 2px 4px rgba(0,0,0,0.1)',
            border: `3px solid ${lambdaData?.instance?.id ? getInstanceColor(lambdaData.instance.id) : '#ddd'}`
          }}>
            <h3 style={{ 
              margin: '0 0 15px',
              color: lambdaData?.instance?.id ? getInstanceColor(lambdaData.instance.id) : '#333'
            }}>
              Lambda API Backend
            </h3>
            <div style={{ display: 'grid', gap: '10px' }}>
              <div><strong>Instance ID:</strong> {lambdaData?.instance?.id || 'Loading...'}</div>
              <div><strong>Zone:</strong> {lambdaData?.instance?.availability_zone || 'Loading...'}</div>
              <div><strong>Type:</strong> {lambdaData?.instance?.type || 'Loading...'}</div>
              <div><strong>Last Response:</strong> {lambdaData ? new Date(lambdaData.timestamp).toLocaleTimeString() : 'Loading...'}</div>
            </div>
          </div>

          {/* Health Status */}
          <div style={{
            backgroundColor: 'white',
            padding: '25px',
            borderRadius: '8px',
            boxShadow: '0 2px 4px rgba(0,0,0,0.1)',
            border: `3px solid ${healthData ? getStatusColor(healthData.status) : '#ddd'}`
          }}>
            <h3 style={{ margin: '0 0 15px' }}>System Status</h3>
            <div style={{
              fontSize: '1.5rem',
              fontWeight: 'bold',
              color: healthData ? getStatusColor(healthData.status) : '#666',
              textTransform: 'uppercase',
              marginBottom: '10px'
            }}>
              {healthData?.status || 'Loading...'}
            </div>
            <div style={{ fontSize: '0.9rem', color: '#666' }}>
              Last Updated: {healthData ? new Date(healthData.timestamp).toLocaleTimeString() : 'Loading...'}
            </div>
          </div>

          {/* Services */}
          {healthData?.services && (
            <div style={{
              backgroundColor: 'white',
              padding: '25px',
              borderRadius: '8px',
              boxShadow: '0 2px 4px rgba(0,0,0,0.1)'
            }}>
              <h3 style={{ margin: '0 0 15px' }}>Services</h3>
              <div style={{ display: 'grid', gap: '8px' }}>
                {healthData.services?.openresty && (
                  <div>
                    <strong>OpenResty:</strong>{' '}
                    <span style={{ 
                      color: healthData.services?.openresty?.status === 'active' ? '#28a745' : '#dc3545',
                      fontWeight: 'bold'
                    }}>
                      {healthData.services?.openresty?.status}
                    </span>
                    {healthData.services?.openresty?.responding ? ' ✓' : ' ✗'}
                  </div>
                )}
                {healthData.services?.lambda && (
                  <div>
                    <strong>Lambda:</strong>{' '}
                    <span style={{ 
                      color: healthData.services?.lambda?.status === 'active' ? '#28a745' : '#dc3545',
                      fontWeight: 'bold'
                    }}>
                      {healthData.services?.lambda?.status}
                    </span>
                    {healthData.services?.lambda?.responding ? ' ✓' : ' ✗'}
                  </div>
                )}
                {healthData.services?.s3_sync && (
                  <div>
                    <strong>S3 Sync:</strong>{' '}
                    <span style={{ 
                      color: getSyncStatusColor(healthData.services?.s3_sync?.seconds_since_last_sync),
                      fontWeight: 'bold'
                    }}>
                      {formatSyncTime(healthData.services?.s3_sync?.seconds_since_last_sync)}
                    </span>
                    {healthData.services?.s3_sync?.seconds_since_last_sync !== null && 
                     healthData.services?.s3_sync?.seconds_since_last_sync !== undefined && 
                     healthData.services?.s3_sync?.seconds_since_last_sync < 300 ? ' ✓' : ' ⚠'}
                  </div>
                )}
              </div>
            </div>
          )}

          {/* System Metrics */}
          {healthData?.system && (
            <div style={{
              backgroundColor: 'white',
              padding: '25px',
              borderRadius: '8px',
              boxShadow: '0 2px 4px rgba(0,0,0,0.1)'
            }}>
              <h3 style={{ margin: '0 0 15px' }}>System Metrics</h3>
              <div style={{ display: 'grid', gap: '8px' }}>
                <div><strong>Disk Usage:</strong> {healthData.system.disk_used}</div>
                <div><strong>Memory Usage:</strong> {healthData.system.memory_used_percent}%</div>
                <div><strong>Load Average:</strong> {healthData.system.load_average}</div>
              </div>
            </div>
          )}
        </div>

        {/* Load Balancing Demo */}
        <div style={{
          backgroundColor: 'white',
          padding: '25px',
          borderRadius: '8px',
          boxShadow: '0 2px 4px rgba(0,0,0,0.1)',
          marginBottom: '20px'
        }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: '15px' }}>
            <h3 style={{ margin: 0 }}>Load Balancing Demonstration</h3>
            <button 
              onClick={refreshData}
              disabled={loading}
              style={{
                backgroundColor: '#007bff',
                color: 'white',
                border: 'none',
                padding: '10px 20px',
                borderRadius: '4px',
                cursor: loading ? 'not-allowed' : 'pointer',
                opacity: loading ? 0.6 : 1
              }}
            >
              {loading ? 'Refreshing...' : 'Refresh Lambda API'}
            </button>
          </div>
          <p style={{ color: '#666', marginBottom: '15px' }}>
            <strong>EC2 Load Balancing:</strong> Click "Refresh EC2 Data" above or refresh the page to see different EC2 instances serving the frontend.<br/>
            <strong>Lambda Load Balancing:</strong> Click "Refresh Lambda API" to see different Lambda execution contexts serving the API.
          </p>
          <div style={{ fontSize: '0.9rem', color: '#666' }}>
            <div>Refreshes: {refreshCount}</div>
            <div>Last Refresh: {lastRefresh.toLocaleTimeString()}</div>
          </div>
        </div>

        {/* Architecture Info */}
        <div style={{
          backgroundColor: 'white',
          padding: '25px',
          borderRadius: '8px',
          boxShadow: '0 2px 4px rgba(0,0,0,0.1)'
        }}>
          <h3 style={{ margin: '0 0 15px' }}>Architecture</h3>
          <div style={{
            display: 'grid',
            gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))',
            gap: '15px'
          }}>
            <div>
              <strong>Frontend:</strong><br/>
              React + OpenResty on EC2
            </div>
            <div>
              <strong>Load Balancer:</strong><br/>
              Application Load Balancer
            </div>
            <div>
              <strong>Backend:</strong><br/>
              AWS Lambda Functions
            </div>
            <div>
              <strong>Storage:</strong><br/>
              S3 with automated sync
            </div>
            <div>
              <strong>Security:</strong><br/>
              WAF + Security Groups
            </div>
            <div>
              <strong>Monitoring:</strong><br/>
              CloudWatch + Health Checks
            </div>
          </div>
        </div>
      </div>

      <style>{`
        @keyframes spin {
          0% { transform: rotate(0deg); }
          100% { transform: rotate(360deg); }
        }
      `}</style>
    </div>
  );
}

export default App;
