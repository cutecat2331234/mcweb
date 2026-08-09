package operation

import "testing"

func TestStorePersistsOneActiveBatchAndTargetLedger(t *testing.T) {
	store, err := NewStore(t.TempDir())
	if err != nil {
		t.Fatalf("NewStore: %v", err)
	}

	state := &State{
		Batch: Batch{
			ProtocolVersion: ProtocolVersion,
			ID:              "batch-1",
			OperationID:     "operation-1",
			DeliveryID:      "delivery-1",
			OperationType:   "collect_metrics",
			PayloadDigest:   "digest-1",
			Targets: []Target{{
				TargetKey: "server-1",
				ServerID:  "server-1",
				TaskType:  "collect_metrics",
				Payload:   map[string]interface{}{},
			}},
		},
		Phase: PhaseRunning,
		TargetResults: []TargetResult{{
			TargetKey: "server-1",
			Status:    "completed",
			Result:    map[string]interface{}{"success": true},
		}},
	}

	if err := store.Save(state); err != nil {
		t.Fatalf("Save: %v", err)
	}
	loaded, err := store.Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if loaded == nil || loaded.Batch.ID != "batch-1" || !loaded.HasResult("server-1") {
		t.Fatalf("unexpected state: %+v", loaded)
	}

	if err := store.Clear(); err != nil {
		t.Fatalf("Clear: %v", err)
	}
	loaded, err = store.Load()
	if err != nil || loaded != nil {
		t.Fatalf("expected empty store, state=%+v err=%v", loaded, err)
	}
}

func TestBatchRejectsMixedOrUnsupportedTasks(t *testing.T) {
	batch := Batch{
		ProtocolVersion: ProtocolVersion,
		ID:              "batch-1",
		OperationID:     "operation-1",
		DeliveryID:      "delivery-1",
		OperationType:   "sync_files",
		PayloadDigest:   "digest-1",
		Targets: []Target{{
			TargetKey: "server-1",
			ServerID:  "server-1",
			TaskType:  "exec_command",
			Payload:   map[string]interface{}{},
		}},
	}
	if err := batch.Validate(); err == nil {
		t.Fatal("expected mixed task type to be rejected")
	}
}
