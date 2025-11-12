# Quick Start Guide - RHOSO with NVIDIA L4 GitOps

This guide will get you up and running quickly with the GitOps deployment.

## Prerequisites Checklist

- [ ] OpenShift cluster is running
- [ ] OpenStack operators are installed (`make openstack` from install_yamls)
- [ ] OpenShift GitOps operator is installed
- [ ] Worker nodes have NVIDIA L4 GPUs
- [ ] Git repository is accessible from the cluster

## 5-Minute Deployment

### Step 1: Update Git Repository URL

Edit `argocd/application.yaml` and update the repository URL:

```bash
cd /home/mcarpio/CLAUDE/architecture/va/nvidia-l4-passthrough

# Edit the file and replace YOUR_USERNAME/YOUR_REPO
vi argocd/application.yaml
```

Or use sed:
```bash
REPO_URL="https://github.com/YOUR_USERNAME/YOUR_REPO.git"
sed -i "s|https://github.com/YOUR_USERNAME/YOUR_REPO.git|${REPO_URL}|" argocd/application.yaml
```

### Step 2: Commit and Push to Git

```bash
cd /home/mcarpio/CLAUDE
git add architecture/va/nvidia-l4-passthrough/
git commit -m "Add RHOSO NVIDIA L4 GitOps deployment"
git push origin main  # or your branch name
```

### Step 3: Deploy via ArgoCD

```bash
cd architecture/va/nvidia-l4-passthrough
oc apply -f argocd/application.yaml
```

### Step 4: Monitor Deployment

```bash
# Watch the ArgoCD application
oc get application rhoso-nvidia-l4-passthrough -n openshift-gitops -w

# Or use the Makefile
make argocd-status

# Watch pods
make watch-pods
```

### Step 5: Verify Deployment

```bash
# Check overall status
make status

# Verify GPU configuration
make verify-gpu-config

# Get OpenStack admin password
make get-password
```

## Alternative: Direct Deployment (Without Git)

If you want to deploy directly without pushing to Git:

```bash
cd /home/mcarpio/CLAUDE/architecture/va/nvidia-l4-passthrough

# Test the configuration
make test

# Deploy
make deploy

# Check status
make status
```

## What Gets Deployed?

The deployment will create:

1. **Namespace**: `rhoso1`
2. **Storage**:
   - StorageClass: `local-storage`
   - 20 PersistentVolumes per worker node
   - Directories on nodes: `/mnt/openstack/pv{1..20}`
3. **Secrets**: OpenStack service passwords
4. **NetConfig**: Network configuration for control plane
5. **OpenStackControlPlane**: Full OpenStack deployment with:
   - Galera (MySQL)
   - RabbitMQ
   - Keystone
   - Glance
   - Nova (with NVIDIA L4 GPU config)
   - Neutron/OVN
   - Cinder
   - Horizon

## Accessing OpenStack

### Get Admin Password

```bash
make get-password
```

### Get Horizon URL

```bash
make get-routes
```

Look for the `horizon` route.

### Access Horizon Dashboard

```bash
# Get the route
HORIZON_URL=$(oc get route horizon -n rhoso1 -o jsonpath='{.spec.host}')
echo "https://${HORIZON_URL}"

# Get admin password
ADMIN_PASS=$(oc get secret osp-secret -n rhoso1 -o jsonpath='{.data.AdminPassword}' | base64 -d)
echo "Password: ${ADMIN_PASS}"
```

Open the URL in a browser and login with:
- **Username**: `admin`
- **Password**: `<password from above>`

## Troubleshooting

### Deployment Stuck?

Check the sync waves are completing in order:

```bash
# Check jobs
oc get jobs -n rhoso1

# View job logs
make logs-storage-prep
make logs-pv-generator

# Check control plane
make describe-controlplane
```

### PVs Not Binding?

```bash
# Check PVs exist
oc get pv | grep local-storage

# Check worker nodes
oc get nodes -l node-role.kubernetes.io/worker

# Clean released PVs
make clean-pvs
```

### ArgoCD Application Not Syncing?

```bash
# Check application details
oc describe application rhoso-nvidia-l4-passthrough -n openshift-gitops

# Force sync
make argocd-sync

# Delete and recreate
make argocd-delete
make argocd-deploy
```

### Services Not Starting?

```bash
# Check pods
oc get pods -n rhoso1

# Check specific service (example: Nova)
make logs-nova

# Check operator logs
oc logs -n openstack-operators deployment/openstack-operator-controller-manager --tail=100
```

## Cleanup

### Remove Everything

```bash
# If deployed via ArgoCD
make argocd-delete

# If deployed directly
make delete

# Also delete PVs
oc get pv | grep local-storage | awk '{print $1}' | xargs oc delete pv
```

## Next Steps

1. **Configure Compute Nodes**: Deploy EDPM nodes with GPU passthrough
2. **Create Flavors**: Create Nova flavors with GPU resources
3. **Test GPU Instances**: Launch VMs with GPU passthrough
4. **Monitor**: Set up monitoring for OpenStack services

## Useful Makefile Commands

```bash
make help              # Show all available commands
make validate          # Validate kustomization
make test              # Preview what will be deployed
make deploy            # Direct deployment
make status            # Check deployment status
make watch-pods        # Watch pods in real-time
make get-routes        # Get all OpenStack routes
make get-password      # Get admin password
make verify-gpu-config # Verify GPU configuration
```

## Documentation

- [Full README](README.md) - Complete documentation
- [RHOSO Docs](https://access.redhat.com/documentation/en-us/red_hat_openstack_services_on_openshift)
- [ArgoCD Docs](https://argo-cd.readthedocs.io/)

## Support

For issues:
1. Check logs with `make logs-*` commands
2. Review the [README](README.md) troubleshooting section
3. Check OpenStack operator logs
4. Review ArgoCD application events
