{{/*webRoot volumeMounts*/}}
{{- define "webRoot.volumeMounts" }}
{{- with .Values.webRoot.volumeMounts }}
  {{- toYaml . | nindent 12 }}
{{- end }}
{{- end }}

{{/*webRoot volumes*/}}
{{- define "webRoot.volumes" }}
{{- with .Values.webRoot.volumes }}
  {{- toYaml . | nindent 8 }}
{{- end }}
{{- end }}