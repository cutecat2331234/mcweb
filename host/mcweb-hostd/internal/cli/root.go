package cli

import (
	"bufio"
	"fmt"
	"os"
	"strings"
	"time"

	"github.com/spf13/cobra"
	"github.com/mcweb/mcweb-hostd/internal/config"
	"github.com/mcweb/mcweb-hostd/internal/mcweb"
	"github.com/mcweb/mcweb-hostd/internal/ops"
	"github.com/mcweb/mcweb-hostd/internal/status"
	"github.com/mcweb/mcweb-hostd/internal/web"
)

var cfgPath string

func Execute() error {
	root := &cobra.Command{
		Use:   "mcweb-hostd",
		Short: "McWeb host console for install and lifecycle operations",
	}
	root.PersistentFlags().StringVar(&cfgPath, "config", config.ConfigPath(), "path to hostd.yml")

	root.AddCommand(serveCmd())
	root.AddCommand(initCmd())
	root.AddCommand(statusCmd())
	root.AddCommand(checkCmd())
	root.AddCommand(startCmd())
	root.AddCommand(stopCmd())
	root.AddCommand(restartCmd())
	root.AddCommand(updateCmd())
	root.AddCommand(logsCmd())
	root.AddCommand(installCmd())
	root.AddCommand(backupCmd())
	root.AddCommand(selfRestartCmd())

	return root.Execute()
}

func loadCfg() (*config.Config, error) {
	return config.Load(config.ResolvePath(cfgPath))
}

func serveCmd() *cobra.Command {
	var listen string
	cmd := &cobra.Command{
		Use:   "serve",
		Short: "Start the web console",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := loadCfg()
			if err != nil {
				return err
			}
			if listen != "" {
				cfg.Listen = listen
			}
			srv, err := web.NewServer(cfg, config.ResolvePath(cfgPath))
			if err != nil {
				return err
			}
			fmt.Printf("mcweb-hostd listening on %s\n", cfg.Listen)
			return srv.ListenAndServe(cfg.Listen)
		},
	}
	cmd.Flags().StringVar(&listen, "listen", "", "listen address")
	return cmd
}

func initCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "init",
		Short: "Initialize hostd administrator",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := loadCfg()
			if err != nil {
				return err
			}
			reader := bufio.NewReader(os.Stdin)
			fmt.Print("Admin username: ")
			username, _ := reader.ReadString('\n')
			fmt.Print("Admin password: ")
			password, _ := reader.ReadString('\n')
			if err := config.SetAdminPassword(cfg, strings.TrimSpace(username), strings.TrimSpace(password)); err != nil {
				return err
			}
			if err := cfg.EnsureSecretKey(); err != nil {
				return err
			}
			path := config.ResolvePath(cfgPath)
			if err := config.Save(path, cfg); err != nil {
				return err
			}
			config.PrintInitHint(path)
			return nil
		},
	}
	return cmd
}

func statusCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "status",
		Short: "Show McWeb and service status",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := loadCfg()
			if err != nil {
				return err
			}
			report := status.Collect(cfg)
			fmt.Printf("McWeb version: %s\n", report.McwebVersion)
			fmt.Printf("Deploy mode: %s\n", report.DeployMode)
			fmt.Printf("Health live: %v ready: %v\n", report.Health.Live, report.Health.Ready)
			for _, u := range report.Units {
				fmt.Printf("  %s: %s\n", u.Name, u.State)
			}
			return nil
		},
	}
}

func checkCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "check",
		Short: "Run doctor and health checks",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := loadCfg()
			if err != nil {
				return err
			}
			jobs := ops.NewJobManager(cfg.JobLogDir)
			lc := ops.NewLifecycle(cfg, jobs)
			job := lc.Check()
			for job.Status == "running" {
				// busy wait for CLI simplicity
			}
			fmt.Println(job.LogText())
			return nil
		},
	}
}

func lifecycleFlags(cmd *cobra.Command) (web, worker, all, docker bool) {
	web, _ = cmd.Flags().GetBool("web")
	worker, _ = cmd.Flags().GetBool("worker")
	all, _ = cmd.Flags().GetBool("all")
	docker, _ = cmd.Flags().GetBool("docker")
	return
}

func addLifecycleFlags(cmd *cobra.Command) {
	cmd.Flags().Bool("web", false, "mcweb-web only")
	cmd.Flags().Bool("worker", false, "mcweb-worker only")
	cmd.Flags().Bool("all", true, "web and worker")
	cmd.Flags().Bool("docker", false, "use docker compose")
}

func startCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "start",
		Short: "Start McWeb services",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := loadCfg()
			if err != nil {
				return err
			}
			jobs := ops.NewJobManager(cfg.JobLogDir)
			lc := ops.NewLifecycle(cfg, jobs)
			w, wo, a, d := lifecycleFlags(cmd)
			job := lc.Start(w, wo, a, d)
			waitJob(job)
			return nil
		},
	}
	addLifecycleFlags(cmd)
	return cmd
}

func stopCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "stop",
		Short: "Stop McWeb services",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := loadCfg()
			if err != nil {
				return err
			}
			jobs := ops.NewJobManager(cfg.JobLogDir)
			lc := ops.NewLifecycle(cfg, jobs)
			w, wo, a, d := lifecycleFlags(cmd)
			job := lc.Stop(w, wo, a, d)
			waitJob(job)
			return nil
		},
	}
	addLifecycleFlags(cmd)
	return cmd
}

func restartCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "restart",
		Short: "Restart McWeb services",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := loadCfg()
			if err != nil {
				return err
			}
			jobs := ops.NewJobManager(cfg.JobLogDir)
			lc := ops.NewLifecycle(cfg, jobs)
			w, wo, a, d := lifecycleFlags(cmd)
			job := lc.Restart(w, wo, a, d)
			waitJob(job)
			return nil
		},
	}
	addLifecycleFlags(cmd)
	return cmd
}

func updateCmd() *cobra.Command {
	var version string
	cmd := &cobra.Command{
		Use:   "update",
		Short: "Update McWeb to a new release",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := loadCfg()
			if err != nil {
				return err
			}
			jobs := ops.NewJobManager(cfg.JobLogDir)
			lc := ops.NewLifecycle(cfg, jobs)
			job := lc.Update(version)
			waitJob(job)
			if job.Status == "failed" {
				return fmt.Errorf("update failed")
			}
			return nil
		},
	}
	cmd.Flags().StringVar(&version, "version", "", "release version")
	return cmd
}

func logsCmd() *cobra.Command {
	var webOnly, worker, follow bool
	cmd := &cobra.Command{
		Use:   "logs",
		Short: "Show service logs",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := loadCfg()
			if err != nil {
				return err
			}
			jobs := ops.NewJobManager(cfg.JobLogDir)
			lc := ops.NewLifecycle(cfg, jobs)
			fmt.Println(lc.Logs(webOnly, worker, follow))
			return nil
		},
	}
	cmd.Flags().BoolVar(&webOnly, "web", true, "web logs")
	cmd.Flags().BoolVar(&worker, "worker", false, "worker logs")
	cmd.Flags().BoolVar(&follow, "f", false, "follow")
	return cmd
}

func installCmd() *cobra.Command {
	install := &cobra.Command{
		Use:   "install",
		Short: "Install McWeb",
	}
	var fresh bool
	var version string
	var pull bool

	native := &cobra.Command{
		Use:   "native",
		Short: "Install McWeb natively",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := loadCfg()
			if err != nil {
				return err
			}
			jobs := ops.NewJobManager(cfg.JobLogDir)
			lc := ops.NewLifecycle(cfg, jobs)
			job := lc.InstallNative(fresh, version)
			waitJob(job)
			if job.Status == "failed" {
				return fmt.Errorf("install failed")
			}
			return nil
		},
	}
	native.Flags().BoolVar(&fresh, "fresh", false, "run bin/install")
	native.Flags().StringVar(&version, "version", "", "release version")

	docker := &cobra.Command{
		Use:   "docker",
		Short: "Install McWeb via Docker Compose",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := loadCfg()
			if err != nil {
				return err
			}
			cfg.DeployMode = "docker"
			jobs := ops.NewJobManager(cfg.JobLogDir)
			lc := ops.NewLifecycle(cfg, jobs)
			job := lc.InstallDocker(pull)
			waitJob(job)
			if job.Status == "failed" {
				return fmt.Errorf("install failed")
			}
			return nil
		},
	}
	docker.Flags().BoolVar(&pull, "pull", false, "pull images first")

	wizard := &cobra.Command{
		Use:   "wizard",
		Short: "Interactive install wizard (use web UI for full flow)",
		Run: func(cmd *cobra.Command, args []string) {
			fmt.Println("Open the hostd web console at /install for the full 7-step wizard.")
			fmt.Println("Or use: mcweb-hostd install native --fresh && bin/hostd-finalize --input config.json")
		},
	}

	install.AddCommand(native, docker, wizard)
	return install
}

func waitJob(job *ops.Job) {
	for job.Status == "running" {
		time.Sleep(100 * time.Millisecond)
	}
	fmt.Println(job.LogText())
}

var _ = mcweb.DefaultRoot
