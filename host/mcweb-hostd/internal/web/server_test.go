package web

import (
	"bytes"
	"strings"
	"testing"

	"github.com/mcweb/mcweb-hostd/internal/config"
	"github.com/mcweb/mcweb-hostd/internal/status"
)

func TestOperationsTemplateRequiresVersionOnlyForNativeUpdates(t *testing.T) {
	cfg := config.Default()
	cfg.JobLogDir = t.TempDir()
	server, err := NewServer(cfg, "")
	if err != nil {
		t.Fatal(err)
	}

	render := func(mode string) string {
		t.Helper()
		var output bytes.Buffer
		data := map[string]any{
			"Page":   "operations",
			"Report": status.Report{DeployMode: mode},
			"Jobs":   []*struct{}{},
			"CSRF":   "test-token",
		}
		if err := server.templates.ExecuteTemplate(&output, "layout.html", data); err != nil {
			t.Fatal(err)
		}
		return output.String()
	}

	native := render("native")
	if !strings.Contains(native, `name="version" required`) {
		t.Fatal("native update form does not require an explicit version")
	}
	docker := render("docker")
	if strings.Contains(docker, `name="version"`) {
		t.Fatal("docker update form unexpectedly asks for a release version")
	}
}
