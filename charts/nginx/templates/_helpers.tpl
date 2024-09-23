{{/*spec.selector*/}}
{{- define "nginx.spec.selector" }}
matchLabels:
  app: {{ .Chart.Name }}
{{- end }}

{{/*spec.template*/}}
{{- define "nginx.spec.template" }}
metadata:
  labels:
    app: {{ .Chart.Name }}
{{- end }}

{{/*metadata.labels*/}}
{{- define "nginx.metadata.labels" }}
labels:
  app: {{ .Chart.Name }}
{{- end }}
