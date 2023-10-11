# Create Config.ini

```bash
kubectl create configmap rondb-configs \
    --from-file=./k8/configs/config.ini \
    --from-file=./k8/configs/my.cnf \
    --from-file=./k8/configs/rest_api.json \
    --from-file=./environments/common.env \
    --from-file=./environments/machine_sizes

kubectl create configmap rondb-templates \
    --from-file=./resources/config_templates
```
