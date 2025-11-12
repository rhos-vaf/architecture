# ArgoCD Installation Guide

This guide shows how to install ArgoCD on OpenShift for the RHOSO NVIDIA L4 GitOps deployment.

## Prerequisites

- OpenShift cluster running (CRC or full cluster)
- Cluster admin access
- `oc` CLI configured and logged in

## Installation Methods

### Method 1: OpenShift GitOps Operator (Recommended)

The OpenShift GitOps operator provides a supported ArgoCD distribution integrated with OpenShift.

#### Install via CLI

```bash
# Create the operator subscription
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
```

#### Wait for Installation

```bash
# Wait for operator to be ready (2-3 minutes)
oc wait --for=condition=Ready pod -l control-plane=gitops-operator \
  -n openshift-gitops-operator --timeout=300s

# Verify operator is installed
oc get csv -n openshift-gitops-operator
```

#### Verify Default ArgoCD Instance

The operator automatically creates a default ArgoCD instance:

```bash
# Check ArgoCD pods
oc get pods -n openshift-gitops

# Expected output:
# NAME                                                    READY   STATUS
# openshift-gitops-application-controller-0               1/1     Running
# openshift-gitops-applicationset-controller-...          1/1     Running
# openshift-gitops-redis-...                              1/1     Running
# openshift-gitops-repo-server-...                        1/1     Running
# openshift-gitops-server-...                             1/1     Running
```

#### Access ArgoCD UI

```bash
# Get the ArgoCD URL
ARGOCD_URL=$(oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}')
echo "ArgoCD URL: https://${ARGOCD_URL}"

# Get the admin password
ARGOCD_PASSWORD=$(oc extract secret/openshift-gitops-cluster -n openshift-gitops --to=- 2>/dev/null)
echo "Admin password: ${ARGOCD_PASSWORD}"

# Or view the full secret
oc get secret openshift-gitops-cluster -n openshift-gitops -o jsonpath='{.data.admin\.password}' | base64 -d
echo
```

Login credentials:
- **Username**: `admin`
- **Password**: (from command above)

#### Install ArgoCD CLI (Optional)

```bash
# Download and install ArgoCD CLI
VERSION=$(curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
curl -sSL -o /tmp/argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/download/$VERSION/argocd-linux-amd64
sudo install -m 555 /tmp/argocd-linux-amd64 /usr/local/bin/argocd
rm /tmp/argocd-linux-amd64

# Verify installation
argocd version --client

# Login via CLI
argocd login $ARGOCD_URL --username admin --password $ARGOCD_PASSWORD --insecure
```

### Method 2: Custom ArgoCD Instance

If you need a separate ArgoCD instance (e.g., for specific projects):

```bash
# First, install the OpenShift GitOps operator (Method 1)
# Then create a custom instance

oc apply -f argocd/argocd-instance.yaml
```

This creates a custom ArgoCD in the `argocd` namespace.

### Method 3: Upstream ArgoCD (Not Recommended)

For upstream ArgoCD installation (not supported by Red Hat):

```bash
# Create namespace
oc new-project argocd

# Install ArgoCD
oc apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Expose via route
oc create route passthrough argocd-server --service=argocd-server --port=https -n argocd

# Get initial password
oc get secret argocd-initial-admin-secret -n argocd -o jsonpath='{.data.password}' | base64 -d
echo
```

## Post-Installation Configuration

### Grant ArgoCD Access to Deploy to rhoso1 Namespace

```bash
# Allow ArgoCD to manage resources in rhoso1 namespace
oc adm policy add-role-to-user admin system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller -n rhoso1

# Or for cluster-wide access (use with caution)
oc adm policy add-cluster-role-to-user cluster-admin system:serviceaccount:openshift-gitops:openshift-gitops-argocd-application-controller
```

### Configure Git Repository

If your Git repository is private, create a secret:

```bash
# For HTTPS with username/password
oc create secret generic git-credentials \
  -n openshift-gitops \
  --from-literal=username=your-username \
  --from-literal=password=your-token

# For SSH
oc create secret generic git-ssh-credentials \
  -n openshift-gitops \
  --from-file=sshPrivateKey=/path/to/id_rsa

# Label the secret so ArgoCD picks it up
oc label secret git-credentials -n openshift-gitops \
  argocd.argoproj.io/secret-type=repository
```

### Add Repository to ArgoCD via CLI

```bash
# Add HTTPS repository
argocd repo add https://github.com/YOUR_USERNAME/YOUR_REPO.git \
  --username your-username \
  --password your-token

# Add SSH repository
argocd repo add git@github.com:YOUR_USERNAME/YOUR_REPO.git \
  --ssh-private-key-path /path/to/id_rsa
```

## Deploy RHOSO Application

Once ArgoCD is installed:

```bash
# 1. Update the repository URL in the application manifest
cd /home/mcarpio/CLAUDE/architecture/va/nvidia-l4-passthrough

# Edit argocd/application.yaml and set your repo URL
REPO_URL="https://github.com/YOUR_USERNAME/YOUR_REPO.git"
sed -i "s|https://github.com/YOUR_USERNAME/YOUR_REPO.git|${REPO_URL}|" argocd/application.yaml

# 2. Commit and push to your Git repository
git add .
git commit -m "Add RHOSO NVIDIA L4 GitOps deployment"
git push

# 3. Deploy the application
oc apply -f argocd/application.yaml

# 4. Monitor via CLI
argocd app get rhoso-nvidia-l4-passthrough

# 5. Or watch in the UI
echo "ArgoCD UI: https://${ARGOCD_URL}"
```

## Verification

### Check ArgoCD is Working

```bash
# Check operator
oc get csv -n openshift-gitops-operator

# Check ArgoCD pods
oc get pods -n openshift-gitops

# Check ArgoCD server
oc get route openshift-gitops-server -n openshift-gitops

# Test ArgoCD API
curl -k https://$ARGOCD_URL/api/version
```

### Check Application Deployment

```bash
# List applications
argocd app list

# Get application status
argocd app get rhoso-nvidia-l4-passthrough

# View application in UI
# Navigate to: https://$ARGOCD_URL/applications/rhoso-nvidia-l4-passthrough
```

## Troubleshooting

### Operator Not Installing

```bash
# Check operator subscription
oc get subscription openshift-gitops-operator -n openshift-gitops-operator

# Check install plan
oc get installplan -n openshift-gitops-operator

# Check operator logs
oc logs -n openshift-gitops-operator -l control-plane=gitops-operator
```

### ArgoCD Pods Not Starting

```bash
# Check events
oc get events -n openshift-gitops --sort-by='.lastTimestamp'

# Check pod status
oc describe pod -n openshift-gitops -l app.kubernetes.io/name=openshift-gitops-server

# Check logs
oc logs -n openshift-gitops -l app.kubernetes.io/name=openshift-gitops-server
```

### Cannot Access ArgoCD UI

```bash
# Check route
oc get route -n openshift-gitops

# Check if route is working
curl -k https://$ARGOCD_URL/healthz

# Check firewall/network
oc get route openshift-gitops-server -n openshift-gitops -o yaml
```

### Application Won't Sync

```bash
# Check application status
oc get application rhoso-nvidia-l4-passthrough -n openshift-gitops -o yaml

# Check ArgoCD controller logs
oc logs -n openshift-gitops -l app.kubernetes.io/name=openshift-gitops-application-controller

# Force sync
argocd app sync rhoso-nvidia-l4-passthrough --force
```

## Uninstallation

### Remove Application

```bash
oc delete -f argocd/application.yaml
```

### Remove Custom ArgoCD Instance

```bash
oc delete -f argocd/argocd-instance.yaml
```

### Remove OpenShift GitOps Operator

```bash
# Delete the operator subscription
oc delete subscription openshift-gitops-operator -n openshift-gitops-operator

# Delete the operator namespace
oc delete namespace openshift-gitops-operator

# Delete the default ArgoCD instance
oc delete namespace openshift-gitops
```

## Quick Reference

### Common Commands

```bash
# Get ArgoCD URL
oc get route openshift-gitops-server -n openshift-gitops -o jsonpath='{.spec.host}'

# Get admin password
oc extract secret/openshift-gitops-cluster -n openshift-gitops --to=-

# List applications
argocd app list

# Sync application
argocd app sync rhoso-nvidia-l4-passthrough

# View application logs
argocd app logs rhoso-nvidia-l4-passthrough

# Delete application
argocd app delete rhoso-nvidia-l4-passthrough
```

### Useful Links

- [OpenShift GitOps Documentation](https://docs.openshift.com/container-platform/latest/cicd/gitops/understanding-openshift-gitops.html)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [ArgoCD Getting Started](https://argo-cd.readthedocs.io/en/stable/getting_started/)

## Next Steps

After ArgoCD is installed:
1. ✅ Configure Git repository access
2. ✅ Grant necessary RBAC permissions
3. ✅ Deploy the RHOSO application using `argocd/application.yaml`
4. ✅ Monitor deployment in ArgoCD UI

For the RHOSO deployment, return to the [QUICKSTART.md](../QUICKSTART.md) guide.
