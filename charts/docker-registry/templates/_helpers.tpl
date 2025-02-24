{{/*common env*/}}
{{- define "common.env" }}
{{- with .Values.env }}
  {{- toYaml . | nindent 12 }}
{{- end }}
{{- end }}