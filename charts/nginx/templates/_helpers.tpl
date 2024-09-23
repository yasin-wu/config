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

{{/*pvc.volumes*/}}
{{- define "nginx.pvc.volumes" }}
- name: data
  persistentVolumeClaim:
    claimName: {{.Values.global.pvc.name}}
{{- end }}

