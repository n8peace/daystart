/**
 * Authentication utilities for Edge Functions
 * Centralized JWT validation and user extraction
 */

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";
import { createErrorResponse } from "./cors.ts";

export interface AuthResult {
  success: boolean;
  userId?: string;
  supabase?: any;
  error?: Response;
}

/**
 * Extract and validate JWT token from request
 * Returns authenticated Supabase client and user ID
 */
export async function authenticateRequest(req: Request, requestId: string): Promise<AuthResult> {
  try {
    // Extract JWT token from Authorization header
    const authHeader = req.headers.get('Authorization');
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
      return {
        success: false,
        error: createErrorResponse('MISSING_AUTH', 'Authorization header with Bearer token required', requestId, 401)
      };
    }

    const token = authHeader.replace('Bearer ', '');
    
    // Initialize Supabase client with JWT context
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseKey = Deno.env.get('SUPABASE_ANON_KEY')!;
    
    const supabase = createClient(supabaseUrl, supabaseKey, {
      global: {
        headers: {
          Authorization: `Bearer ${token}`,
        },
      },
    });

    // Validate JWT and get authenticated user
    const { data: { user }, error: authError } = await supabase.auth.getUser(token);
    if (authError || !user) {
      console.error('Auth validation error:', authError);
      return {
        success: false,
        error: createErrorResponse('INVALID_TOKEN', 'Invalid or expired token', requestId, 401)
      };
    }

    return {
      success: true,
      userId: user.id,
      supabase: supabase
    };

  } catch (error) {
    console.error('Authentication error:', error);
    return {
      success: false,
      error: createErrorResponse('AUTH_ERROR', 'Authentication failed', requestId, 500)
    };
  }
}

/**
 * Check if request has valid authentication
 * Lighter weight check that doesn't initialize full Supabase client
 */
export function hasValidAuthHeader(req: Request): boolean {
  const authHeader = req.headers.get('Authorization');
  return authHeader !== null && authHeader.startsWith('Bearer ') && authHeader.length > 7;
}
