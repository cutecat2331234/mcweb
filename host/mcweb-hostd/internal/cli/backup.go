package cli

import (
	"fmt"

	"github.com/spf13/cobra"
	"github.com/mcweb/mcweb-hostd/internal/ops"
)

func backupCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "backup",
		Short: "Run McWeb backup script",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := loadCfg()
			if err != nil {
				return err
			}
			jobs := ops.NewJobManager(cfg.JobLogDir)
			ext := ops.NewExtendedOps(cfg, jobs)
			job := ext.Backup()
			waitJob(job)
			if job.Status == "failed" {
				return fmt.Errorf("backup failed")
			}
			return nil
		},
	}
}
