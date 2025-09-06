#!/bin/bash

# Simple test to verify deployment script works
set -euo pipefail

echo "Testing deployment script setup..."

# Check if deployment script exists
if [[ ! -f "./deploy-supabase.sh" ]]; then
    echo "ERROR: deploy-supabase.sh not found in current directory"
    exit 1
fi

# Check required environment variables
missing_vars=()
[[ -z "${SUPABASE_PROJECT_REF:-}" ]] && missing_vars+=("SUPABASE_PROJECT_REF")
[[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]] && missing_vars+=("SUPABASE_ACCESS_TOKEN") 
[[ -z "${SUPABASE_ANON_KEY:-}" ]] && missing_vars+=("SUPABASE_ANON_KEY")
[[ -z "${SUPABASE_DB_PASSWORD:-}" ]] && missing_vars+=("SUPABASE_DB_PASSWORD")

if [[ ${#missing_vars[@]} -gt 0 ]]; then
    echo "Missing required environment variables:"
    printf '  - %s\n' "${missing_vars[@]}"
    echo ""
    echo "Please set these before running deployment:"
    echo "  export SUPABASE_PROJECT_REF='your-project-ref'"
    echo "  export SUPABASE_ACCESS_TOKEN='your-access-token'"
    echo "  export SUPABASE_ANON_KEY='your-anon-key'"
    echo "  export SUPABASE_DB_PASSWORD='your-db-password'"
    exit 1
fi

echo "✓ Deployment script found"
echo "✓ Environment variables set"
echo ""
echo "Current settings:"
echo "  Project: ${SUPABASE_PROJECT_REF}"
echo "  Directory: $(pwd)"
echo ""
echo "Ready to run deployment. Use: ./deploy-supabase.sh"