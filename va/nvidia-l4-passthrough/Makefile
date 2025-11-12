.PHONY: help deploy delete test validate prereqs install-argocd install-argocd-rhoso1 argocd-deploy argocd-deploy-rhoso1 argocd-delete argocd-delete-rhoso1 argocd-status argocd-status-rhoso1 argocd-sync argocd-sync-rhoso1 status logs

NAMESPACE ?= rhoso1
OVERLAY ?= overlays/rhoso1
ARGOCD_NAMESPACE ?= openshift-gitops
ARGOCD_RHOSO1_NAMESPACE ?= gitops-rhoso1

help: ## Display this help message
	@echo "RHOSO NVIDIA L4 Passthrough GitOps Deployment"
	@echo ""
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

prereqs: ## Validate prerequisites (recommended before deployment)
	@bash scripts/validate-prerequisites.sh

install-argocd: ## Install OpenShift GitOps (ArgoCD) operator
	@bash scripts/install-argocd.sh

install-argocd-rhoso1: ## Install dedicated ArgoCD instance for RHOSO
	@bash scripts/install-argocd-rhoso1.sh

validate: ## Validate the kustomization
	@echo "Validating kustomization..."
	oc kustomize $(OVERLAY) > /dev/null
	@echo "✓ Kustomization is valid"

test: validate ## Test kustomization output
	@echo "Rendering kustomization..."
	oc kustomize $(OVERLAY)

deploy: validate ## Deploy directly via kubectl/oc (bypasses ArgoCD)
	@echo "Deploying to $(NAMESPACE)..."
	oc apply -k $(OVERLAY)
	@echo "✓ Deployment submitted"
	@echo ""
	@echo "Monitor with: make status"

delete: ## Delete the deployment
	@echo "Deleting deployment from $(NAMESPACE)..."
	oc delete -k $(OVERLAY) --ignore-not-found=true
	@echo "✓ Deletion submitted"

argocd-deploy: ## Deploy ArgoCD Application
	@echo "Deploying ArgoCD Application..."
	@if ! oc get namespace $(ARGOCD_NAMESPACE) >/dev/null 2>&1; then \
		echo "Error: ArgoCD namespace $(ARGOCD_NAMESPACE) not found"; \
		echo "Please install OpenShift GitOps operator first"; \
		exit 1; \
	fi
	@echo ""
	@echo "⚠️  Make sure to update the repoURL in argocd/application.yaml before deploying!"
	@echo ""
	oc apply -f argocd/application.yaml
	@echo "✓ ArgoCD Application created"
	@echo ""
	@echo "Monitor with: make argocd-status"

argocd-deploy-rhoso1: ## Deploy ArgoCD Application (dedicated instance)
	@echo "Deploying ArgoCD Application to dedicated instance..."
	@if ! oc get namespace $(ARGOCD_RHOSO1_NAMESPACE) >/dev/null 2>&1; then \
		echo "Error: Dedicated ArgoCD namespace $(ARGOCD_RHOSO1_NAMESPACE) not found"; \
		echo "Please install dedicated instance first: make install-argocd-rhoso1"; \
		exit 1; \
	fi
	@echo ""
	@echo "⚠️  Make sure to update the repoURL in argocd/application-rhoso1.yaml before deploying!"
	@echo ""
	oc apply -f argocd/application-rhoso1.yaml
	@echo "✓ ArgoCD Application created in $(ARGOCD_RHOSO1_NAMESPACE)"
	@echo ""
	@echo "Monitor with: make argocd-status-rhoso1"

argocd-delete: ## Delete ArgoCD Application
	@echo "Deleting ArgoCD Application..."
	oc delete -f argocd/application.yaml --ignore-not-found=true
	@echo "✓ ArgoCD Application deleted"

argocd-delete-rhoso1: ## Delete ArgoCD Application (dedicated instance)
	@echo "Deleting ArgoCD Application from dedicated instance..."
	oc delete -f argocd/application-rhoso1.yaml --ignore-not-found=true
	@echo "✓ ArgoCD Application deleted"

argocd-status: ## Check ArgoCD Application status
	@oc get application rhoso-nvidia-l4-passthrough -n $(ARGOCD_NAMESPACE)

argocd-status-rhoso1: ## Check ArgoCD Application status (dedicated instance)
	@oc get application rhoso-nvidia-l4-passthrough -n $(ARGOCD_RHOSO1_NAMESPACE)

argocd-sync: ## Force ArgoCD sync
	@argocd app sync rhoso-nvidia-l4-passthrough

argocd-sync-rhoso1: ## Force ArgoCD sync (dedicated instance)
	@argocd app sync rhoso-nvidia-l4-passthrough --grpc-web

status: ## Check deployment status
	@echo "=== Namespace ==="
	@oc get namespace $(NAMESPACE) 2>/dev/null || echo "Namespace not found"
	@echo ""
	@echo "=== Jobs ==="
	@oc get jobs -n $(NAMESPACE) 2>/dev/null || echo "No jobs found"
	@echo ""
	@echo "=== PersistentVolumes ==="
	@oc get pv | grep local-storage || echo "No PVs found"
	@echo ""
	@echo "=== OpenStackControlPlane ==="
	@oc get openstackcontrolplane -n $(NAMESPACE) 2>/dev/null || echo "No control plane found"
	@echo ""
	@echo "=== Pods ==="
	@oc get pods -n $(NAMESPACE) 2>/dev/null || echo "No pods found"

logs-storage-prep: ## View storage preparation job logs
	@oc logs job/storage-prep -n $(NAMESPACE)

logs-pv-generator: ## View PV generator job logs
	@oc logs job/pv-generator -n $(NAMESPACE)

logs-nova: ## View Nova API logs
	@oc logs -n $(NAMESPACE) -l service=nova-api --tail=50

describe-controlplane: ## Describe OpenStackControlPlane
	@oc describe openstackcontrolplane openstack-galera -n $(NAMESPACE)

verify-gpu-config: ## Verify Nova GPU configuration
	@echo "Checking Nova PCI configuration..."
	@oc get openstackcontrolplane openstack-galera -n $(NAMESPACE) -o yaml | grep -A 10 "customServiceConfig" || echo "Configuration not found"

clean-pvs: ## Clean up released PVs
	@echo "Cleaning up released PVs..."
	@oc get pv -o json | jq -r '.items[] | select(.status.phase | test("Released")).metadata.name' | \
		xargs -I {} oc patch pv {} -p '{"spec":{"claimRef": null}}'
	@echo "✓ Released PVs cleaned"

watch-pods: ## Watch pods in namespace
	@watch -n 2 'oc get pods -n $(NAMESPACE)'

watch-controlplane: ## Watch OpenStackControlPlane status
	@watch -n 5 'oc get openstackcontrolplane -n $(NAMESPACE)'

get-routes: ## Get OpenStack service routes
	@echo "=== OpenStack Routes ==="
	@oc get routes -n $(NAMESPACE)

get-password: ## Get admin password from secret
	@echo "Admin Password:"
	@oc get secret osp-secret -n $(NAMESPACE) -o jsonpath='{.data.AdminPassword}' | base64 -d
	@echo ""
