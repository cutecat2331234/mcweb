package agent

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"runtime"
	"time"

	"github.com/mcweb/mcweb-node/internal/client"
	"github.com/mcweb/mcweb-node/internal/config"
	"github.com/mcweb/mcweb-node/internal/executor"
	"github.com/mcweb/mcweb-node/internal/metrics"
	"github.com/mcweb/mcweb-node/internal/proxy"
)

type Agent struct {
	cfg      *config.Config
	client   *client.Client
	exec     *executor.Executor
	stats    *proxy.Stats
	hostname string
}

func New(cfg *config.Config, stats *proxy.Stats) *Agent {
	return &Agent{
		cfg:      cfg,
		client:   client.New(cfg.RailsURL, cfg.NodeID, cfg.NodeSecret),
		exec:     executor.New(),
		stats:    stats,
		hostname: hostname(),
	}
}

func hostname() string {
	h, err := os.Hostname()
	if err != nil {
		return "unknown"
	}
	return h
}

func (a *Agent) Run(ctx context.Context) {
	ticker := time.NewTicker(a.cfg.PollInterval)
	defer ticker.Stop()

	a.tick(ctx)

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			a.tick(ctx)
		}
	}
}

func (a *Agent) tick(ctx context.Context) {
	a.heartbeat(ctx)
	a.pollTasks(ctx)
}

func (a *Agent) heartbeat(ctx context.Context) {
	body := map[string]interface{}{
		"hostname": a.hostname,
		"metadata": map[string]interface{}{
			"go_version":   runtime.Version(),
			"num_cpu":      runtime.NumCPU(),
			"os":           runtime.GOOS,
			"host_metrics": metrics.CollectHost(),
		},
		"connector_proxy": a.stats.Snapshot(),
	}
	resp, err := a.client.Post(a.client.NodePath("heartbeat"), body)
	if err != nil {
		log.Printf("heartbeat failed: %v", err)
		return
	}
	_ = resp
}

func (a *Agent) pollTasks(ctx context.Context) {
	resp, err := a.client.Get(a.client.NodePath("tasks"))
	if err != nil {
		log.Printf("task poll failed: %v", err)
		return
	}
	tasks, ok := resp["tasks"].([]interface{})
	if !ok || len(tasks) == 0 {
		return
	}
	for _, raw := range tasks {
		task, ok := raw.(map[string]interface{})
		if !ok {
			continue
		}
		a.handleTask(ctx, task)
	}
}

func (a *Agent) handleTask(ctx context.Context, task map[string]interface{}) {
	id, _ := task["id"].(float64)
	taskID := fmt.Sprintf("%.0f", id)

	enriched := enrichTask(task)
	result := a.exec.Run(ctx, enriched)

	if taskType, _ := task["task_type"].(string); taskType == "collect_metrics" {
		a.reportInstanceMetrics(enriched, result)
	}

	completeBody := map[string]interface{}{"result": result}
	path := fmt.Sprintf("/minecraft/nodes/%s/tasks/%s/complete", a.cfg.NodeID, taskID)
	_, err := a.client.Post(path, completeBody)
	if err != nil {
		log.Printf("complete task %s failed: %v", taskID, err)
	}
}

func (a *Agent) reportInstanceMetrics(task map[string]interface{}, result map[string]interface{}) {
	serverID := instanceServerID(task)
	if serverID == "" {
		return
	}

	body := map[string]interface{}{}
	if metricsData, ok := result["metrics"].(map[string]interface{}); ok {
		body["metrics"] = metricsData
	}
	if ps, ok := result["process_state"].(string); ok && ps != "" {
		body["process_state"] = ps
	}
	if len(body) == 0 {
		return
	}

	path := fmt.Sprintf("/minecraft/nodes/%s/instances/%s/report", a.cfg.NodeID, serverID)
	if _, err := a.client.Post(path, body); err != nil {
		log.Printf("instance report for %s failed: %v", serverID, err)
	}
}

func instanceServerID(task map[string]interface{}) string {
	if sid, ok := task["server_id"].(string); ok && sid != "" {
		return sid
	}
	payload, _ := task["payload"].(map[string]interface{})
	if payload == nil {
		return ""
	}
	if sid, ok := payload["server_id"].(string); ok {
		return sid
	}
	return fmt.Sprint(payload["server_id"])
}

func enrichTask(task map[string]interface{}) map[string]interface{} {
	payload, _ := task["payload"].(map[string]interface{})
	if payload == nil {
		payload = map[string]interface{}{}
	}
	// payload from Rails may already include process fields
	task["payload"] = payload
	return task
}

// JSON debug helper
func _debug(v interface{}) string {
	b, _ := json.Marshal(v)
	return string(b)
}

