# Quick Start - Dedicated ArgoCD Instance

This guide shows you how to quickly deploy RHOSO with a dedicated ArgoCD instance.

## What You'll Get

A dedicated ArgoCD instance in the `gitops-rhoso1` namespace that:
- Manages only the `rhoso1` namespace
- Has custom OpenStack CRD health checks
- Has fine-grained RBAC for OpenStack resources
- Is isolated from other ArgoCD instances

## Prerequisites

- OpenShift cluster running
- Logged in with `oc` CLI as cluster-admin
- Git repository with this code

## Quick Installation (5 Steps)

### Step 1: Install OpenShift GitOps Operator

```bash
cd /home/mcarpio/CLAUDE/architecture/va/nvidia-l4-passthrough
make install-argocd
```

Wait for completion (~2-3 minutes).

### Step 2: Install Dedicated ArgoCD Instance

```bash
make install-argocd-rhoso1
```

This will:
- Create `gitops-rhoso1` namespace
- Deploy ArgoCD instance
- Configure RBAC
- Label `rhoso1` namespace with `argocd.argoproj.io/managed-by=gitops-rhoso1`
- Display access credentials

**Save the URL and password shown!**

### Step 3: Update Git Repository URL

Edit `argocd/application-rhoso1.yaml`:

```bash
# Option 1: Edit manually
vim argocd/application-rhoso1.yaml

# Option 2: Use sed
REPO_URL="https://github.com/YOUR_USERNAME/YOUR_REPO.git"
sed -i "s|https://github.com/YOUR_USERNAME/YOUR_REPO.git|${REPO_URL}|" argocd/application-rhoso1.yaml
```

### Step 4: Commit and Push to Git

```bash
git add .
git commit -m "Add RHOSO NVIDIA L4 GitOps deployment"
git push
```

### Step 5: Deploy RHOSO Application

```bash
make argocd-deploy-rhoso1
```

## Monitor Deployment

### Via Makefile

```bash
# Check application status
make argocd-status-rhoso1

# Check deployment status
make status

# Watch pods
make watch-pods
```

### Via ArgoCD UI

Access the ArgoCD UI with the credentials from Step 2:

```bash
# Get URL and password again if needed
oc get route gitops-rhoso1-server -n gitops-rhoso1 -o jsonpath='{.spec.host}'
oc get secret gitops-rhoso1-cluster -n gitops-rhoso1 -o jsonpath='{.data.admin\.password}' | base64 -d
```

Login and view the `rhoso-nvidia-l4-passthrough` application.

### Via CLI

```bash
# Install ArgoCD CLI (if not already)
# (will be prompted during install-argocd-rhoso1)

# Get ArgoCD URL
ARGOCD_URL=$(oc get route gitops-rhoso1-server -n gitops-rhoso1 -o jsonpath='{.spec.host}')

# Get password
ARGOCD_PASSWORD=$(oc get secret gitops-rhoso1-cluster -n gitops-rhoso1 -o jsonpath='{.data.admin\.password}' | base64 -d)

# Login
argocd login ${ARGOCD_URL} --username admin --password "${ARGOCD_PASSWORD}" --insecure

# View application
argocd app get rhoso-nvidia-l4-passthrough

# Watch sync
argocd app sync rhoso-nvidia-l4-passthrough --grpc-web
```

## Verify Deployment

### Check Sync Waves Complete

```bash
# Wave -10: Storage preparation
oc get job storage-prep -n rhoso1

# Wave -5: PV generation
oc get job pv-generator -n rhoso1
oc get pv | grep local-storage

# Wave -3: Secrets
oc get secret osp-secret -n rhoso1

# Wave -2: NetConfig
oc get netconfig -n rhoso1

# Wave 0: OpenStackControlPlane
oc get openstackcontrolplane -n rhoso1
```

### Check OpenStack is Ready

```bash
# Overall status
make status

# Control plane status
make describe-controlplane

# GPU configuration
make verify-gpu-config

# Get admin password
make get-password

# Get routes
make get-routes
```

## Access OpenStack

### Horizon Dashboard

```bash
# Get Horizon URL
HORIZON_URL=$(oc get route horizon -n rhoso1 -o jsonpath='{.spec.host}')
echo "Horizon: https://${HORIZON_URL}"

# Get admin password
ADMIN_PASS=$(oc get secret osp-secret -n rhoso1 -o jsonpath='{.data.AdminPassword}' | base64 -d)
echo "Password: ${ADMIN_PASS}"
```

Open in browser:
- **URL**: https://${HORIZON_URL}
- **Username**: admin
- **Password**: ${ADMIN_PASS}

## Key Differences from Shared Instance

| Command | Shared Instance | Dedicated Instance |
|---------|----------------|-------------------|
| Install | `make install-argocd` | `make install-argocd-rhoso1` |
| Deploy App | `make argocd-deploy` | `make argocd-deploy-rhoso1` |
| Status | `make argocd-status` | `make argocd-status-rhoso1` |
| Sync | `make argocd-sync` | `make argocd-sync-rhoso1` |
| Delete App | `make argocd-delete` | `make argocd-delete-rhoso1` |
| Namespace | `openshift-gitops` | `gitops-rhoso1` |
| Manifest | `argocd/application.yaml` | `argocd/application-rhoso1.yaml` |

## Verify Namespace Label

The rhoso1 namespace should be labeled for management:

```bash
oc get namespace rhoso1 --show-labels

# Should show:
# argocd.argoproj.io/managed-by=gitops-rhoso1
```

This label was set automatically by the installation script.

## Troubleshooting

### ArgoCD Not Installed

```bash
# Verify operator
oc get csv -n openshift-gitops-operator

# If not installed
make install-argocd
```

### Dedicated Instance Not Created

```bash
# Check if it exists
oc get argocd gitops-rhoso1 -n gitops-rhoso1

# If not, run again
make install-argocd-rhoso1
```

### Application Won't Sync

```bash
# Check application
oc get application rhoso-nvidia-l4-passthrough -n gitops-rhoso1 -o yaml

# Check logs
oc logs -n gitops-rhoso1 -l app.kubernetes.io/name=gitops-rhoso1-application-controller

# Force sync
make argocd-sync-rhoso1
```

### Permission Issues

```bash
# Verify RBAC
oc get clusterrolebinding gitops-rhoso1-manager-binding

# Verify label
oc get namespace rhoso1 -o jsonpath='{.metadata.labels}'

# Re-apply RBAC
oc apply -f argocd/argocd-rhoso1-rbac.yaml

# Re-label namespace
oc label namespace rhoso1 argocd.argoproj.io/managed-by=gitops-rhoso1 --overwrite
```

## Cleanup

### Remove Application Only

```bash
make argocd-delete-rhoso1
```

### Remove Everything (including ArgoCD instance)

```bash
# Delete application
make argocd-delete-rhoso1

# Delete ArgoCD instance
oc delete argocd gitops-rhoso1 -n gitops-rhoso1

# Delete namespace
oc delete namespace gitops-rhoso1

# Remove RBAC
oc delete -f argocd/argocd-rhoso1-rbac.yaml

# Remove label
oc label namespace rhoso1 argocd.argoproj.io/managed-by-
```

## All Available Commands

View all commands:

```bash
make help
```

### ArgoCD Commands (Dedicated Instance)

```bash
make install-argocd-rhoso1   # Install dedicated ArgoCD instance
make argocd-deploy-rhoso1    # Deploy RHOSO application
make argocd-status-rhoso1    # Check application status
make argocd-sync-rhoso1      # Force sync
make argocd-delete-rhoso1    # Delete application
```

## Next Steps

After successful deployment:

1. ✅ Verify all components are healthy
2. ✅ Access Horizon dashboard
3. ✅ Configure EDPM nodes with GPU passthrough
4. ✅ Create Nova flavors with GPU resources
5. ✅ Test VM instances with GPU

## Resources

- [Full README](README.md) - Complete documentation
- [Dedicated Instance Guide](argocd/DEDICATED_INSTANCE.md) - Detailed guide
- [ArgoCD Install Guide](argocd/ARGOCD_INSTALL.md) - Installation details
- [Deployment Summary](DEPLOYMENT_SUMMARY.md) - What gets deployed

---

**Quick Summary:**

```bash
# 1. Install operator and dedicated instance
make install-argocd
make install-argocd-rhoso1

# 2. Update Git repo URL in argocd/application-rhoso1.yaml

# 3. Push to Git
git add . && git commit -m "Add RHOSO" && git push

# 4. Deploy
make argocd-deploy-rhoso1

# 5. Monitor
make status
```

That's it! 🚀
