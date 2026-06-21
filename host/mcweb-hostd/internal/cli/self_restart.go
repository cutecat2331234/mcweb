package cli

import (
	"fmt"
	"os/exec"

	"github.com/spf13/cobra"
)

func selfRestartCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "self-restart",
		Short: "Restart the mcweb-hostd systemd unit",
		RunE: func(cmd *cobra.Command, args []string) error {
			out, err := exec.Command("systemctl", "restart", "mcweb-hostd").CombinedOutput()
			fmt.Print(string(out))
			return err
		},
	}
}
