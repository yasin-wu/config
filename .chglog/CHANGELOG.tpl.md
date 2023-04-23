{{ range .Versions }}
## {{ if .Tag.Previous }}[{{ .Tag.Name }}]({{ $.Info.RepositoryURL }}/compare/{{ .Tag.Previous.Name }}...{{ .Tag.Name }}){{ else }}{{ .Tag.Name }}{{ end }}

> {{ datetime "2006-01-02 15:04:05" .Tag.Date }}

{{ range .CommitGroups -}}
### {{ .Title }}

{{ range .Commits -}}
* {{ if .Scope }}**{{ .Scope }}:** {{ end }}{{ .Subject }}([{{ .Author.Name }}]({{ .Author.Email }}))([{{ .Hash.Short }}]({{ $.Info.RepositoryURL }}/commits/{{ .Hash.Long }}))
{{ end }}
{{ end -}}

{{- if .RevertCommits -}}
### Reverts

{{ range .RevertCommits -}}
* {{ .Revert.Header }}([{{ .Author.Name }}]({{ .Author.Email }}))([{{ .Hash.Short }}]({{ $.Info.RepositoryURL }}/commits/{{ .Hash.Long }}))
{{ end }}
{{ end -}}

{{- if .MergeCommits -}}
### Merge Requests

{{ range .MergeCommits -}}
* {{ .Header }}([{{ .Author.Name }}]({{ .Author.Email }}))([{{ .Hash.Short }}]({{ $.Info.RepositoryURL }}/commits/{{ .Hash.Long }}))
{{ end }}
{{ end -}}

{{- if .NoteGroups -}}
{{ range .NoteGroups -}}
### {{ .Title }}

{{ range .Notes }}
{{ .Body }}([{{ .Author.Name }}]({{ .Author.Email }}))([{{ .Hash.Short }}]({{ $.Info.RepositoryURL }}/commits/{{ .Hash.Long }}))
{{ end }}
{{ end -}}
{{ end -}}
{{ end -}}