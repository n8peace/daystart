import { serve } from "https://deno.land/std@0.208.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.3";

interface SubmitFeedbackRequest {
  category: string;
  message?: string;
  include_diagnostics?: boolean;
  history_id?: string;
  app_version?: string;
  build?: string;
  device_model?: string;
  os_version?: string;
  email?: string;
}

interface SubmitFeedbackResponse {
  success: boolean;
  message: string;
}

serve(async (req: Request): Promise<Response> => {
  try {
    // CORS preflight support
    if (req.method === 'OPTIONS') {
      return new Response(null, {
        status: 204,
        headers: {
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Headers': 'authorization, x-client-info, content-type, x-auth-type',
          'Access-Control-Allow-Methods': 'POST, OPTIONS'
        }
      });
    }

    if (req.method !== 'POST') {
      return new Response(JSON.stringify({ success: false, message: 'Method not allowed' }), {
        status: 405,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Parse request body
    const body: SubmitFeedbackRequest = await req.json();

    // Validate required fields
    if (!body.category) {
      return new Response(JSON.stringify({ success: false, message: 'Category is required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    // Extract user ID from headers (receipt ID for purchased users)
    const userId = req.headers.get('x-client-info');
    const authType = req.headers.get('x-auth-type');

    if (!userId) {
      return new Response(JSON.stringify({ success: false, message: 'User identification required' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    console.log(`📝 Feedback submission from user: ${userId.substring(0, 8)}...`);
    console.log(`📝 Category: ${body.category}, Auth type: ${authType}`);

    // Initialize Supabase client with service role
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Track purchase user for analytics (non-critical, fail-safe)
    try {
      if (authType === 'purchase') {
        await supabase.rpc('track_purchase_user', {
          p_receipt_id: userId,
          p_is_test: userId.startsWith('tx_')
        });
      }
    } catch (error) {
      console.warn('User tracking failed (non-critical):', error);
    }

    // Insert feedback using service role (bypasses RLS)
    const { error } = await supabase
      .from('app_feedback')
      .insert({
        user_id: userId,
        category: body.category,
        message: body.message || null,
        include_diagnostics: body.include_diagnostics || false,
        history_id: body.history_id || null,
        app_version: body.app_version || null,
        build: body.build || null,
        device_model: body.device_model || null,
        os_version: body.os_version || null,
        email: body.email || null
      });

    if (error) {
      console.error('Failed to insert feedback:', error);
      return new Response(JSON.stringify({ success: false, message: 'Database error' }), {
        status: 500,
        headers: { 'Content-Type': 'application/json' }
      });
    }

    console.log(`✅ Feedback submitted successfully for user: ${userId.substring(0, 8)}...`);

    return new Response(JSON.stringify({ success: true, message: 'Feedback submitted' }), {
      status: 201,
      headers: { 'Content-Type': 'application/json' }
    });

  } catch (error) {
    console.error('Submit feedback error:', error);
    return new Response(JSON.stringify({ success: false, message: 'Internal error' }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' }
    });
  }
});