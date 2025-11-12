# RHOSO NVIDIA L4 GitOps Deployment Checklist

Use this checklist to ensure a successful deployment.

## Pre-Deployment Checklist

### Prerequisites

- [ ] OpenShift cluster is running and accessible
- [ ] You have cluster-admin privileges
- [ ] OpenStack operators are installed
  ```bash
  oc get namespace openstack-operators
  oc get deployment -n openstack-operators
  ```
- [ ] OpenShift GitOps operator is installed (for ArgoCD deployment)
  ```bash
  oc get namespace openshift-gitops
  ```
- [ ] Worker nodes have NVIDIA L4 GPUs installed
- [ ] Git repository is accessible from the cluster

### Validation

- [ ] Run prerequisites validation
  ```bash
  cd /home/mcarpio/CLAUDE/architecture/va/nvidia-l4-passthrough
  make prereqs
  ```
- [ ] All checks pass (or warnings are acceptable)

### Configuration

- [ ] Review and update GPU configuration in [base/openstackcontrolplane.yaml](base/openstackcontrolplane.yaml)
  - [ ] Vendor ID is correct (10de for NVIDIA)
  - [ ] Product ID is correct (27b8 for L4)
  - [ ] Alias name is appropriate

- [ ] Review storage configuration
  - [ ] PV count is correct (default: 20)
  - [ ] Storage capacity is appropriate (default: 10Gi)
  - [ ] Storage paths are acceptable (/mnt/openstack/pv{1..20})

- [ ] Review network configuration in [base/netconfig.yaml](base/netconfig.yaml)
  - [ ] CIDR is correct (default: 192.168.122.0/24)
  - [ ] Gateway is correct (default: 192.168.122.1)
  - [ ] Allocation ranges don't conflict

- [ ] **SECURITY**: Update secrets in [base/secrets.yaml](base/secrets.yaml)
  - [ ] Change default passwords (current: 12345678)
  - [ ] Generate new encryption keys
  - [ ] Consider using Sealed Secrets or External Secrets

### Git Repository (for ArgoCD deployment)

- [ ] Update repository URL in [argocd/application.yaml](argocd/application.yaml)
  ```yaml
  source:
    repoURL: https://github.com/YOUR_USERNAME/YOUR_REPO.git  # UPDATE THIS
  ```
- [ ] Commit all changes to Git
  ```bash
  git add .
  git commit -m "Add RHOSO NVIDIA L4 GitOps deployment"
  git push
  ```
- [ ] Verify Git repository is accessible from cluster

## Deployment Checklist

### Option A: Deploy via ArgoCD

- [ ] Validate kustomization
  ```bash
  make validate
  ```

- [ ] Deploy ArgoCD Application
  ```bash
  make argocd-deploy
  ```

- [ ] Monitor ArgoCD sync
  ```bash
  make argocd-status
  # or watch in ArgoCD UI
  ```

- [ ] Wait for all sync waves to complete
  - [ ] Wave -10: Storage preparation
  - [ ] Wave -5: PV generation
  - [ ] Wave -3: Secrets
  - [ ] Wave -2: NetConfig
  - [ ] Wave 0: OpenStackControlPlane

### Option B: Direct Deployment

- [ ] Validate kustomization
  ```bash
  make validate
  ```

- [ ] Preview what will be deployed
  ```bash
  make test
  ```

- [ ] Deploy
  ```bash
  make deploy
  ```

## Post-Deployment Verification

### Check Overall Status

- [ ] Run status check
  ```bash
  make status
  ```

### Verify Storage

- [ ] Storage preparation job completed
  ```bash
  oc get job storage-prep -n rhoso1
  oc logs job/storage-prep -n rhoso1
  ```

- [ ] PV generator job completed
  ```bash
  oc get job pv-generator -n rhoso1
  oc logs job/pv-generator -n rhoso1
  ```

- [ ] PVs are created and available
  ```bash
  oc get pv | grep local-storage
  # Should show 20+ PVs in Available or Bound state
  ```

### Verify OpenStack Control Plane

- [ ] OpenStackControlPlane resource exists
  ```bash
  oc get openstackcontrolplane -n rhoso1
  ```

- [ ] Control plane is Ready
  ```bash
  make describe-controlplane
  # Look for Status: Ready
  ```

- [ ] GPU configuration is present
  ```bash
  make verify-gpu-config
  # Should show the PCI alias configuration
  ```

### Verify Services

- [ ] All pods are running
  ```bash
  oc get pods -n rhoso1
  # All pods should be Running or Completed
  ```

- [ ] Database is ready
  ```bash
  oc get pods -n rhoso1 | grep galera
  # Should show 1 galera pod running
  ```

- [ ] RabbitMQ is ready
  ```bash
  oc get pods -n rhoso1 | grep rabbitmq
  # Should show rabbitmq pods running
  ```

- [ ] Keystone is ready
  ```bash
  oc get pods -n rhoso1 | grep keystone
  # Should show keystone pods running
  ```

- [ ] Nova is ready and has GPU config
  ```bash
  oc get pods -n rhoso1 | grep nova-api
  make logs-nova | grep -i pci
  ```

- [ ] Neutron is ready
  ```bash
  oc get pods -n rhoso1 | grep neutron
  ```

- [ ] Horizon is ready
  ```bash
  oc get pods -n rhoso1 | grep horizon
  ```

### Access OpenStack

- [ ] Get service routes
  ```bash
  make get-routes
  ```

- [ ] Get admin password
  ```bash
  make get-password
  ```

- [ ] Access Horizon dashboard
  ```bash
  # Get URL from routes
  HORIZON_URL=$(oc get route horizon -n rhoso1 -o jsonpath='{.spec.host}')
  echo "https://${HORIZON_URL}"
  # Login with admin / <password from make get-password>
  ```

- [ ] Verify you can login to Horizon

## Troubleshooting Checklist

If deployment fails, check:

- [ ] ArgoCD application status
  ```bash
  oc describe application rhoso-nvidia-l4-passthrough -n openshift-gitops
  ```

- [ ] Job logs
  ```bash
  make logs-storage-prep
  make logs-pv-generator
  ```

- [ ] Operator logs
  ```bash
  oc logs -n openstack-operators deployment/openstack-operator-controller-manager --tail=100
  ```

- [ ] Control plane events
  ```bash
  oc describe openstackcontrolplane openstack-galera -n rhoso1 | grep -A 50 Events
  ```

- [ ] Pod events
  ```bash
  oc get events -n rhoso1 --sort-by='.lastTimestamp'
  ```

## Cleanup Checklist (if needed)

- [ ] Delete ArgoCD Application (if used)
  ```bash
  make argocd-delete
  ```

- [ ] Delete resources
  ```bash
  make delete
  ```

- [ ] Delete PVs
  ```bash
  oc get pv | grep local-storage | awk '{print $1}' | xargs oc delete pv
  ```

- [ ] Verify namespace is deleted
  ```bash
  oc get namespace rhoso1
  # Should show NotFound
  ```

## Next Steps Checklist

After successful deployment:

- [ ] Review [DEPLOYMENT_SUMMARY.md](DEPLOYMENT_SUMMARY.md) for next steps
- [ ] Configure EDPM nodes with GPU passthrough
- [ ] Create Nova flavors with GPU resources
- [ ] Test GPU passthrough with a VM instance
- [ ] Set up monitoring and logging
- [ ] Configure backups for persistent data
- [ ] Review security settings and harden for production
- [ ] Document any customizations made

## Sign-off

Deployment completed by: ________________

Date: ________________

Deployment method: [ ] ArgoCD  [ ] Direct

Issues encountered: ________________

Notes: ________________

---

**Reference Documents:**
- [README.md](README.md) - Full documentation
- [QUICKSTART.md](QUICKSTART.md) - Quick start guide
- [DEPLOYMENT_SUMMARY.md](DEPLOYMENT_SUMMARY.md) - Deployment details
- [values.yaml](values.yaml) - Configuration reference
