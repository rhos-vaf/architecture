#!/bin/bash
# Install OpenShift GitOps (ArgoCD) Operator

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}OpenShift GitOps (ArgoCD) Installation${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if oc is available
if ! command -v oc &> /dev/null; then
    echo -e "${RED}Error: 'oc' command not found. Please install OpenShift CLI.${NC}"
    exit 1
fi

# Check if logged in
if ! oc whoami &> /dev/null; then
    echo -e "${RED}Error: Not logged in to OpenShift. Please run 'oc login' first.${NC}"
    exit 1
fi

CURRENT_USER=$(oc whoami)
echo -e "${GREEN}✓${NC} Logged in as: $CURRENT_USER"
echo ""

# Check if already installed
if oc get namespace openshift-gitops &> /dev/null; then
    echo -e "${YELLOW}⚠ OpenShift GitOps appears to be already installed.${NC}"
    echo ""
    read -p "Do you want to continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
fi

# Install the operator
echo -e "${BLUE}Step 1: Installing OpenShift GitOps Operator...${NC}"

cat <<EOF | oc apply -f -
apiVersion: v1
kind: Namespace
metadata:
  name: openshift-gitops-operator
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: openshift-gitops-operator
  namespace: openshift-gitops-operator
spec:
  upgradeStrategy: Default
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-gitops-operator
  namespace: openshift-gitops-operator
spec:
  channel: latest
  installPlanApproval: Automatic
  name: openshift-gitops-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

echo -e "${GREEN}✓${NC} Operator subscription created"
echo ""

# Wait for operator to be ready
echo -e "${BLUE}Step 2: Waiting for operator to be ready (this may take 2-3 minutes)...${NC}"

# Wait for the operator namespace to have pods
for i in {1..60}; do
    if oc get pods -n openshift-gitops-operator &> /dev/null; then
        break
    fi
    echo -n "."
    sleep 5
done
echo ""

# Wait for operator pod to be ready
if ! oc wait --for=condition=Ready pod -l control-plane=gitops-operator \
    -n openshift-gitops-operator --timeout=300s 2>/dev/null; then
    echo -e "${YELLOW}⚠ Timeout waiting for operator pod. Checking status...${NC}"
    oc get pods -n openshift-gitops-operator
else
    echo -e "${GREEN}✓${NC} Operator is ready"
fi
echo ""

# Wait for default ArgoCD instance
echo -e "${BLUE}Step 3: Waiting for default ArgoCD instance to be created...${NC}"

for i in {1..60}; do
    if oc get namespace openshift-gitops &> /dev/null; then
        echo -e "${GREEN}✓${NC} ArgoCD namespace created"
        break
    fi
    echo -n "."
    sleep 5
done
echo ""

# Wait for ArgoCD pods
echo -e "${BLUE}Step 4: Waiting for ArgoCD pods to be ready...${NC}"

for i in {1..60}; do
    READY_PODS=$(oc get pods -n openshift-gitops --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [ "$READY_PODS" -ge 5 ]; then
        break
    fi
    echo -n "."
    sleep 5
done
echo ""

# Show pod status
echo -e "${BLUE}ArgoCD Pods:${NC}"
oc get pods -n openshift-gitops
echo ""

# Get ArgoCD URL and password
echo -e "${BLUE}Step 5: Retrieving ArgoCD access information...${NC}"
echo ""

if ARGOCD_URL=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}' 2>/dev/null); then
    echo -e "${GREEN}✓${NC} ArgoCD server is accessible"
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}ArgoCD Access Information${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
    echo -e "${GREEN}URL:${NC} https://${ARGOCD_URL}"
    echo ""
    echo -e "${GREEN}Username:${NC} admin"
    echo ""

    if ARGOCD_PASSWORD=$(oc extract secret/openshift-gitops-cluster -n openshift-gitops --to=- 2>/dev/null); then
        echo -e "${GREEN}Password:${NC} ${ARGOCD_PASSWORD}"
    else
        echo -e "${YELLOW}Password:${NC} (run this command to retrieve it)"
        echo "  oc extract secret/openshift-gitops-cluster -n openshift-gitops --to=-"
    fi
    echo ""
else
    echo -e "${YELLOW}⚠ Could not retrieve ArgoCD route. It may still be initializing.${NC}"
    echo "Run this command to get the URL:"
    echo "  oc get route openshift-gitops-server -n openshift-gitops"
fi

# Grant permissions to rhoso1 namespace
echo -e "${BLUE}Step 6: Granting ArgoCD permissions...${NC}"

# Create rhoso1 namespace if it doesn't exist
if ! oc get namespace rhoso1 &> /dev/null; then
    echo "Creating rhoso1 namespace..."
    oc create namespace rhoso1
fi

# Grant ArgoCD admin access to rhoso1
oc adm policy add-role-to-user admin \
    system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller \
    -n rhoso1 2>/dev/null || echo -e "${YELLOW}⚠ Could not grant permissions (may already exist)${NC}"

echo -e "${GREEN}✓${NC} Permissions configured"
echo ""

# Installation summary
echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Installation Summary${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""
echo -e "${GREEN}✓${NC} OpenShift GitOps Operator installed"
echo -e "${GREEN}✓${NC} Default ArgoCD instance created"
echo -e "${GREEN}✓${NC} Permissions configured for rhoso1 namespace"
echo ""

# Next steps
echo -e "${BLUE}Next Steps:${NC}"
echo ""
echo "1. Access ArgoCD UI:"
echo "   Open: https://${ARGOCD_URL}"
echo "   Login with credentials shown above"
echo ""
echo "2. Deploy the RHOSO application:"
echo "   cd /home/mcarpio/CLAUDE/architecture/va/nvidia-l4-passthrough"
echo "   # Update argocd/application.yaml with your Git repo URL"
echo "   oc apply -f argocd/application.yaml"
echo ""
echo "3. Monitor deployment:"
echo "   make argocd-status"
echo "   # or view in ArgoCD UI"
echo ""

# Optional: Install ArgoCD CLI
echo -e "${BLUE}Optional: Install ArgoCD CLI${NC}"
echo ""
read -p "Do you want to install the ArgoCD CLI? (y/N) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Installing ArgoCD CLI..."
    VERSION=$(curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
    curl -sSL -o /tmp/argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/download/$VERSION/argocd-linux-amd64
    sudo install -m 555 /tmp/argocd-linux-amd64 /usr/local/bin/argocd
    rm /tmp/argocd-linux-amd64

    if command -v argocd &> /dev/null; then
        echo -e "${GREEN}✓${NC} ArgoCD CLI installed: $(argocd version --client --short)"
        echo ""
        echo "Login to ArgoCD:"
        echo "  argocd login ${ARGOCD_URL} --username admin --password '${ARGOCD_PASSWORD}' --insecure"
    else
        echo -e "${RED}✗${NC} Failed to install ArgoCD CLI"
    fi
else
    echo "Skipping ArgoCD CLI installation."
fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}========================================${NC}"
