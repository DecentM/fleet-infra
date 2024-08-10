# Starting from the ground up

- Get a cluster going
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
