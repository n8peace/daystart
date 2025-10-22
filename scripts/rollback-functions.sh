#!/bin/bash

# Rollback script for Supabase deployment
# This script reverts the entire Supabase project (functions + migrations) to a specific commit
# Supports both interactive and CI/CD usage

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} ${1}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} ${1}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} ${1}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} ${1}"
}

# Check if we're running in CI (GitHub Actions)
IS_CI=${CI:-false}

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    log_error "Not in a git repository!"
    exit 1
fi

# Get the current commit hash
CURRENT_COMMIT=$(git rev-parse HEAD)
log_info "Current commit: ${CURRENT_COMMIT}"

# Determine target commit for rollback
if [[ -n "${ROLLBACK_TARGET_COMMIT:-}" ]]; then
    # Use the explicitly provided target commit (from CI)
    TARGET_COMMIT="${ROLLBACK_TARGET_COMMIT}"
    log_info "Using provided rollback target: ${TARGET_COMMIT}"
else
    # For interactive use, get the previous commit
    TARGET_COMMIT=$(git rev-parse HEAD~1)
    log_info "Using previous commit as target: ${TARGET_COMMIT}"
fi

# Verify the target commit exists
if ! git rev-parse --quiet --verify "${TARGET_COMMIT}" > /dev/null 2>&1; then
    log_error "Target commit ${TARGET_COMMIT} does not exist!"
    exit 1
fi

# Check if rollback is needed
if [[ "${CURRENT_COMMIT}" == "${TARGET_COMMIT}" ]]; then
    log_warning "Already at target commit ${TARGET_COMMIT}"
    exit 0
fi

# Show what will be rolled back
log_info "Changes to be reverted:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
git diff --name-status "${TARGET_COMMIT}" "${CURRENT_COMMIT}" -- supabase/
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Interactive confirmation (skip in CI)
if [[ "${IS_CI}" != "true" ]]; then
    read -p "Do you want to rollback to commit ${TARGET_COMMIT:0:8}? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Rollback cancelled"
        exit 0
    fi
fi

# Create a backup branch (skip in CI as it's not needed)
if [[ "${IS_CI}" != "true" ]]; then
    BACKUP_BRANCH="backup-before-rollback-$(date +%Y%m%d_%H%M%S)"
    git branch "${BACKUP_BRANCH}"
    log_info "Created backup branch: ${BACKUP_BRANCH}"
fi

# Checkout the target version of the entire supabase directory
log_info "Reverting supabase directory to ${TARGET_COMMIT:0:8}..."
git checkout "${TARGET_COMMIT}" -- supabase/

# Check if the revert actually changed anything
if git diff --quiet; then
    log_warning "No actual changes detected after revert"
    exit 0
fi

# Check required environment variables
if [[ -z "${SUPABASE_PROJECT_REF:-}" ]] || [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
    log_error "Missing required environment variables: SUPABASE_PROJECT_REF, SUPABASE_ACCESS_TOKEN"
    log_info "Restoring working directory..."
    git checkout "${CURRENT_COMMIT}" -- supabase/
    exit 1
fi

# In CI, we need to set up Supabase CLI
if [[ "${IS_CI}" == "true" ]]; then
    log_info "Setting up Supabase CLI for CI environment..."
    
    # Link project if not already linked
    if [[ -n "${SUPABASE_DB_PASSWORD:-}" ]]; then
        supabase link --project-ref "${SUPABASE_PROJECT_REF}" \
            --password "${SUPABASE_DB_PASSWORD}" || true
    fi
fi

# Deploy the reverted state
log_info "Deploying reverted state to Supabase..."

# First, apply any database migrations
log_info "Applying database state from ${TARGET_COMMIT:0:8}..."
if ! supabase db push; then
    log_error "Failed to apply database changes!"
    log_warning "Database state may be inconsistent - manual review required"
    # Don't exit here - try to deploy functions anyway
fi

# Deploy the functions
log_info "Deploying functions from ${TARGET_COMMIT:0:8}..."
if supabase functions deploy; then
    log_success "Functions successfully deployed from ${TARGET_COMMIT:0:8}!"
else
    log_error "Failed to deploy functions!"
    log_info "Restoring working directory..."
    git checkout "${CURRENT_COMMIT}" -- supabase/
    exit 1
fi

# Summary
log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_success "Rollback completed successfully!"
log_success "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "Previous state: ${CURRENT_COMMIT:0:8}"
log_info "Rolled back to: ${TARGET_COMMIT:0:8}"

# Only commit if not in CI (GitHub Actions will handle this)
if [[ "${IS_CI}" != "true" ]]; then
    git add supabase/
    git commit -m "Rollback: Revert Supabase to ${TARGET_COMMIT}

This rollback was performed to restore a known working state.
Previous commit: ${CURRENT_COMMIT}
Rolled back to: ${TARGET_COMMIT}

To restore the previous state, run:
git checkout ${BACKUP_BRANCH} -- supabase/"
    
    log_success "Rollback committed"
    log_info "To restore the previous state, run:"
    log_info "  git checkout ${BACKUP_BRANCH} -- supabase/"
else
    log_info "Working directory contains rollback changes (commit skipped in CI)"
fi