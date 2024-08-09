# Starting from the ground up

- Get a cluster going
- Install flannel
  - `kubectl apply -f system/flannel.yaml`
- Initialise Flux

  - ```sh
    flux bootstrap github \
        --token-auth \
        --owner=decentm \
        --repository=fleet-infra \
        --branch=main \
        --path=. \
        --personal
    ```
