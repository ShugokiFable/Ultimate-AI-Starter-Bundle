package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
)

const version = "6.0.0"

type receipt struct {
	Result string `json:"result"`
	Source string `json:"source,omitempty"`
	Target string `json:"target,omitempty"`
	SHA256 string `json:"sha256,omitempty"`
	Size   int64  `json:"size,omitempty"`
}

func hashFile(path string) (string, int64, error) {
	f, err := os.Open(path)
	if err != nil {
		return "", 0, err
	}
	defer f.Close()
	h := sha256.New()
	n, err := io.Copy(h, f)
	if err != nil {
		return "", 0, err
	}
	return hex.EncodeToString(h.Sum(nil)), n, nil
}

func atomicCopy(source, target string) (receipt, error) {
	if source == "" || target == "" {
		return receipt{}, errors.New("source and target are required")
	}
	src, err := os.Open(source)
	if err != nil {
		return receipt{}, err
	}
	defer src.Close()
	if _, err := os.Stat(target); err == nil {
		return receipt{}, fmt.Errorf("refusing to overwrite existing target: %s", target)
	}
	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		return receipt{}, err
	}
	tmp := target + ".forge.tmp"
	_ = os.Remove(tmp)
	out, err := os.OpenFile(tmp, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o644)
	if err != nil {
		return receipt{}, err
	}
	_, copyErr := io.Copy(out, src)
	syncErr := out.Sync()
	closeErr := out.Close()
	if copyErr != nil || syncErr != nil || closeErr != nil {
		_ = os.Remove(tmp)
		if copyErr != nil {
			return receipt{}, copyErr
		}
		if syncErr != nil {
			return receipt{}, syncErr
		}
		return receipt{}, closeErr
	}
	if err := os.Rename(tmp, target); err != nil {
		_ = os.Remove(tmp)
		return receipt{}, err
	}
	digest, size, err := hashFile(target)
	if err != nil {
		return receipt{}, err
	}
	return receipt{Result: "PASS", Source: source, Target: target, SHA256: digest, Size: size}, nil
}

func selfTest() error {
	dir, err := os.MkdirTemp("", "skyrim-forge-native-")
	if err != nil {
		return err
	}
	defer os.RemoveAll(dir)
	source := filepath.Join(dir, "input.bin")
	target := filepath.Join(dir, "output.bin")
	if err := os.WriteFile(source, []byte("Skyrim Forge "+version+" native self-test\n"), 0o644); err != nil {
		return err
	}
	r, err := atomicCopy(source, target)
	if err != nil {
		return err
	}
	if r.Result != "PASS" || r.Size == 0 {
		return errors.New("invalid atomic-copy receipt")
	}
	a, _, _ := hashFile(source)
	b, _, _ := hashFile(target)
	if a != b {
		return errors.New("copy hash mismatch")
	}
	return nil
}

func printJSON(v any) {
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	_ = enc.Encode(v)
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: SkyrimForge.Native <version|self-test|hash|atomic-copy>")
		os.Exit(2)
	}
	switch os.Args[1] {
	case "version":
		fmt.Printf("SkyrimForge.Native %s go\n", version)
	case "self-test":
		if err := selfTest(); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		fmt.Println("SKYRIM FORGE NATIVE SELF-TEST: PASS")
	case "hash":
		if len(os.Args) != 3 {
			fmt.Fprintln(os.Stderr, "hash requires a path")
			os.Exit(2)
		}
		digest, size, err := hashFile(os.Args[2])
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		printJSON(receipt{Result: "PASS", Source: os.Args[2], SHA256: digest, Size: size})
	case "atomic-copy":
		if len(os.Args) != 4 {
			fmt.Fprintln(os.Stderr, "atomic-copy requires source and target")
			os.Exit(2)
		}
		r, err := atomicCopy(os.Args[2], os.Args[3])
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		printJSON(r)
	default:
		fmt.Fprintln(os.Stderr, "unknown command")
		os.Exit(2)
	}
}
