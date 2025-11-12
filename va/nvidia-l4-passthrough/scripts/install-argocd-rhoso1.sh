#!/bin/bash
# Install dedicated ArgoCD instance for RHOSO in gitops-rhoso1 namespace

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}Dedicated ArgoCD Instance Installation for RHOSO${NC}"
echo -e "${BLUE}================================================================${NC}"
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

# Check if OpenShift GitOps operator is installed
echo -e "${BLUE}Step 1: Checking for OpenShift GitOps operator...${NC}"
if ! oc get crd argocds.argoproj.io &> /dev/null; then
    echo -e "${RED}Error: OpenShift GitOps operator is not installed.${NC}"
    echo "Please install it first by running:"
    echo "  make install-argocd"
    echo "or"
    echo "  bash scripts/install-argocd.sh"
    exit 1
fi
echo -e "${GREEN}✓${NC} OpenShift GitOps operator is installed"
echo ""

# Check if gitops-rhoso1 already exists
if oc get namespace gitops-rhoso1 &> /dev/null; then
    echo -e "${YELLOW}⚠ Namespace gitops-rhoso1 already exists.${NC}"
    echo ""
    read -p "Do you want to continue and recreate the ArgoCD instance? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
    echo "Deleting existing ArgoCD instance..."
    oc delete argocd gitops-rhoso1 -n gitops-rhoso1 --ignore-not-found=true --timeout=60s
fi

# Create the ArgoCD instance
echo -e "${BLUE}Step 2: Creating dedicated ArgoCD instance in gitops-rhoso1 namespace...${NC}"
oc apply -f argocd/argocd-rhoso1-instance.yaml

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} ArgoCD instance created"
else
    echo -e "${RED}✗${NC} Failed to create ArgoCD instance"
    exit 1
fi
echo ""

# Wait for ArgoCD to be ready
echo -e "${BLUE}Step 3: Waiting for ArgoCD pods to be ready (this may take 2-3 minutes)...${NC}"

# Wait for namespace to be ready
for i in {1..30}; do
    if oc get namespace gitops-rhoso1 &> /dev/null; then
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

# Wait for pods to start
echo "Waiting for pods to start..."
for i in {1..60}; do
    POD_COUNT=$(oc get pods -n gitops-rhoso1 --no-headers 2>/dev/null | wc -l)
    if [ "$POD_COUNT" -ge 4 ]; then
        break
    fi
    echo -n "."
    sleep 5
done
echo ""

# Wait for pods to be ready
echo "Waiting for pods to be ready..."
oc wait --for=condition=Ready pod --all -n gitops-rhoso1 --timeout=300s 2>/dev/null || {
    echo -e "${YELLOW}⚠ Some pods may still be starting. Current status:${NC}"
    oc get pods -n gitops-rhoso1
    echo ""
}

# Show pod status
echo -e "${BLUE}ArgoCD Pods:${NC}"
oc get pods -n gitops-rhoso1
echo ""

# Apply RBAC
echo -e "${BLUE}Step 4: Configuring RBAC permissions...${NC}"
oc apply -f argocd/argocd-rhoso1-rbac.yaml

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} RBAC configured"
else
    echo -e "${YELLOW}⚠${NC} RBAC configuration may have failed (check manually)"
fi
echo ""

# Label rhoso1 namespace
echo -e "${BLUE}Step 5: Labeling rhoso1 namespace...${NC}"

# Create rhoso1 namespace if it doesn't exist
if ! oc get namespace rhoso1 &> /dev/null; then
    echo "Creating rhoso1 namespace..."
    oc create namespace rhoso1
fi

# Apply the label
oc label namespace rhoso1 \
  argocd.argoproj.io/managed-by=gitops-rhoso1 \
  --overwrite

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓${NC} Namespace rhoso1 labeled with argocd.argoproj.io/managed-by=gitops-rhoso1"
else
    echo -e "${RED}✗${NC} Failed to label namespace"
fi
echo ""

# Get ArgoCD URL and password
echo -e "${BLUE}Step 6: Retrieving ArgoCD access information...${NC}"
echo ""

# Wait for route to be created
for i in {1..30}; do
    if oc get route gitops-rhoso1-server -n gitops-rhoso1 &> /dev/null 2>&1; then
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

if ARGOCD_URL=$(oc get route gitops-rhoso1-server -n gitops-rhoso1 -o jsonpath='{.spec.host}' 2>/dev/null); then
    echo -e "${GREEN}✓${NC} ArgoCD server is accessible"
    echo ""
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}ArgoCD Access Information${NC}"
    echo -e "${BLUE}================================================================${NC}"
    echo ""
    echo -e "${GREEN}URL:${NC} https://${ARGOCD_URL}"
    echo ""
    echo -e "${GREEN}Username:${NC} admin"
    echo ""

    # Get password - try different secret names
    if ARGOCD_PASSWORD=$(oc get secret gitops-rhoso1-cluster -n gitops-rhoso1 -o jsonpath='{.data.admin\.password}' 2>/dev/null | base64 -d); then
        echo -e "${GREEN}Password:${NC} ${ARGOCD_PASSWORD}"
    else
        echo -e "${YELLOW}Password:${NC} Run this command to retrieve it:"
        echo "  oc get secret gitops-rhoso1-cluster -n gitops-rhoso1 -o jsonpath='{.data.admin\.password}' | base64 -d"
    fi
    echo ""
else
    echo -e "${YELLOW}⚠ Could not retrieve ArgoCD route. It may still be initializing.${NC}"
    echo "Run this command to get the URL:"
    echo "  oc get route gitops-rhoso1-server -n gitops-rhoso1"
fi

# Installation summary
echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}Installation Summary${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""
echo -e "${GREEN}✓${NC} Dedicated ArgoCD instance created in gitops-rhoso1 namespace"
echo -e "${GREEN}✓${NC} RBAC permissions configured"
echo -e "${GREEN}✓${NC} Namespace rhoso1 labeled: argocd.argoproj.io/managed-by=gitops-rhoso1"
echo ""

# Show namespace labels
echo -e "${BLUE}Namespace Labels:${NC}"
oc get namespace rhoso1 --show-labels
echo ""

# Next steps
echo -e "${BLUE}Next Steps:${NC}"
echo ""
echo "1. Access ArgoCD UI:"
echo "   Open: https://${ARGOCD_URL}"
echo "   Login with credentials shown above"
echo ""
echo "2. Update the repository URL in the application manifest:"
echo "   Edit: argocd/application-rhoso1.yaml"
echo "   Change: https://github.com/YOUR_USERNAME/YOUR_REPO.git"
echo ""
echo "3. Deploy the RHOSO application:"
echo "   oc apply -f argocd/application-rhoso1.yaml"
echo ""
echo "4. Monitor deployment:"
echo "   oc get application rhoso-nvidia-l4-passthrough -n gitops-rhoso1"
echo "   # or view in ArgoCD UI"
echo ""

# Optional: Install ArgoCD CLI
if ! command -v argocd &> /dev/null; then
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
            echo -e "${GREEN}✓${NC} ArgoCD CLI installed: $(argocd version --client --short 2>/dev/null)"
            echo ""
            echo "Login to ArgoCD:"
            echo "  argocd login ${ARGOCD_URL} --username admin --password '${ARGOCD_PASSWORD}' --insecure"
        else
            echo -e "${RED}✗${NC} Failed to install ArgoCD CLI"
        fi
    else
        echo "Skipping ArgoCD CLI installation."
    fi
fi

echo ""
echo -e "${GREEN}================================================================${NC}"
echo -e "${GREEN}Installation Complete!${NC}"
echo -e "${GREEN}================================================================${NC}"
echo ""
echo "You can now deploy applications to this ArgoCD instance."
echo "The ArgoCD instance is configured to manage the rhoso1 namespace."
