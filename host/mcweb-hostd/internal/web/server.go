package web

import (
	"embed"
	"html/template"
	"io/fs"
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/mcweb/mcweb-hostd/internal/auth"
	"github.com/mcweb/mcweb-hostd/internal/config"
	"github.com/mcweb/mcweb-hostd/internal/mcweb"
	"github.com/mcweb/mcweb-hostd/internal/ops"
	"github.com/mcweb/mcweb-hostd/internal/status"
)

//go:embed templates/*.html
var templateFS embed.FS

type Server struct {
	cfg       *config.Config
	cfgPath   string
	auth      *auth.Manager
	lifecycle *ops.Lifecycle
	jobs      *ops.JobManager
	templates *template.Template
	install   *InstallState
}

func NewServer(cfg *config.Config, cfgPath string) (*Server, error) {
	tmpl, err := template.ParseFS(templateFS, "templates/*.html")
	if err != nil {
		return nil, err
	}
	jobs := ops.NewJobManager(cfg.JobLogDir)
	return &Server{
		cfg:       cfg,
		cfgPath:   cfgPath,
		auth:      auth.New(cfg),
		lifecycle: ops.NewLifecycle(cfg, jobs),
		jobs:      jobs,
		templates: tmpl,
		install:   NewInstallState(),
	}, nil
}

func (s *Server) Handler() http.Handler {
	r := chi.NewRouter()
	r.Use(middleware.Recoverer, middleware.Logger, middleware.RealIP)

	r.Get("/static/*", func(w http.ResponseWriter, r *http.Request) {
		sub, _ := fs.Sub(templateFS, "templates/static")
		http.StripPrefix("/static/", http.FileServer(http.FS(sub))).ServeHTTP(w, r)
	})

	r.Get("/init", s.handleInitGet)
	r.Post("/init", s.handleInitPost)
	r.Get("/login", s.handleLoginGet)
	r.Post("/login", s.handleLoginPost)
	r.Post("/logout", s.handleLogout)

	r.Group(func(r chi.Router) {
		r.Use(s.requireAuth)
		r.Get("/", s.handleDashboard)
		r.Get("/install", s.handleInstallGet)
		r.Post("/install", s.handleInstallPost)
		r.Get("/operations", s.handleOperationsGet)
		r.Post("/operations/{action}", s.handleOperationsPost)
		r.Get("/operations/jobs/{id}", s.handleJobGet)
		r.Post("/operations/backup", s.handleBackupPost)
		r.Post("/operations/install-node", s.handleInstallNodePost)
		r.Get("/settings", s.handleSettingsGet)
		r.Post("/settings", s.handleSettingsPost)
	})

	return r
}

func (s *Server) ListenAndServe(addr string) error {
	if addr == "" {
		addr = s.cfg.Listen
	}
	return http.ListenAndServe(addr, s.Handler())
}

func (s *Server) render(w http.ResponseWriter, name string, data map[string]any) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	if data == nil {
		data = map[string]any{}
	}
	data["Page"] = name
	if err := s.templates.ExecuteTemplate(w, "layout.html", data); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}

func (s *Server) requireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !s.cfg.Initialized {
			http.Redirect(w, r, "/init", http.StatusSeeOther)
			return
		}
		if _, ok := s.auth.UsernameFromRequest(r); !ok {
			http.Redirect(w, r, "/login", http.StatusSeeOther)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) dashboardData() map[string]any {
	report := status.Collect(s.cfg)
	paths := mcweb.ResolvePaths(s.cfg.McwebRoot, s.cfg.McwebEnvFile)
	return map[string]any{
		"Report":         report,
		"McwebInstalled": paths.Installed(),
		"InstallLocked":  report.Health.Live && report.InstalledViaHostd,
	}
}
