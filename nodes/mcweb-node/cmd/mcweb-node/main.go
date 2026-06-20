package main

import (
	"context"
	"flag"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/mcweb/mcweb-node/internal/agent"
	"github.com/mcweb/mcweb-node/internal/config"
	"github.com/mcweb/mcweb-node/internal/proxy"
)

func main() {
	configPath := flag.String("config", "config/mcweb-node.yml", "path to config file")
	flag.Parse()

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
