# Create Config.ini

```bash
kubectl create configmap rondb-configs \
    --from-file=./k8/config.ini \
    --from-file=./k8/my.cnf
```
