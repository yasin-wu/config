{{/*common env*/}}
{{- define "common.env" }}
{{- with .Values.env }}
  {{- toYaml . | nindent 12 }}
{{- end }}
{{- end }}

{{/*common volumeMounts*/}}
{{- define "common.volumeMounts" }}
{{- with .Values.volumeMounts }}
  {{- toYaml . | nindent 12 }}
{{- end }}
{{- end }}

{{/*common volumes*/}}
{{- define "common.volumes" }}
{{- with .Values.volumes }}
  {{- toYaml . | nindent 8 }}
{{- end }}
{{- end }}

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