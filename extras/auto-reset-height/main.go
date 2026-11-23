// auto-reset-height resets a niri window's height to auto when it becomes the
// only window in its column.
//
// niri keeps a fixed/preset height (e.g. from switch-preset-window-height) even
// after the other windows in the column close, so the survivor doesn't fill the
// column. This listens to the niri event stream and calls reset-window-height.
package main

import (
	"bufio"
	"encoding/json"
	"os/exec"
	"strconv"
)

type layout struct {
	PosInScrollingLayout *[2]int `json:"pos_in_scrolling_layout"`
}

type window struct {
	ID          uint64  `json:"id"`
	WorkspaceID *uint64 `json:"workspace_id"`
	IsFloating  bool    `json:"is_floating"`
	Layout      layout  `json:"layout"`
}

type colKey struct {
	ws  uint64
	col int
}

type event struct {
	WindowsChanged *struct {
		Windows []window `json:"windows"`
	} `json:"WindowsChanged"`
	WindowOpenedOrChanged *struct {
		Window window `json:"window"`
	} `json:"WindowOpenedOrChanged"`
	WindowClosed *struct {
		ID uint64 `json:"id"`
	} `json:"WindowClosed"`
	WindowLayoutsChanged *struct {
		Changes [][2]json.RawMessage `json:"changes"`
	} `json:"WindowLayoutsChanged"`
}

var (
	windows   = map[uint64]*window{}
	prevCount = map[uint64]int{}
)

func key(w *window) (colKey, bool) {
	if w.IsFloating || w.WorkspaceID == nil || w.Layout.PosInScrollingLayout == nil {
		return colKey{}, false
	}
	return colKey{*w.WorkspaceID, w.Layout.PosInScrollingLayout[0]}, true
}

func update() {
	counts := map[colKey]int{}
	for _, w := range windows {
		if k, ok := key(w); ok {
			counts[k]++
		}
	}
	newCount := make(map[uint64]int, len(windows))
	for id, w := range windows {
		k, ok := key(w)
		if !ok {
			continue
		}
		n := counts[k]
		newCount[id] = n
		if prev, seen := prevCount[id]; n == 1 && seen && prev > 1 {
			_ = exec.Command("niri", "msg", "action", "reset-window-height",
				"--id", strconv.FormatUint(id, 10)).Run()
		}
	}
	prevCount = newCount
}

func main() {
	cmd := exec.Command("niri", "msg", "--json", "event-stream")
	out, err := cmd.StdoutPipe()
	if err != nil {
		panic(err)
	}
	if err := cmd.Start(); err != nil {
		panic(err)
	}

	sc := bufio.NewScanner(out)
	sc.Buffer(make([]byte, 0, 64*1024), 16*1024*1024)
	for sc.Scan() {
		var ev event
		if json.Unmarshal(sc.Bytes(), &ev) != nil {
			continue
		}
		switch {
		case ev.WindowsChanged != nil:
			windows = map[uint64]*window{}
			for i := range ev.WindowsChanged.Windows {
				w := ev.WindowsChanged.Windows[i]
				windows[w.ID] = &w
			}
		case ev.WindowOpenedOrChanged != nil:
			w := ev.WindowOpenedOrChanged.Window
			windows[w.ID] = &w
		case ev.WindowClosed != nil:
			delete(windows, ev.WindowClosed.ID)
		case ev.WindowLayoutsChanged != nil:
			for _, c := range ev.WindowLayoutsChanged.Changes {
				var id uint64
				var l layout
				if json.Unmarshal(c[0], &id) != nil || json.Unmarshal(c[1], &l) != nil {
					continue
				}
				if w, ok := windows[id]; ok {
					w.Layout = l
				}
			}
		default:
			continue
		}
		update()
	}
	_ = cmd.Wait()
}
