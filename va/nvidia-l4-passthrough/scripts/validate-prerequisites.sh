#!/bin/bash
# Validate prerequisites for RHOSO NVIDIA L4 GitOps deployment

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ERRORS=0
WARNINGS=0

echo "========================================"
echo "RHOSO NVIDIA L4 Deployment - Prerequisites Check"
echo "========================================"
echo ""

# Function to print status
print_status() {
    local status=$1
    local message=$2
    if [ "$status" == "OK" ]; then
        echo -e "${GREEN}✓${NC} $message"
    elif [ "$status" == "WARN" ]; then
        echo -e "${YELLOW}⚠${NC} $message"
        ((WARNINGS++))
    else
        echo -e "${RED}✗${NC} $message"
        ((ERRORS++))
    fi
}

# Check OpenShift connection
echo "Checking OpenShift Connection..."
if oc whoami &> /dev/null; then
    CURRENT_USER=$(oc whoami)
    print_status "OK" "Connected to OpenShift as: $CURRENT_USER"
else
    print_status "ERROR" "Cannot connect to OpenShift cluster"
fi
echo ""

# Check OpenShift version
echo "Checking OpenShift Version..."
if OCP_VERSION=$(oc version -o json 2>/dev/null | jq -r '.openshiftVersion' 2>/dev/null); then
    print_status "OK" "OpenShift version: $OCP_VERSION"
else
    print_status "WARN" "Could not determine OpenShift version"
fi
echo ""

# Check for worker nodes
echo "Checking Worker Nodes..."
WORKER_COUNT=$(oc get nodes -l node-role.kubernetes.io/worker --no-headers 2>/dev/null | wc -l)
if [ "$WORKER_COUNT" -gt 0 ]; then
    print_status "OK" "Found $WORKER_COUNT worker node(s)"
    oc get nodes -l node-role.kubernetes.io/worker -o custom-columns=NAME:.metadata.name,STATUS:.status.conditions[?\(@.type==\"Ready\"\)].status
else
    print_status "ERROR" "No worker nodes found"
fi
echo ""

# Check for OpenStack operators namespace
echo "Checking OpenStack Operators..."
if oc get namespace openstack-operators &> /dev/null; then
    print_status "OK" "openstack-operators namespace exists"

    # Check for openstack-operator deployment
    if oc get deployment openstack-operator-controller-manager -n openstack-operators &> /dev/null; then
        READY=$(oc get deployment openstack-operator-controller-manager -n openstack-operators -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        if [ "$READY" -gt 0 ]; then
            print_status "OK" "OpenStack operator is running"
        else
            print_status "ERROR" "OpenStack operator is not ready"
        fi
    else
        print_status "ERROR" "OpenStack operator deployment not found"
    fi
else
    print_status "ERROR" "openstack-operators namespace not found - run 'make openstack' from install_yamls"
fi
echo ""

# Check for ArgoCD/OpenShift GitOps
echo "Checking ArgoCD/OpenShift GitOps..."
if oc get namespace openshift-gitops &> /dev/null; then
    print_status "OK" "openshift-gitops namespace exists"

    # Check for ArgoCD server
    if oc get deployment openshift-gitops-server -n openshift-gitops &> /dev/null; then
        READY=$(oc get deployment openshift-gitops-server -n openshift-gitops -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        if [ "$READY" -gt 0 ]; then
            print_status "OK" "ArgoCD server is running"
            ARGOCD_URL=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}' 2>/dev/null || echo "unknown")
            echo "   ArgoCD URL: https://$ARGOCD_URL"
        else
            print_status "WARN" "ArgoCD server is not ready"
        fi
    else
        print_status "WARN" "ArgoCD server deployment not found"
    fi
else
    print_status "WARN" "openshift-gitops namespace not found - GitOps operator may not be installed"
    echo "   You can still deploy using 'make deploy' but ArgoCD deployment won't work"
fi
echo ""

# Check for existing rhoso1 namespace
echo "Checking Target Namespace..."
if oc get namespace rhoso1 &> /dev/null; then
    print_status "WARN" "Namespace rhoso1 already exists - deployment may conflict"

    # Check for existing OpenStackControlPlane
    if oc get openstackcontrolplane -n rhoso1 &> /dev/null 2>&1; then
        CTLPLANE_COUNT=$(oc get openstackcontrolplane -n rhoso1 --no-headers 2>/dev/null | wc -l)
        if [ "$CTLPLANE_COUNT" -gt 0 ]; then
            print_status "WARN" "Found $CTLPLANE_COUNT existing OpenStackControlPlane(s) in rhoso1"
        fi
    fi
else
    print_status "OK" "Namespace rhoso1 does not exist - will be created"
fi
echo ""

# Check for local-storage StorageClass
echo "Checking Storage..."
if oc get storageclass local-storage &> /dev/null; then
    print_status "WARN" "StorageClass 'local-storage' already exists"
else
    print_status "OK" "StorageClass 'local-storage' does not exist - will be created"
fi

# Check for existing PVs
PV_COUNT=$(oc get pv -o json 2>/dev/null | jq -r '.items[] | select(.spec.storageClassName=="local-storage") | .metadata.name' | wc -l)
if [ "$PV_COUNT" -gt 0 ]; then
    print_status "WARN" "Found $PV_COUNT existing PVs with storageClass 'local-storage'"
else
    print_status "OK" "No existing local-storage PVs found"
fi
echo ""

# Check for NVIDIA GPUs on worker nodes (if lspci is available)
echo "Checking for NVIDIA GPUs..."
GPU_FOUND=false
for node in $(oc get nodes -l node-role.kubernetes.io/worker -o jsonpath='{.items[*].metadata.name}'); do
    # Try to check for NVIDIA devices via node feature discovery labels or direct check
    if oc get node "$node" -o json 2>/dev/null | jq -r '.metadata.labels' | grep -q nvidia; then
        print_status "OK" "NVIDIA GPU detected on node: $node"
        GPU_FOUND=true
    fi
done

if [ "$GPU_FOUND" = false ]; then
    print_status "WARN" "Could not detect NVIDIA GPUs via node labels - ensure GPUs are present and configured"
    echo "   You may need to install Node Feature Discovery or GPU operator"
fi
echo ""

# Check for required CRDs
echo "Checking Required CRDs..."
REQUIRED_CRDS=(
    "openstackcontrolplanes.core.openstack.org"
    "netconfigs.network.openstack.org"
)

for crd in "${REQUIRED_CRDS[@]}"; do
    if oc get crd "$crd" &> /dev/null; then
        print_status "OK" "CRD $crd exists"
    else
        print_status "ERROR" "CRD $crd not found"
    fi
done
echo ""

# Check for kustomize
echo "Checking Required Tools..."
if command -v kustomize &> /dev/null; then
    KUSTOMIZE_VERSION=$(kustomize version --short 2>/dev/null || echo "unknown")
    print_status "OK" "kustomize is installed: $KUSTOMIZE_VERSION"
else
    print_status "WARN" "kustomize not found - using 'oc kustomize' instead"
fi

# Check for argocd CLI (optional)
if command -v argocd &> /dev/null; then
    ARGOCD_VERSION=$(argocd version --client --short 2>/dev/null || echo "unknown")
    print_status "OK" "argocd CLI is installed: $ARGOCD_VERSION"
else
    print_status "WARN" "argocd CLI not found - some commands won't work (optional)"
fi

# Check for jq
if command -v jq &> /dev/null; then
    print_status "OK" "jq is installed"
else
    print_status "WARN" "jq not found - some validation checks skipped (optional)"
fi
echo ""

# Summary
echo "========================================"
echo "Validation Summary"
echo "========================================"
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed!${NC}"
    echo ""
    echo "You can proceed with deployment:"
    echo "  1. Update argocd/application.yaml with your Git repository URL"
    echo "  2. Run: make argocd-deploy"
    echo "  or"
    echo "  2. Run: make deploy (for direct deployment)"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ Validation completed with $WARNINGS warning(s)${NC}"
    echo ""
    echo "You can proceed with deployment, but review the warnings above."
    exit 0
else
    echo -e "${RED}✗ Validation failed with $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo ""
    echo "Please fix the errors above before proceeding."
    exit 1
fi
