package templates

import (
	"bytes"
	_ "embed"
	"fmt"
	"text/template"
)

//go:embed workflow.yaml
var workflowTemplate string

//go:embed workflow-nix.yaml
var workflowNixTemplate string

func Render(p RenderParams) (string, error) {

	tmplStr := workflowTemplate
	if p.FlakeRef != "" {
		tmplStr = workflowNixTemplate
	}

	tmpl, err := template.New("workflow").Parse(tmplStr)
	if err != nil {
		return "", fmt.Errorf("failed to parse workflow template: %w", err)
	}

	buf := bytes.NewBuffer(nil)

	if err := tmpl.Execute(buf, p); err != nil {
		return "", fmt.Errorf("failed to execute workflow template: %w", err)
	}

	return buf.String(), nil
}

type RenderParams struct {
	Name      string
	Login     string
	Date      string
	RunsOn    string
	Secrets   map[string]string
	FlakeRef  string
	Tailscale bool
}
