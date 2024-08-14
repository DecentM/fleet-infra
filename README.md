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
