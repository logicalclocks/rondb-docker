# Also supports nothing defined at all (local registry)
{{- define "image_registry" -}}
{{- if $.Values.global -}}
{{- if $.Values.global.imageRegistry -}}
{{- $.Values.global.imageRegistry -}}/
{{- end -}}
{{- else if $.Values.imageRegistry -}}
{{- $.Values.imageRegistry -}}/
{{- end -}}
{{- end -}}
