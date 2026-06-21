package spool

import (
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

type Completion struct {
	TaskID string                 `json:"task_id"`
	Body   map[string]interface{} `json:"body"`
}

type Spool struct {
	dir string
}

func New(dir string) (*Spool, error) {
	if dir == "" {
		return nil, fmt.Errorf("spool dir required")
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, err
	}
	return &Spool{dir: dir}, nil
}

func (s *Spool) Enqueue(taskID string, body map[string]interface{}) error {
	name := fmt.Sprintf("%s.json", sanitize(taskID))
	data, err := json.Marshal(Completion{TaskID: taskID, Body: body})
	if err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(s.dir, name), data, 0o600)
}

func (s *Spool) List() ([]Completion, error) {
	entries, err := os.ReadDir(s.dir)
	if err != nil {
		return nil, err
	}
	var names []string
	for _, entry := range entries {
		if entry.IsDir() || !strings.HasSuffix(entry.Name(), ".json") {
			continue
		}
		names = append(names, entry.Name())
	}
	sort.Strings(names)

	out := make([]Completion, 0, len(names))
	for _, name := range names {
		data, err := os.ReadFile(filepath.Join(s.dir, name))
		if err != nil {
			continue
		}
		var item Completion
		if err := json.Unmarshal(data, &item); err != nil {
			continue
		}
		out = append(out, item)
	}
	return out, nil
}

func (s *Spool) Remove(taskID string) error {
	return os.Remove(filepath.Join(s.dir, fmt.Sprintf("%s.json", sanitize(taskID))))
}

func sanitize(taskID string) string {
	return strings.Map(func(r rune) rune {
		switch r {
		case '/', '\\', ':', '*', '?', '"', '<', '>', '|':
			return '_'
		default:
			return r
		}
	}, taskID)
}
