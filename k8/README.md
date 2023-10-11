# Create Config.ini

```bash
kubectl create configmap rondb-configs \
    --from-file=./k8/configs/config.ini \
    --from-file=./k8/configs/my.cnf \
    --from-file=./k8/configs/rest_api.json
```
