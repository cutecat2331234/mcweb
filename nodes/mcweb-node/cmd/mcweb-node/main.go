package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/mcweb/mcweb-node/internal/agent"
	"github.com/mcweb/mcweb-node/internal/config"
	"github.com/mcweb/mcweb-node/internal/pairing"
	"github.com/mcweb/mcweb-node/internal/proxy"
)

func main() {
	if len(os.Args) > 1 && os.Args[1] == "pair" {
		runPair(os.Args[2:])
		return
	}
	runAgent(os.Args[1:])
}

func runAgent(args []string) {
	flags := flag.NewFlagSet("mcweb-node", flag.ExitOnError)
	configPath := flags.String("config", "config/mcweb-node.yml", "path to config file")
	_ = flags.Parse(args)

	cfg, err := config.Load(*configPath)
	if err != nil {
		log.Fatalf("load config: %v", err)
	}

	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	stats := proxy.NewStats()

	go func() {
		if err := proxy.ListenAndServe(cfg.ProxyListen, cfg.RailsURL, stats); err != nil {
			log.Fatalf("proxy: %v", err)
		}
	}()

	a := agent.New(cfg, stats)
	log.Printf("mcweb-node started node_id=%s rails=%s", cfg.NodeID, cfg.RailsURL)
	a.Run(ctx)
	os.Exit(0)
}

func runPair(args []string) {
	flags := flag.NewFlagSet("mcweb-node pair", flag.ExitOnError)
	token := flags.String("token", "", "one-time pairing token from the McWeb admin")
	railsURL := flags.String("rails-url", "", "public McWeb URL")
	configPath := flags.String("config", "config/mcweb-node.yml", "configuration file to create")
	hostnameFlag := flags.String("hostname", "", "node hostname (defaults to the system hostname)")
	allowInsecureHTTP := flags.Bool("allow-insecure-http", false, "allow plain HTTP on a trusted network")
	_ = flags.Parse(args)

	hostname := *hostnameFlag
	if hostname == "" {
		hostname, _ = os.Hostname()
	}
	ctx, cancel := context.WithTimeout(context.Background(), 45*time.Second)
	defer cancel()
	credentials, err := pairing.Pair(ctx, *railsURL, *token, hostname, *allowInsecureHTTP)
	if err != nil {
		log.Fatalf("pair node: %v", err)
	}

	cfg := &config.Config{
		RailsURL:   *railsURL,
		NodeID:     credentials.NodeID,
		NodeSecret: credentials.NodeSecret,
	}
	if existing, loadErr := config.Load(*configPath); loadErr == nil {
		cfg.ProxyListen = existing.ProxyListen
		cfg.PollInterval = existing.PollInterval
		cfg.SpoolDir = existing.SpoolDir
	}
	if err := config.Save(*configPath, cfg); err != nil {
		log.Fatalf("save paired config: %v", err)
	}
	fmt.Printf("mcweb-node paired successfully as %s; credentials saved to %s\n", credentials.NodeID, *configPath)
}
