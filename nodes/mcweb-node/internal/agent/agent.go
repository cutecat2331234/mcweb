package agent

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/url"
	"os"
	"path/filepath"
	"runtime"
	"sync"
	"time"

	"github.com/mcweb/mcweb-node/internal/client"
	"github.com/mcweb/mcweb-node/internal/config"
	"github.com/mcweb/mcweb-node/internal/executor"
	"github.com/mcweb/mcweb-node/internal/metrics"
	"github.com/mcweb/mcweb-node/internal/operation"
	"github.com/mcweb/mcweb-node/internal/proxy"
	"github.com/mcweb/mcweb-node/internal/spool"
)

type Agent struct {
	cfg            *config.Config
	client         *client.Client
	exec           *executor.Executor
	stats          *proxy.Stats
	hostname       string
	spool          *spool.Spool
	operationStore *operation.Store
	pollNow        chan struct{}
	wakeSince      string
	wakeMu         sync.Mutex
}

func New(cfg *config.Config, stats *proxy.Stats) *Agent {
	s, err := spool.New(cfg.SpoolDir)
	if err != nil {
		log.Printf("spool disabled: %v", err)
	}
	operationStore, operationErr := operation.NewStore(filepath.Join(cfg.SpoolDir, "operations"))
	if operationErr != nil {
		log.Printf("operation store disabled: %v", operationErr)
	}
	return &Agent{
		cfg:            cfg,
		client:         client.New(cfg.RailsURL, cfg.NodeID, cfg.NodeSecret),
		exec:           executor.New(),
		stats:          stats,
		hostname:       hostname(),
		spool:          s,
		operationStore: operationStore,
		pollNow:        make(chan struct{}, 1),
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
		available, wakeAt, err := a.client.PollTaskWake(ctx, since)
		if err != nil && ctx.Err() == nil {
			log.Printf("task wake poll failed: %v", err)
		}
		if available {
			if wakeAt != "" {
				a.setWakeSince(wakeAt)
			}
			a.requestPoll()
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
	a.heartbeat(ctx)
	if a.flushSpool(ctx) {
		return
	}
	if a.processOperation(ctx) {
		return
	}
	a.pollTasks(ctx)
}

func (a *Agent) flushSpool(ctx context.Context) bool {
	if a.spool == nil {
		return false
	}
	items, err := a.spool.List()
	if err != nil {
		log.Printf("spool list failed: %v", err)
		return true
	}
	if len(items) == 0 {
		return false
	}

	// Replay exactly one already-executed legacy task and keep the node blocked until
	// Rails confirms it. Dropping a 4xx response could otherwise leave the control
	// plane and node with irreconcilable execution histories.
	item := items[0]
	path := fmt.Sprintf("/minecraft/nodes/%s/tasks/%s/complete", a.cfg.NodeID, item.TaskID)
	if _, err := a.client.Post(path, item.Body); err != nil {
		log.Printf("spool replay task %s failed and remains blocking: %v", item.TaskID, err)
		return true
	}
	if err := a.spool.Remove(item.TaskID); err != nil {
		log.Printf("spool remove task %s failed: %v", item.TaskID, err)
		return true
	}
	_ = ctx
	return len(items) > 1
}

func (a *Agent) heartbeat(ctx context.Context) bool {
	body := map[string]interface{}{
		"hostname": a.hostname,
		"metadata": map[string]interface{}{
			"go_version":             runtime.Version(),
			"num_cpu":                runtime.NumCPU(),
			"os":                     runtime.GOOS,
			"host_metrics":           metrics.CollectHost(),
			"node_protocol_versions": []int{1, operation.ProtocolVersion},
			"operation_types":        []string{"collect_metrics", "sync_files"},
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
	task, ok := tasks[0].(map[string]interface{})
	if ok {
		a.handleTask(ctx, task)
	}
}

func (a *Agent) handleTask(ctx context.Context, task map[string]interface{}) {
	taskID := stringIdentifier(task["id"])
	if taskID == "" {
		log.Printf("legacy task ignored because id is missing")
		return
	}

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

func (a *Agent) processOperation(ctx context.Context) bool {
	if a.operationStore == nil {
		return false
	}

	state, err := a.operationStore.Load()
	if err != nil {
		log.Printf("operation ledger load failed; node remains blocked: %v", err)
		return true
	}
	if state == nil {
		state, err = a.claimOperation()
		if err != nil {
			log.Printf("operation poll failed: %v", err)
			return false
		}
		if state == nil {
			return false
		}
		if err := a.operationStore.Save(state); err != nil {
			log.Printf("operation claim could not be persisted; node remains blocked: %v", err)
			return true
		}
	}

	if err := a.resumeOperation(ctx, state); err != nil {
		log.Printf("operation batch %s paused: %v", state.Batch.ID, err)
	}
	return true
}

func (a *Agent) claimOperation() (*operation.State, error) {
	resp, err := a.client.Get(a.client.NodePath("operations/next"))
	if err != nil {
		return nil, err
	}
	raw, exists := resp["batch"]
	if !exists || raw == nil {
		return nil, nil
	}
	encoded, err := json.Marshal(raw)
	if err != nil {
		return nil, err
	}
	var batch operation.Batch
	if err := json.Unmarshal(encoded, &batch); err != nil {
		return nil, err
	}
	if err := batch.Validate(); err != nil {
		return nil, err
	}
	return &operation.State{Batch: batch, Phase: operation.PhaseDispatched}, nil
}

func (a *Agent) resumeOperation(ctx context.Context, state *operation.State) error {
	if state.Phase != operation.PhaseResultPendingAck {
		if err := a.executeOperationTargets(ctx, state); err != nil {
			return err
		}
	}
	return a.deliverOperationResult(state)
}

func (a *Agent) executeOperationTargets(ctx context.Context, state *operation.State) error {
	state.Phase = operation.PhaseRunning
	if err := a.operationStore.Save(state); err != nil {
		return err
	}

	leaseCtx, cancelLease := context.WithCancel(ctx)
	var leaseWG sync.WaitGroup
	leaseWG.Add(1)
	go func() {
		defer leaseWG.Done()
		a.renewOperationLeaseLoop(leaseCtx, state.Batch)
	}()
	defer func() {
		cancelLease()
		leaseWG.Wait()
	}()

	for _, target := range state.Batch.Targets {
		if state.HasResult(target.TargetKey) {
			continue
		}
		startedAt := time.Now().UTC()
		payload := mergePayloads(state.Batch.SharedPayload, target.Payload)
		result := a.exec.Run(ctx, map[string]interface{}{
			"task_type": target.TaskType,
			"payload":   payload,
		})
		completedAt := time.Now().UTC()
		status := "completed"
		if !operationResultSuccessful(result) {
			status = "failed"
		}

		state.TargetResults = append(state.TargetResults, operation.TargetResult{
			TargetKey:       target.TargetKey,
			Status:          status,
			AppliedRevision: stringIdentifier(result["applied_revision"]),
			Result:          result,
			ErrorCode:       stringIdentifier(result["error_code"]),
			ErrorMessage:    stringIdentifier(result["error"]),
			StartedAt:       startedAt,
			CompletedAt:     completedAt,
		})
		if err := a.operationStore.Save(state); err != nil {
			return err
		}
	}

	state.Phase = operation.PhaseResultPendingAck
	return a.operationStore.Save(state)
}

func (a *Agent) renewOperationLeaseLoop(ctx context.Context, batch operation.Batch) {
	renew := func() {
		path := fmt.Sprintf(
			"/minecraft/nodes/%s/operations/%s/lease",
			a.cfg.NodeID,
			url.PathEscape(batch.ID),
		)
		body := map[string]interface{}{
			"delivery_id":    batch.DeliveryID,
			"payload_digest": batch.PayloadDigest,
		}
		if _, err := a.client.Post(path, body); err != nil && ctx.Err() == nil {
			log.Printf("operation batch %s lease renewal failed: %v", batch.ID, err)
		}
	}

	renew()
	ticker := time.NewTicker(time.Minute)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			renew()
		}
	}
}

func (a *Agent) deliverOperationResult(state *operation.State) error {
	basePath := fmt.Sprintf(
		"/minecraft/nodes/%s/operations/%s",
		a.cfg.NodeID,
		url.PathEscape(state.Batch.ID),
	)
	baseBody := map[string]interface{}{
		"delivery_id":    state.Batch.DeliveryID,
		"payload_digest": state.Batch.PayloadDigest,
	}

	if state.AcknowledgementID == "" {
		body := map[string]interface{}{
			"delivery_id":    state.Batch.DeliveryID,
			"payload_digest": state.Batch.PayloadDigest,
			"target_results": state.TargetResults,
		}
		resp, err := a.client.Post(basePath+"/complete", body)
		if err != nil {
			return err
		}
		if acknowledged, _ := resp["acknowledged"].(bool); acknowledged {
			return a.operationStore.Clear()
		}
		state.AcknowledgementID, _ = resp["acknowledgement_id"].(string)
		if state.AcknowledgementID == "" {
			return fmt.Errorf("completion response omitted acknowledgement_id")
		}
		if err := a.operationStore.Save(state); err != nil {
			return err
		}
	}

	baseBody["acknowledgement_id"] = state.AcknowledgementID
	resp, err := a.client.Post(basePath+"/acknowledge", baseBody)
	if err != nil {
		return err
	}
	acknowledged, _ := resp["acknowledged"].(bool)
	if !acknowledged {
		return fmt.Errorf("control plane did not acknowledge operation result")
	}
	return a.operationStore.Clear()
}

func operationResultSuccessful(result map[string]interface{}) bool {
	if success, ok := result["success"].(bool); ok && !success {
		return false
	}
	return stringIdentifier(result["status"]) != "failed"
}

func mergePayloads(shared, target map[string]interface{}) map[string]interface{} {
	merged := make(map[string]interface{}, len(shared)+len(target))
	for key, value := range shared {
		merged[key] = value
	}
	for key, value := range target {
		merged[key] = value
	}
	return merged
}

func stringIdentifier(value interface{}) string {
	switch typed := value.(type) {
	case string:
		return typed
	case json.Number:
		return typed.String()
	case float64:
		return fmt.Sprintf("%.0f", typed)
	case nil:
		return ""
	default:
		return fmt.Sprint(typed)
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
