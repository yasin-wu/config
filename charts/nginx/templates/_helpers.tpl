{{/*spec.selector*/}}
{{- define "spec.selector" }}
matchLabels:
  app: {{ .Chart.Name }}
{{- end }}

{{/*spec.template*/}}
{{- define "spec.template" }}
metadata:
  labels:
    app: {{ .Chart.Name }}
{{- end }}

{{/*metadata.labels*/}}
{{- define "metadata.labels" }}
labels:
  app: {{ .Chart.Name }}
{{- end }}

{{/*pvc.volumes*/}}
{{- define "pvc.volumes" }}
- name: data
  persistentVolumeClaim:
    claimName: {{.Values.global.pvc.name}}
{{- end }}

