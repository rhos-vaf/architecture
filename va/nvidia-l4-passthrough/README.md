# RHOSO with NVIDIA L4 GPU Passthrough - GitOps Deployment

This directory contains the GitOps/ArgoCD configuration for deploying Red Hat OpenStack Services on OpenShift (RHOSO) with NVIDIA L4 GPU passthrough support.

## Overview

This deployment replaces the manual `make` commands with a declarative GitOps approach using Kustomize and ArgoCD. It provides the same functionality as:

```bash
NETWORK_ISOLATION=false NAMESPACE=rhoso1 PV_NUM=20 make input crc_storage openstack_deploy
oc patch openstackcontrolplane openstack-galera -n rhoso1 \
  --type=json \
  -p='[{
    "op": "replace",
    "path": "/spec/nova/template/apiServiceTemplate/customServiceConfig",
    "value": "[pci]\nalias = { \"vendor_id\":\"10de\", \"product_id\":\"27b8\", \"device_type\":\"type-PCI\", \"name\":\"nvidia\", \"numa_policy\":\"preferred\" }\n"
  }]'
```

## Prerequisites

- OpenShift cluster with:
  - OpenStack operators installed
  - ArgoCD/OpenShift GitOps operator installed
  - Worker nodes with NVIDIA L4 GPUs
- Completed these steps:
  ```bash
  cd install_yamls/devsetup
  CRC_VERSION=2.41.0 PULL_SECRET=~/.config/openstack/pull-secret.txt CPUS=24 MEMORY=65536 DISK=200 make crc
  make crc_attach_default_interface
  cd ..
  make crc_storage
  make input
  make openstack
  make openstack_init
  ```

## Directory Structure

```
architecture/va/nvidia-l4-passthrough/
├── README.md                           # This file
├── base/                              # Base manifests
│   ├── kustomization.yaml            # Base kustomization
│   ├── namespace.yaml                # rhoso1 namespace
│   ├── storage.yaml                  # StorageClass definition
│   ├── storage-prep-job.yaml         # PreSync hook to create dirs on nodes
│   ├── pv-generator.yaml             # PreSync hook to generate 20 PVs
│   ├── secrets.yaml                  # OpenStack secrets
│   └── openstackcontrolplane.yaml    # OpenStack control plane with GPU config
├── overlays/
│   └── rhoso1/                       # Environment-specific overlay
│       └── kustomization.yaml        # Overlay customizations
└── argocd/
    └── application.yaml              # ArgoCD Application manifest
```

## Component Details

### Sync Waves

The deployment uses ArgoCD sync waves for proper ordering:

1. **Wave -10**: Storage preparation (creates directories on worker nodes)
2. **Wave -5**: PV generation (creates 20 PersistentVolumes)
3. **Wave -3**: Secrets (osp-secret, libvirt-secret, etc.)
4. **Wave 0**: OpenStackControlPlane (main deployment)

### Storage Configuration

- **StorageClass**: `local-storage` with WaitForFirstConsumer binding
- **PVs**: 20 PersistentVolumes per worker node at `/mnt/openstack/pv{1..20}`
- **Capacity**: 10Gi per PV
- **Access Modes**: ReadWriteOnce, ReadWriteMany, ReadOnlyMany

### NVIDIA L4 GPU Configuration

The Nova API service is configured with PCI alias for NVIDIA L4:

```yaml
nova:
  template:
    apiServiceTemplate:
      customServiceConfig: |
        [pci]
        alias = { "vendor_id":"10de", "product_id":"27b8", "device_type":"type-PCI", "name":"nvidia", "numa_policy":"preferred" }
```

- **Vendor ID**: 10de (NVIDIA)
- **Product ID**: 27b8 (L4)
- **Alias Name**: nvidia
- **NUMA Policy**: preferred

## Deployment Instructions

### Option 1: Deploy via ArgoCD UI

1. Login to ArgoCD:
   ```bash
   oc get route openshift-gitops-server -n openshift-gitops
   ```

2. Update the repository URL in [argocd/application.yaml](argocd/application.yaml):
   ```yaml
   source:
     repoURL: https://github.com/YOUR_USERNAME/YOUR_REPO.git
   ```

3. Apply the Application:
   ```bash
   oc apply -f argocd/application.yaml
   ```

4. Monitor the deployment in the ArgoCD UI

### Option 2: Deploy via kubectl/oc

1. Test the kustomization:
   ```bash
   oc kustomize overlays/rhoso1
   ```

2. Apply directly:
   ```bash
   oc apply -k overlays/rhoso1
   ```

### Option 3: Manual Application Creation

1. From the ArgoCD UI, click "New App"
2. Configure:
   - **Application Name**: rhoso-nvidia-l4-passthrough
   - **Project**: default
   - **Sync Policy**: Automatic
   - **Repository URL**: Your Git repository
   - **Path**: architecture/va/nvidia-l4-passthrough/overlays/rhoso1
   - **Cluster**: in-cluster
   - **Namespace**: rhoso1

## Verification

### Check ArgoCD Application Status

```bash
oc get application rhoso-nvidia-l4-passthrough -n openshift-gitops
```

### Check OpenStack Control Plane

```bash
oc get openstackcontrolplane -n rhoso1
oc describe openstackcontrolplane openstack-galera -n rhoso1
```

### Verify Nova PCI Configuration

```bash
oc get openstackcontrolplane openstack-galera -n rhoso1 -o yaml | grep -A 5 "customServiceConfig"
```

### Check PVs

```bash
oc get pv | grep local-storage
```

### Check Storage Preparation

```bash
oc get job -n rhoso1
oc logs job/storage-prep -n rhoso1
oc logs job/pv-generator -n rhoso1
```

## Customization

### Modify GPU Configuration

Edit [base/openstackcontrolplane.yaml](base/openstackcontrolplane.yaml):

```yaml
nova:
  template:
    apiServiceTemplate:
      customServiceConfig: |
        [pci]
        alias = { "vendor_id":"YOUR_VENDOR", "product_id":"YOUR_PRODUCT", "device_type":"type-PCI", "name":"YOUR_NAME", "numa_policy":"preferred" }
```

### Change Number of PVs

Edit [base/pv-generator.yaml](base/pv-generator.yaml):

```yaml
env:
- name: PV_NUM
  value: "30"  # Change from 20 to your desired number
```

### Adjust Replicas

Create a patch in [overlays/rhoso1/kustomization.yaml](overlays/rhoso1/kustomization.yaml):

```yaml
patches:
  - target:
      kind: OpenStackControlPlane
      name: openstack-galera
    patch: |-
      - op: replace
        path: /spec/nova/template/apiServiceTemplate/replicas
        value: 3
```

### Enable Additional Services

Edit [base/openstackcontrolplane.yaml](base/openstackcontrolplane.yaml) and set `enabled: true` for desired services:

```yaml
heat:
  enabled: true
  template:
    # ... configuration
```

## Troubleshooting

### PV Creation Fails

Check the pv-generator job logs:
```bash
oc logs job/pv-generator -n rhoso1
```

Verify worker nodes are labeled:
```bash
oc get nodes -l node-role.kubernetes.io/worker
```

### Storage Directories Not Created

Check the storage-prep job:
```bash
oc logs job/storage-prep -n rhoso1
oc get job storage-prep -n rhoso1 -o yaml
```

### OpenStackControlPlane Not Ready

Check the status:
```bash
oc describe openstackcontrolplane openstack-galera -n rhoso1
oc get pods -n rhoso1
```

Check operator logs:
```bash
oc logs -n openstack-operators deployment/openstack-operator-controller-manager
```

### ArgoCD Sync Issues

View application status:
```bash
oc get application rhoso-nvidia-l4-passthrough -n openshift-gitops -o yaml
```

Check sync operation:
```bash
argocd app get rhoso-nvidia-l4-passthrough
argocd app sync rhoso-nvidia-l4-passthrough --force
```

## Network Isolation

This deployment uses `NETWORK_ISOLATION=false` configuration. For production deployments with network isolation, you'll need to:

1. Add NetConfig and NetAttachDef resources
2. Update OpenStackControlPlane with network attachments
3. Configure OVN nicMappings appropriately

## Security Considerations

⚠️ **Important**: The secrets in [base/secrets.yaml](base/secrets.yaml) use default passwords. For production:

1. Use proper secret management (Sealed Secrets, External Secrets Operator, Vault)
2. Generate strong, unique passwords
3. Rotate secrets regularly
4. Consider using Kustomize secretGenerator with external sources

## References

- [RHOSO Documentation](https://access.redhat.com/documentation/en-us/red_hat_openstack_services_on_openshift)
- [OpenStack Operator](https://github.com/openstack-k8s-operators/openstack-operator)
- [ArgoCD Documentation](https://argo-cd.readthedocs.io/)
- [Kustomize Documentation](https://kustomize.io/)

## Contributing

To modify this deployment:

1. Make changes in your branch
2. Test with `oc kustomize overlays/rhoso1`
3. Commit and push to your repository
4. ArgoCD will automatically sync (if auto-sync is enabled)

## License

This configuration follows the same license as the install_yamls repository.
