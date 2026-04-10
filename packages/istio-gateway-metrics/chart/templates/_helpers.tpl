{{- define "istio-gateway-metrics.namespace" -}}
{{- default "monitoring" .Values.namespace -}}
{{- end -}}
