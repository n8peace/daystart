/**
 * CORS headers for Edge Functions
 * Centralized CORS configuration for all DayStart Edge Functions
 */

export function corsHeaders(): Record<string, string> {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
    'Access-Control-Max-Age': '86400', // 24 hours
  };
}

export function createCorsResponse(
  body: any, 
  status: number = 200,
  additionalHeaders: Record<string, string> = {}
): Response {
  return new Response(
    typeof body === 'string' ? body : JSON.stringify(body),
    {
      status,
      headers: {
        ...corsHeaders(),
        'Content-Type': 'application/json',
        ...additionalHeaders,
      },
    }
  );
}

export function createErrorResponse(
  errorCode: string,
  errorMessage: string,
  requestId: string,
  status: number = 400
): Response {
  return createCorsResponse(
    {
      success: false,
      error_code: errorCode,
      error_message: errorMessage,
      request_id: requestId,
    },
    status
  );
}
