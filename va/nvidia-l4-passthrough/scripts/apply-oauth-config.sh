#!/bin/bash
# Apply OpenShift OAuth configuration to ArgoCD instance
# This script must be run as cluster-admin

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Apply OpenShift OAuth Configuration${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if we have cluster-admin permissions
echo "Checking permissions..."
if ! oc auth can-i create argocds -n gitops-rhoso1 &> /dev/null; then
    echo -e "${RED}Error: You need cluster-admin permissions to update ArgoCD instance.${NC}"
    echo ""
    echo "Please run this as cluster-admin user:"
    echo "  oc login -u kubeadmin"
    echo "  bash scripts/apply-oauth-config.sh"
    echo ""
    echo "Or if using CRC:"
    echo "  oc login -u kubeadmin -p \$(cat ~/.crc/machines/crc/kubeadmin-password) https://api.crc.testing:6443"
    exit 1
fi

echo -e "${GREEN}✓${NC} You have cluster-admin permissions"
echo ""

# Show current RBAC config
echo "Current RBAC configuration in file:"
echo "===================================="
grep -A 13 "rbac:" argocd/argocd-rhoso1-instance.yaml | sed 's/^/  /'
echo ""

# Apply the configuration
echo "Applying updated ArgoCD instance configuration..."
oc apply -f argocd/argocd-rhoso1-instance.yaml

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Configuration applied successfully"
else
    echo -e "${RED}✗${NC} Failed to apply configuration"
    exit 1
fi
echo ""

# Wait for rollout
echo "Waiting for ArgoCD server to restart..."
oc rollout status deployment/gitops-rhoso1-server -n gitops-rhoso1 --timeout=300s

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} ArgoCD server restarted successfully"
else
    echo -e "${YELLOW}⚠${NC} Rollout may still be in progress"
fi
echo ""

# Get ArgoCD URL
ARGOCD_URL=$(oc get route gitops-rhoso1-server -n gitops-rhoso1 -o jsonpath='{.spec.host}' 2>/dev/null)

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}OpenShift OAuth Login Enabled${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${GREEN}ArgoCD URL:${NC} https://${ARGOCD_URL}"
echo ""
echo "Login Options:"
echo "=============="
echo ""
echo "1. OpenShift OAuth (Recommended):"
echo "   - Click 'LOG IN VIA OPENSHIFT' button"
echo "   - Use your OpenShift credentials"
echo "   - Any authenticated user gets admin access"
echo ""
echo "2. Admin User (Fallback):"
echo "   - Username: admin"
echo "   - Password: \$(oc get secret gitops-rhoso1-cluster -n gitops-rhoso1 -o jsonpath='{.data.admin\.password}' | base64 -d)"
echo ""
echo -e "${BLUE}RBAC Configuration:${NC}"
echo "==================="
echo "✓ All authenticated OpenShift users: admin access"
echo "✓ Cluster admins: admin access"
echo ""
echo "To customize access, edit the rbac.policy in:"
echo "  argocd/argocd-rhoso1-instance.yaml"
echo ""
echo "See: argocd/OPENSHIFT_OAUTH_LOGIN.md for details"
echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Configuration Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
