# Starting from the ground up

- Get a cluster going
- Get the ZFS pool going
  - Create a zvol, format it as XFS, mount it via fstab
- Install flannel
  - `kubectl apply -f infrastructure/flannel/index.yaml`
- If the control plane has the pool, remove the control-plane taint
  - `kubectl taint nodes <hostname> node-role.kubernetes.io/control-plane:NoSchedule-`
- Initialise Flux

  - ```sh
    flux bootstrap github \
        --token-auth \
        --owner=decentm \
        --repository=fleet-infra \
        --branch=main \
        --path=clusters/staging \ # or `clusters/production`
        --personal
    ```

- In Longhorn, add a disk on the pool node with the "zfs-pool" tag. Make the
    host path be the xfs fs's mount path

## Secrets

> From [Sealed Secrets | Flux](https://fluxcd.io/flux/guides/sealed-secrets/#encrypt-secrets)

```sh
kubeseal --fetch-cert \
--controller-name=sealed-secrets-controller \
--controller-namespace=flux-system \
> pub-sealed-secrets.pem
```

The public key can be safely stored in Git, and can be used to encrypt secrets without direct access to the Kubernetes cluster.
Encrypt secrets

Generate a Kubernetes secret manifest with kubectl:

```sh
kubectl -n <namespace> create secret generic <secret-name> \
--from-literal=user=admin \
--from-literal=password=change-me \
--dry-run=client \
-o yaml > basic-auth.yaml
```

Encrypt the secret with kubeseal:

```sh
kubeseal --format=yaml --cert=pub-sealed-secrets.pem \
< basic-auth.yaml > basic-auth-sealed.yaml
```

Delete the plain secret and commit the sealed one
