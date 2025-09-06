#!/bin/bash

# Rollback script for Supabase Edge Functions
# This script reverts Edge Functions to the previous git commit

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

# Check if we're in a git repository
if ! git rev-parse --git-dir > /dev/null 2>&1; then
    log_error "Not in a git repository!"
    exit 1
fi

# Get the current commit hash
CURRENT_COMMIT=$(git rev-parse HEAD)
log_info "Current commit: ${CURRENT_COMMIT}"

# Check if there are uncommitted changes
if ! git diff-index --quiet HEAD --; then
    log_warning "There are uncommitted changes in the repository"
    read -p "Do you want to stash them and continue? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        git stash push -m "Rollback stash at $(date)"
        log_info "Changes stashed"
    else
        log_error "Cannot rollback with uncommitted changes"
        exit 1
    fi
fi

# Get the previous commit that modified supabase/functions
PREVIOUS_COMMIT=$(git log -n 2 --pretty=format:"%H" -- supabase/functions/ | tail -n 1)

if [[ -z "${PREVIOUS_COMMIT}" ]]; then
    log_error "No previous commit found for supabase/functions/"
    exit 1
fi

log_info "Previous functions commit: ${PREVIOUS_COMMIT}"

# Show what changed
log_info "Changes to be reverted:"
git diff --name-only "${PREVIOUS_COMMIT}" "${CURRENT_COMMIT}" -- supabase/functions/

read -p "Do you want to rollback to this commit? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Rollback cancelled"
    exit 0
fi

# Create a backup branch
BACKUP_BRANCH="backup-before-rollback-$(date +%Y%m%d_%H%M%S)"
git branch "${BACKUP_BRANCH}"
log_info "Created backup branch: ${BACKUP_BRANCH}"

# Checkout the previous version of the functions
log_info "Reverting functions to previous version..."
git checkout "${PREVIOUS_COMMIT}" -- supabase/functions/

# Check required environment variables
if [[ -z "${SUPABASE_PROJECT_REF:-}" ]] || [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
    log_error "Missing required environment variables: SUPABASE_PROJECT_REF, SUPABASE_ACCESS_TOKEN"
    log_info "Restoring working directory..."
    git checkout "${CURRENT_COMMIT}" -- supabase/functions/
    exit 1
fi

# Deploy the reverted functions
log_info "Deploying reverted functions to Supabase..."
if supabase functions deploy; then
    log_success "Functions successfully rolled back!"
    
    # Commit the rollback
    git add supabase/functions/
    git commit -m "Rollback: Revert Edge Functions to ${PREVIOUS_COMMIT}

This rollback was performed due to deployment validation failure.
Previous commit: ${CURRENT_COMMIT}
Rolled back to: ${PREVIOUS_COMMIT}

To restore the previous state, run:
git checkout ${BACKUP_BRANCH} -- supabase/functions/"
    
    log_success "Rollback committed"
    log_info "To restore the previous state, run:"
    log_info "  git checkout ${BACKUP_BRANCH} -- supabase/functions/"
else
    log_error "Failed to deploy reverted functions!"
    log_info "Restoring working directory..."
    git checkout "${CURRENT_COMMIT}" -- supabase/functions/
    exit 1
fi