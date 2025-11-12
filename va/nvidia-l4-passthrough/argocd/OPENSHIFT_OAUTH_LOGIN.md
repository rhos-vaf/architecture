# OpenShift OAuth Login for ArgoCD

The dedicated ArgoCD instance is configured to allow login using OpenShift credentials.

## How It Works

The ArgoCD instance uses **Dex** with OpenShift OAuth integration, which allows you to:
- Login with your OpenShift username/password
- Use the same credentials as `oc login`
- Leverage OpenShift RBAC groups

## Configuration

The following settings enable OpenShift OAuth in `argocd-rhoso1-instance.yaml`:

```yaml
dex:
  openShiftOAuth: true  # Enables OpenShift OAuth provider

rbac:
  policy: |
    # All authenticated OpenShift users get admin access
    g, system:authenticated, role:admin

    # Cluster admins also get admin access
    g, system:cluster-admins, role:admin
    g, cluster-admins, role:admin
```

## Apply the Configuration

If you need to update the configuration:

```bash
cd /home/mcarpio/CLAUDE/architecture/va/nvidia-l4-passthrough

# Apply updated ArgoCD instance
oc apply -f argocd/argocd-rhoso1-instance.yaml

# Wait for rollout
oc rollout status deployment/gitops-rhoso1-server -n gitops-rhoso1
```

## Login Methods

### Method 1: Login with OpenShift OAuth (Recommended)

1. Get the ArgoCD URL:
   ```bash
   ARGOCD_URL=$(oc get route gitops-rhoso1-server -n gitops-rhoso1 -o jsonpath='{.spec.host}')
   echo "https://${ARGOCD_URL}"
   ```

2. Open the URL in your browser

3. Click **"LOG IN VIA OPENSHIFT"** button

4. You'll be redirected to OpenShift OAuth login page

5. Login with your OpenShift credentials:
   - **Username**: Your OpenShift username (e.g., `kubeadmin`, `developer`, etc.)
   - **Password**: Your OpenShift password

6. Authorize ArgoCD to access your account (first time only)

7. You're logged in! ✅

### Method 2: Login with Admin User (Fallback)

If OAuth doesn't work, you can still use the admin user:

1. Get admin password:
   ```bash
   oc get secret gitops-rhoso1-cluster -n gitops-rhoso1 \
     -o jsonpath='{.data.admin\.password}' | base64 -d
   echo
   ```

2. Login with:
   - **Username**: `admin`
   - **Password**: (from above)

## Verify Your Access

After logging in via OpenShift OAuth:

```bash
# Check who you're logged in as
argocd account get-user-info

# Should show your OpenShift username
```

## Customize RBAC Permissions

By default, **all authenticated OpenShift users** get admin access. You can customize this:

### Option 1: Grant Admin Only to Specific Users

Edit `argocd-rhoso1-instance.yaml`:

```yaml
rbac:
  defaultPolicy: 'role:readonly'  # Default: read-only
  policy: |
    # Grant admin to specific users
    g, kubeadmin, role:admin
    g, developer, role:admin
    g, your-username, role:admin

    # Cluster admins still get admin
    g, system:cluster-admins, role:admin
```

### Option 2: Grant Admin to Specific OpenShift Groups

```yaml
rbac:
  policy: |
    # Map OpenShift groups to ArgoCD roles
    g, rhoso-admins, role:admin
    g, rhoso-developers, role:readonly

    # Cluster admins
    g, system:cluster-admins, role:admin
```

### Option 3: Read-Only for Most, Admin for Few

```yaml
rbac:
  defaultPolicy: 'role:readonly'  # Everyone gets read-only
  policy: |
    # Only these users get admin
    g, kubeadmin, role:admin
    g, rhoso-admin, role:admin

    # Cluster admins
    g, system:cluster-admins, role:admin
```

After changing RBAC:

```bash
oc apply -f argocd/argocd-rhoso1-instance.yaml
```

## Troubleshooting

### "LOG IN VIA OPENSHIFT" Button Not Showing

1. Check Dex is enabled:
   ```bash
   oc get pods -n gitops-rhoso1 | grep dex
   ```

2. Check ArgoCD logs:
   ```bash
   oc logs deployment/gitops-rhoso1-server -n gitops-rhoso1 | grep -i oauth
   ```

3. Verify configuration:
   ```bash
   oc get argocd gitops-rhoso1 -n gitops-rhoso1 -o yaml | grep -A 5 "dex:"
   ```

### OAuth Login Redirects but Fails

1. Check the OAuth client was created:
   ```bash
   oc get oauthclient | grep argocd
   ```

2. Verify the redirect URI is correct:
   ```bash
   oc get oauthclient gitops-rhoso1 -o yaml
   ```

   Should contain:
   ```yaml
   redirectURIs:
   - https://gitops-rhoso1-server-gitops-rhoso1.apps-crc.testing/auth/callback
   ```

3. Check Dex logs:
   ```bash
   oc logs deployment/gitops-rhoso1-dex-server -n gitops-rhoso1
   ```

### "User Not Authorized" After Login

Check RBAC policy:

```bash
oc get argocd gitops-rhoso1 -n gitops-rhoso1 -o yaml | grep -A 20 "rbac:"
```

Verify your user is in an authorized group:

```bash
# Check your OpenShift groups
oc whoami
oc get groups
```

### Unable to Access Applications

Even if logged in, you might see "permission denied". This means:
1. You're authenticated (logged in) ✅
2. But not authorized (no RBAC role) ❌

Solution: Add your user to the RBAC policy as shown above.

## Security Considerations

### Current Configuration: Wide Open

The default configuration grants **admin** to **all authenticated users**:

```yaml
g, system:authenticated, role:admin
```

**This is convenient for:**
- Development environments
- CRC/single-user setups
- POC/testing

**But NOT recommended for:**
- Production environments
- Multi-user clusters
- Compliance-required setups

### Recommended Production Configuration

For production, use specific users or groups:

```yaml
rbac:
  defaultPolicy: 'role:readonly'
  policy: |
    # Specific admin users
    g, rhoso-admin-user1, role:admin
    g, rhoso-admin-user2, role:admin

    # OpenShift admin group
    g, rhoso-admins, role:admin

    # Developer group gets read-only
    g, rhoso-developers, role:readonly

    # Cluster admins
    g, system:cluster-admins, role:admin
```

## ArgoCD RBAC Roles

Available built-in roles:

| Role | Permissions |
|------|-------------|
| `role:admin` | Full access - create, update, delete |
| `role:readonly` | Read-only access - view only |

## Testing OAuth Login

```bash
# 1. Get your OpenShift username
oc whoami

# 2. Open ArgoCD UI
ARGOCD_URL=$(oc get route gitops-rhoso1-server -n gitops-rhoso1 -o jsonpath='{.spec.host}')
echo "Open: https://${ARGOCD_URL}"

# 3. Click "LOG IN VIA OPENSHIFT"

# 4. Use your OpenShift credentials

# 5. Verify access
# You should see the ArgoCD dashboard with full access
```

## Example: Multiple Users Setup

If you have multiple users and want different access levels:

```yaml
rbac:
  defaultPolicy: ''  # No default policy
  policy: |
    # Admins
    p, role:admin, *, *, *, allow
    g, alice, role:admin
    g, bob, role:admin

    # Developers (read-only)
    p, role:developer, applications, get, */*, allow
    p, role:developer, applications, list, */*, allow
    g, charlie, role:developer
    g, diana, role:developer

    # Cluster admins always get full access
    g, system:cluster-admins, role:admin
```

## References

- [ArgoCD RBAC Documentation](https://argo-cd.readthedocs.io/en/stable/operator-manual/rbac/)
- [OpenShift OAuth](https://docs.openshift.com/container-platform/latest/authentication/index.html)
- [Dex OpenShift Connector](https://dexidp.io/docs/connectors/openshift/)

## Quick Commands

```bash
# Get ArgoCD URL
oc get route gitops-rhoso1-server -n gitops-rhoso1 -o jsonpath='{.spec.host}'

# Check who you are in OpenShift
oc whoami

# View current RBAC policy
oc get argocd gitops-rhoso1 -n gitops-rhoso1 -o jsonpath='{.spec.rbac.policy}'

# Update configuration
oc apply -f argocd/argocd-rhoso1-instance.yaml

# Restart ArgoCD server to pick up changes
oc rollout restart deployment/gitops-rhoso1-server -n gitops-rhoso1
```

---

**Default Login:** Any OpenShift user can login with admin access
**To Restrict:** Update the RBAC policy in `argocd-rhoso1-instance.yaml`
**To Test:** Open ArgoCD UI and click "LOG IN VIA OPENSHIFT"
