package agent

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"runtime"
	"sync"
	"time"

	"github.com/mcweb/mcweb-node/internal/client"
	"github.com/mcweb/mcweb-node/internal/config"
	"github.com/mcweb/mcweb-node/internal/executor"
	"github.com/mcweb/mcweb-node/internal/metrics"
	"github.com/mcweb/mcweb-node/internal/proxy"
	"github.com/mcweb/mcweb-node/internal/spool"
)

type Agent struct {
	cfg       *config.Config
	client    *client.Client
	exec      *executor.Executor
	stats     *proxy.Stats
	hostname  string
	spool     *spool.Spool
	pollNow   chan struct{}
	wakeSince string
	wakeMu    sync.Mutex
}

func New(cfg *config.Config, stats *proxy.Stats) *Agent {
	s, err := spool.New(cfg.SpoolDir)
	if err != nil {
		log.Printf("spool disabled: %v", err)
	}
	return &Agent{
		cfg:      cfg,
		client:   client.New(cfg.RailsURL, cfg.NodeID, cfg.NodeSecret),
		exec:     executor.New(),
		stats:    stats,
		hostname: hostname(),
		spool:    s,
		pollNow:  make(chan struct{}, 1),
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
	go a.watchEvents(ctx)

	ticker := time.NewTicker(a.cfg.PollInterval)
	defer ticker.Stop()

	a.tick(ctx)

	for {
		select {
		case <-ctx.Done():
			return
		case <-a.pollNow:
			a.tick(ctx)
		case <-ticker.C:
			a.tick(ctx)
		}
	}
}

func (a *Agent) requestPoll() {
	select {
	case a.pollNow <- struct{}{}:
	default:
	}
}

func (a *Agent) watchEvents(ctx context.Context) {
	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		since := a.currentWakeSince()
		err := a.client.StreamEvents(ctx, since, func(event string) {
			if event == "tasks_available" {
				a.requestPoll()
			}
		})
		if err != nil && ctx.Err() == nil {
			log.Printf("event stream ended: %v", err)
		}

		select {
		case <-ctx.Done():
			return
		case <-time.After(2 * time.Second):
		}
	}
}

func (a *Agent) currentWakeSince() string {
	a.wakeMu.Lock()
	defer a.wakeMu.Unlock()
	return a.wakeSince
}

func (a *Agent) setWakeSince(value string) {
	a.wakeMu.Lock()
	a.wakeSince = value
	a.wakeMu.Unlock()
}

func (a *Agent) tick(ctx context.Context) {
	a.flushSpool(ctx)
	urgent := a.heartbeat(ctx)
	a.pollTasks(ctx)
	if urgent {
		a.pollTasks(ctx)
	}
}

func (a *Agent) flushSpool(ctx context.Context) {
	if a.spool == nil {
		return
	}
	items, err := a.spool.List()
	if err != nil {
		log.Printf("spool list failed: %v", err)
		return
	}
	for _, item := range items {
		path := fmt.Sprintf("/minecraft/nodes/%s/tasks/%s/complete", a.cfg.NodeID, item.TaskID)
		if _, err := a.client.Post(path, item.Body); err != nil {
			log.Printf("spool replay task %s failed: %v", item.TaskID, err)
			continue
		}
		if err := a.spool.Remove(item.TaskID); err != nil {
			log.Printf("spool remove task %s failed: %v", item.TaskID, err)
		}
	}
	_ = ctx
}

func (a *Agent) heartbeat(ctx context.Context) bool {
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
		return false
	}

	if wakeAt, ok := resp["tasks_wake_at"].(string); ok && wakeAt != "" {
		a.setWakeSince(wakeAt)
	}
	if urgent, ok := resp["urgent_tasks_pending"].(bool); ok && urgent {
		return true
	}
	return false
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
	if _, err := a.client.Post(path, completeBody); err != nil {
		log.Printf("complete task %s failed: %v", taskID, err)
		if a.spool != nil {
			if spoolErr := a.spool.Enqueue(taskID, completeBody); spoolErr != nil {
				log.Printf("spool task %s failed: %v", taskID, spoolErr)
			}
		}
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
	task["payload"] = payload
	return task
}

// JSON debug helper
func _debug(v interface{}) string {
	b, _ := json.Marshal(v)
	return string(b)
}
