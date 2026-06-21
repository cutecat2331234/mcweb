package web

import (
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"
	"github.com/mcweb/mcweb-hostd/internal/auth"
	"github.com/mcweb/mcweb-hostd/internal/config"
	"github.com/mcweb/mcweb-hostd/internal/mcweb"
	"github.com/mcweb/mcweb-hostd/internal/ops"
)

func (s *Server) handleInitGet(w http.ResponseWriter, r *http.Request) {
	if s.cfg.Initialized {
		http.Redirect(w, r, "/login", http.StatusSeeOther)
		return
	}
	csrf := s.auth.NewCSRF()
	s.auth.SetCSRFCookie(w, r, csrf)
	s.render(w, "init", map[string]any{
		"CSRF": csrf,
	})
}

func (s *Server) handleInitPost(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if !s.auth.ValidateCSRF(r) {
		http.Error(w, "invalid csrf", http.StatusForbidden)
		return
	}
	if err := config.SetAdminPassword(s.cfg, r.FormValue("username"), r.FormValue("password")); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if err := s.cfg.EnsureSecretKey(); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	if err := config.Save(s.cfgPath, s.cfg); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	http.Redirect(w, r, "/login", http.StatusSeeOther)
}

func (s *Server) handleLoginGet(w http.ResponseWriter, r *http.Request) {
	if !s.cfg.Initialized {
		http.Redirect(w, r, "/init", http.StatusSeeOther)
		return
	}
	csrf := s.auth.NewCSRF()
	s.auth.SetCSRFCookie(w, r, csrf)
	s.render(w, "login", map[string]any{"CSRF": csrf})
}

func (s *Server) handleLoginPost(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if !s.auth.ValidateCSRF(r) {
		http.Error(w, "invalid csrf", http.StatusForbidden)
		return
	}
	if !config.CheckAdminPassword(s.cfg, r.FormValue("username"), r.FormValue("password")) {
		csrf := s.auth.NewCSRF()
		s.auth.SetCSRFCookie(w, r, csrf)
		s.render(w, "login", map[string]any{"CSRF": csrf, "Error": "Invalid credentials"})
		return
	}
	_ = s.auth.SetSessionCookie(w, r, r.FormValue("username"))
	http.Redirect(w, r, "/", http.StatusSeeOther)
}

func (s *Server) handleLogout(w http.ResponseWriter, r *http.Request) {
	s.auth.ClearSession(w)
	http.Redirect(w, r, "/login", http.StatusSeeOther)
}

func (s *Server) handleDashboard(w http.ResponseWriter, r *http.Request) {
	data := s.dashboardData()
	data["Title"] = "Dashboard"
	s.render(w, "dashboard", data)
}

func (s *Server) handleOperationsGet(w http.ResponseWriter, r *http.Request) {
	csrf := s.auth.NewCSRF()
	s.auth.SetCSRFCookie(w, r, csrf)
	data := s.dashboardData()
	data["Title"] = "Operations"
	data["CSRF"] = csrf
	data["Jobs"] = s.jobs.Recent(10)
	s.render(w, "operations", data)
}

func (s *Server) handleOperationsPost(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if !s.auth.ValidateCSRF(r) {
		http.Error(w, "invalid csrf", http.StatusForbidden)
		return
	}
	action := chi.URLParam(r, "action")
	docker := r.FormValue("docker") == "1"
	all := r.FormValue("all") == "1" || action == "start" || action == "stop" || action == "restart"
	webUnit := r.FormValue("web") == "1" || all
	worker := r.FormValue("worker") == "1" || all
	var job *ops.Job
	switch action {
	case "start":
		job = s.lifecycle.Start(webUnit, worker, all, docker)
	case "stop":
		job = s.lifecycle.Stop(webUnit, worker, all, docker)
	case "restart":
		job = s.lifecycle.Restart(webUnit, worker, all, docker)
	case "check":
		job = s.lifecycle.Check()
	case "update":
		job = s.lifecycle.Update(r.FormValue("version"))
	default:
		http.Error(w, "unknown action", http.StatusBadRequest)
		return
	}
	http.Redirect(w, r, "/operations/jobs/"+job.ID, http.StatusSeeOther)
}

func (s *Server) handleBackupPost(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if !s.auth.ValidateCSRF(r) {
		http.Error(w, "invalid csrf", http.StatusForbidden)
		return
	}
	ext := ops.NewExtendedOps(s.cfg, s.jobs)
	job := ext.Backup()
	http.Redirect(w, r, "/operations/jobs/"+job.ID, http.StatusSeeOther)
}

func (s *Server) handleInstallNodePost(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if !s.auth.ValidateCSRF(r) {
		http.Error(w, "invalid csrf", http.StatusForbidden)
		return
	}
	ext := ops.NewExtendedOps(s.cfg, s.jobs)
	job := ext.InstallNode()
	http.Redirect(w, r, "/operations/jobs/"+job.ID, http.StatusSeeOther)
}

func (s *Server) handleJobGet(w http.ResponseWriter, r *http.Request) {
	id := chi.URLParam(r, "id")
	job, ok := s.jobs.Get(id)
	if !ok {
		http.NotFound(w, r)
		return
	}
	data := s.dashboardData()
	data["Title"] = "Job " + id
	data["Job"] = job
	data["Refresh"] = job.Status == "running"
	s.render(w, "job", data)
}

func (s *Server) handleSettingsGet(w http.ResponseWriter, r *http.Request) {
	csrf := s.auth.NewCSRF()
	s.auth.SetCSRFCookie(w, r, csrf)
	data := s.dashboardData()
	data["Title"] = "Settings"
	data["CSRF"] = csrf
	data["Config"] = s.cfg
	s.render(w, "settings", data)
}

func (s *Server) handleSettingsPost(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if !s.auth.ValidateCSRF(r) {
		http.Error(w, "invalid csrf", http.StatusForbidden)
		return
	}
	s.cfg.Listen = r.FormValue("listen")
	s.cfg.McwebRoot = r.FormValue("mcweb_root")
	s.cfg.McwebEnvFile = r.FormValue("mcweb_env_file")
	s.cfg.ComposeDir = r.FormValue("compose_dir")
	s.cfg.DeployMode = r.FormValue("deploy_mode")
	s.cfg.ReleaseURL = r.FormValue("release_url")
	s.cfg.HealthURL = r.FormValue("health_url")
	if err := config.Save(s.cfgPath, s.cfg); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}
	http.Redirect(w, r, "/settings", http.StatusSeeOther)
}

// Install wizard state stored in memory (single-node hostd).
type InstallState struct {
	Step   int
	Mode   string
	DB     mcweb.FinalizeInput
	JobID  string
}

func NewInstallState() *InstallState {
	return &InstallState{Step: 1}
}

func (s *Server) handleInstallGet(w http.ResponseWriter, r *http.Request) {
	csrf := s.auth.NewCSRF()
	s.auth.SetCSRFCookie(w, r, csrf)
	data := s.dashboardData()
	data["Title"] = "Install McWeb"
	data["CSRF"] = csrf
	data["Step"] = s.install.Step
	data["Mode"] = s.install.Mode
	data["Install"] = s.install
	s.render(w, "install", data)
}

func (s *Server) handleInstallPost(w http.ResponseWriter, r *http.Request) {
	if err := r.ParseForm(); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	if !s.auth.ValidateCSRF(r) {
		http.Error(w, "invalid csrf", http.StatusForbidden)
		return
	}
	step, _ := strconv.Atoi(r.FormValue("step"))
	switch step {
	case 1:
		s.install.Mode = r.FormValue("mode")
		s.install.Step = 2
	case 2:
		s.install.Step = 3
		if r.FormValue("run_check") == "1" {
			job := s.lifecycle.Check()
			s.install.JobID = job.ID
		}
	case 3:
		s.install.Step = 4
		if s.install.Mode == "docker" {
			job := s.lifecycle.InstallDocker(r.FormValue("pull") == "1")
			s.install.JobID = job.ID
		} else {
			job := s.lifecycle.InstallNative(r.FormValue("fresh") == "1", r.FormValue("version"))
			s.install.JobID = job.ID
		}
	case 4:
		port, _ := strconv.Atoi(r.FormValue("port"))
		if port == 0 {
			port = 5432
		}
		s.install.DB.Database.Host = r.FormValue("host")
		s.install.DB.Database.Port = port
		s.install.DB.Database.Username = r.FormValue("username")
		s.install.DB.Database.Password = r.FormValue("password")
		s.install.DB.Database.DevelopmentDatabase = r.FormValue("development_database")
		s.install.Step = 5
	case 5:
		s.install.DB.Site.Name = r.FormValue("name")
		s.install.DB.Site.URL = r.FormValue("url")
		s.install.Step = 6
	case 6:
		s.install.DB.Admin.Email = r.FormValue("email")
		s.install.DB.Admin.Username = r.FormValue("username")
		s.install.DB.Admin.Password = r.FormValue("password")
		s.install.DB.Admin.DisplayName = r.FormValue("display_name")
		s.install.Step = 7
	case 7:
		job := s.lifecycle.Finalize(s.install.DB)
		s.install.JobID = job.ID
		s.install.Step = 8
	}
	http.Redirect(w, r, "/install", http.StatusSeeOther)
}

var _ = auth.CSRFTokenField
