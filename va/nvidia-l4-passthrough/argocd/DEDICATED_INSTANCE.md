# Dedicated ArgoCD Instance for RHOSO

This guide shows how to set up a dedicated ArgoCD instance specifically for managing the RHOSO deployment in the rhoso1 namespace.

## Why a Dedicated Instance?

A dedicated ArgoCD instance provides:

- **Isolation**: Separate ArgoCD for RHOSO resources
- **Custom RBAC**: Fine-grained permissions specific to OpenStack
- **Resource Management**: Better resource allocation and limits
- **Multi-tenancy**: Different teams can manage different ArgoCD instances
- **Custom Health Checks**: OpenStack-specific health checks for CRDs

## Architecture

```
┌─────────────────────────────────────┐
│  gitops-rhoso1 namespace            │
│                                     │
│  ┌─────────────────────────────┐   │
│  │  ArgoCD Instance            │   │
│  │  - Server                   │   │
│  │  - Application Controller   │   │
│  │  - Repo Server              │   │
│  │  - Redis                    │   │
│  └─────────────────────────────┘   │
│                                     │
│  Manages ↓                          │
└─────────────────────────────────────┘
           │
           ↓
┌─────────────────────────────────────┐
│  rhoso1 namespace                   │
│  (labeled: argocd.argoproj.io/      │
│   managed-by=gitops-rhoso1)         │
│                                     │
│  - OpenStackControlPlane            │
│  - Storage Resources                │
│  - Secrets                          │
│  - Jobs                             │
└─────────────────────────────────────┘
```

## Installation

### Prerequisites

1. OpenShift GitOps operator must be installed:
   ```bash
   make install-argocd
   # or
   bash scripts/install-argocd.sh
   ```

2. Verify the operator is ready:
   ```bash
   oc get csv -n openshift-gitops-operator
   ```

### Install Dedicated ArgoCD Instance

#### Option 1: Automated Script (Recommended)

```bash
cd /home/mcarpio/CLAUDE/architecture/va/nvidia-l4-passthrough
bash scripts/install-argocd-rhoso1.sh
```

This script will:
1. Create `gitops-rhoso1` namespace
2. Deploy ArgoCD instance
3. Configure RBAC with OpenStack CRD permissions
4. Label `rhoso1` namespace for management
5. Display access credentials

#### Option 2: Manual Installation

```bash
# 1. Create ArgoCD instance
oc apply -f argocd/argocd-rhoso1-instance.yaml

# 2. Wait for pods to be ready
oc wait --for=condition=Ready pod --all -n gitops-rhoso1 --timeout=300s

# 3. Apply RBAC configuration
oc apply -f argocd/argocd-rhoso1-rbac.yaml

# 4. Label rhoso1 namespace
oc label namespace rhoso1 argocd.argoproj.io/managed-by=gitops-rhoso1
```

## Accessing the ArgoCD Instance

### Get Access Credentials

```bash
# Get ArgoCD URL
ARGOCD_URL=$(oc get route gitops-rhoso1-server -n gitops-rhoso1 -o jsonpath='{.spec.host}')
echo "ArgoCD URL: https://${ARGOCD_URL}"

# Get admin password
ARGOCD_PASSWORD=$(oc get secret gitops-rhoso1-cluster -n gitops-rhoso1 -o jsonpath='{.data.admin\.password}' | base64 -d)
echo "Password: ${ARGOCD_PASSWORD}"
```

**Login:**
- **URL**: (from above)
- **Username**: `admin`
- **Password**: (from above)

### Login via CLI

```bash
argocd login ${ARGOCD_URL} \
  --username admin \
  --password "${ARGOCD_PASSWORD}" \
  --insecure
```

## Deploy RHOSO Application

### Update Application Manifest

Edit `argocd/application-rhoso1.yaml` and update the repository URL:

```yaml
source:
  repoURL: https://github.com/YOUR_USERNAME/YOUR_REPO.git  # UPDATE THIS
```

### Deploy Application

```bash
# Apply the application
oc apply -f argocd/application-rhoso1.yaml

# Verify application is created
oc get application rhoso-nvidia-l4-passthrough -n gitops-rhoso1

# Watch application sync
oc get application rhoso-nvidia-l4-passthrough -n gitops-rhoso1 -w
```

### Monitor via CLI

```bash
# List applications
argocd app list

# Get application details
argocd app get rhoso-nvidia-l4-passthrough

# View sync status
argocd app sync rhoso-nvidia-l4-passthrough

# View application logs
argocd app logs rhoso-nvidia-l4-passthrough
```

## Features of This Instance

### 1. OpenStack CRD Health Checks

Custom health checks for OpenStack resources:

```lua
# OpenStackControlPlane health check
- Checks for "Ready" condition
- Reports Healthy/Degraded/Progressing status
- Shows meaningful messages

# Job health check
- Detects successful completion
- Detects failures
- Shows progress
```

### 2. Resource Customizations

- Ignores status changes in OpenStackControlPlane
- Handles Job completion states
- Proper handling of Secret data changes

### 3. RBAC Permissions

The instance has permissions to manage:
- All OpenStack CRDs (core.openstack.org, network.openstack.org, etc.)
- Kubernetes core resources (Secrets, ConfigMaps, PVs, PVCs)
- Storage resources (StorageClasses)
- Batch resources (Jobs)
- RBAC resources
- Routes

### 4. Sync Waves Support

The application respects sync waves:
- Wave -10: Storage preparation
- Wave -5: PV generation
- Wave -3: Secrets
- Wave -2: NetConfig
- Wave 0: OpenStackControlPlane

## Managing the Instance

### View ArgoCD Resources

```bash
# View ArgoCD pods
oc get pods -n gitops-rhoso1

# View ArgoCD instance
oc get argocd gitops-rhoso1 -n gitops-rhoso1

# View ArgoCD route
oc get route -n gitops-rhoso1
```

### View Managed Resources

```bash
# View applications
oc get application -n gitops-rhoso1

# View application projects
oc get appproject -n gitops-rhoso1

# View managed namespace
oc get namespace rhoso1 --show-labels
```

### Update ArgoCD Configuration

Edit the ArgoCD instance:

```bash
oc edit argocd gitops-rhoso1 -n gitops-rhoso1
```

Or update the manifest and reapply:

```bash
# Edit argocd/argocd-rhoso1-instance.yaml
oc apply -f argocd/argocd-rhoso1-instance.yaml
```

## Troubleshooting

### ArgoCD Pods Not Starting

```bash
# Check events
oc get events -n gitops-rhoso1 --sort-by='.lastTimestamp'

# Check pod logs
oc logs -n gitops-rhoso1 -l app.kubernetes.io/name=gitops-rhoso1-server

# Check ArgoCD instance status
oc get argocd gitops-rhoso1 -n gitops-rhoso1 -o yaml
```

### Application Won't Sync

```bash
# Check application status
oc get application rhoso-nvidia-l4-passthrough -n gitops-rhoso1 -o yaml

# Check application controller logs
oc logs -n gitops-rhoso1 -l app.kubernetes.io/name=gitops-rhoso1-application-controller

# Force sync
argocd app sync rhoso-nvidia-l4-passthrough --force
```

### Permission Issues

```bash
# Verify RBAC is applied
oc get clusterrolebinding gitops-rhoso1-manager-binding

# Check service account
oc get sa -n gitops-rhoso1 | grep gitops-rhoso1

# Verify namespace label
oc get namespace rhoso1 -o jsonpath='{.metadata.labels}'
```

### Cannot Access UI

```bash
# Check route
oc get route gitops-rhoso1-server -n gitops-rhoso1

# Test route
curl -k https://$(oc get route gitops-rhoso1-server -n gitops-rhoso1 -o jsonpath='{.spec.host}')/healthz

# Check if server pod is running
oc get pods -n gitops-rhoso1 -l app.kubernetes.io/name=gitops-rhoso1-server
```

## Cleanup

### Delete Application Only

```bash
oc delete -f argocd/application-rhoso1.yaml
```

### Delete ArgoCD Instance

```bash
# Delete ArgoCD instance (keeps namespace)
oc delete argocd gitops-rhoso1 -n gitops-rhoso1

# Delete RBAC
oc delete -f argocd/argocd-rhoso1-rbac.yaml

# Remove namespace label
oc label namespace rhoso1 argocd.argoproj.io/managed-by-
```

### Complete Cleanup

```bash
# Delete everything
oc delete namespace gitops-rhoso1
oc delete -f argocd/argocd-rhoso1-rbac.yaml
oc label namespace rhoso1 argocd.argoproj.io/managed-by-
```

## Comparison: Shared vs Dedicated Instance

| Feature | Shared (openshift-gitops) | Dedicated (gitops-rhoso1) |
|---------|---------------------------|---------------------------|
| Namespace | openshift-gitops | gitops-rhoso1 |
| Management | System-wide | RHOSO-specific |
| RBAC | Broad permissions | Fine-grained OpenStack |
| Health Checks | Generic | OpenStack CRDs |
| Resource Limits | Shared | Dedicated |
| Isolation | Low | High |
| Multi-tenancy | No | Yes |
| Best For | General use | Production RHOSO |

## Best Practices

1. **Use Dedicated Instance for Production**
   - Better isolation
   - Custom resource limits
   - OpenStack-specific configurations

2. **Monitor Resources**
   - Set appropriate resource limits
   - Monitor pod resource usage
   - Scale if needed

3. **RBAC Management**
   - Review permissions regularly
   - Use least privilege principle
   - Audit access logs

4. **Backup**
   - Backup ArgoCD configuration
   - Backup Application manifests
   - Document customizations

5. **Updates**
   - Keep ArgoCD instance updated
   - Test updates in development first
   - Review release notes

## Advanced Configuration

### Enable Notifications

Edit `argocd-rhoso1-instance.yaml`:

```yaml
notifications:
  enabled: true
```

### Add Custom Health Checks

Add more OpenStack CRDs to `resourceCustomizations`.

### Configure SSO

Enable Dex or OpenShift OAuth for authentication.

### Multi-Cluster Management

Configure ArgoCD to manage resources in multiple clusters.

## References

- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [OpenShift GitOps](https://docs.openshift.com/container-platform/latest/cicd/gitops/)
- [ArgoCD Multi-Tenancy](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#clusters)
- [ArgoCD Resource Hooks](https://argo-cd.readthedocs.io/en/stable/user-guide/resource_hooks/)

## Support

For issues with this dedicated instance:

1. Check logs: `oc logs -n gitops-rhoso1 -l app.kubernetes.io/name=gitops-rhoso1-server`
2. Review events: `oc get events -n gitops-rhoso1`
3. Verify RBAC: `oc get clusterrolebinding gitops-rhoso1-manager-binding`
4. Check namespace label: `oc get namespace rhoso1 --show-labels`

For RHOSO deployment issues, see the main [README.md](../README.md).
