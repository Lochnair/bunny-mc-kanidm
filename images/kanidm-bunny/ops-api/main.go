package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"time"
)

const configPath = "/data/server.toml"

type commandResult struct {
	OK       bool   `json:"ok"`
	Command  string `json:"command"`
	Stdout   string `json:"stdout"`
	Stderr   string `json:"stderr"`
	ExitCode int    `json:"exit_code"`
	Timeout  bool   `json:"timeout"`
}

type apiError struct {
	Error string `json:"error"`
}

func main() {
	bind := envDefault("OPS_BINDADDRESS", "127.0.0.1:9080")
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", healthz)
	mux.HandleFunc("GET /version", version)
	mux.HandleFunc("GET /replication/certificate", replicationCertificate)
	mux.HandleFunc("POST /replication/refresh-consumer", refreshConsumer)
	mux.HandleFunc("POST /account/recover", recoverAccount)
	mux.HandleFunc("GET /config/redacted", redactedConfig)

	log.Printf("[kanidm-ops-api] listening on %s", bind)
	if err := http.ListenAndServe(bind, logRequests(mux)); err != nil {
		log.Fatalf("[kanidm-ops-api] server failed: %v", err)
	}
}

func healthz(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func version(w http.ResponseWriter, r *http.Request) {
	res := runCommand(r.Context(), []string{"version"})
	writeCommandResponse(w, res)
}

func replicationCertificate(w http.ResponseWriter, r *http.Request) {
	if isTrue(os.Getenv("OPS_REQUIRE_AUTH_FOR_READS")) && !authorized(r) {
		writeJSON(w, http.StatusUnauthorized, apiError{Error: "missing or invalid bearer token"})
		return
	}
	res := runCommand(r.Context(), []string{"show-replication-certificate", "-c", configPath})
	writeCommandResponse(w, res)
}

func refreshConsumer(w http.ResponseWriter, r *http.Request) {
	if !authorized(r) {
		writeJSON(w, http.StatusUnauthorized, apiError{Error: "missing or invalid bearer token"})
		return
	}
	res := runCommand(r.Context(), []string{"refresh-replication-consumer", "-c", configPath})
	writeCommandResponse(w, res)
}

func recoverAccount(w http.ResponseWriter, r *http.Request) {
	if !authorized(r) {
		writeJSON(w, http.StatusUnauthorized, apiError{Error: "missing or invalid bearer token"})
		return
	}
	if !isTrue(os.Getenv("OPS_ENABLE_RECOVERY")) {
		writeJSON(w, http.StatusForbidden, apiError{Error: "account recovery is disabled"})
		return
	}

	var req struct {
		Account string `json:"account"`
	}
	dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1024))
	dec.DisallowUnknownFields()
	if err := dec.Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, apiError{Error: "invalid JSON body"})
		return
	}
	account := strings.TrimSpace(req.Account)
	if account == "" {
		writeJSON(w, http.StatusBadRequest, apiError{Error: "account is required"})
		return
	}

	res := runCommand(r.Context(), []string{"recover-account", account, "-c", configPath})
	writeCommandResponse(w, res)
}

func redactedConfig(w http.ResponseWriter, r *http.Request) {
	if !authorized(r) {
		writeJSON(w, http.StatusUnauthorized, apiError{Error: "missing or invalid bearer token"})
		return
	}
	data, err := os.ReadFile(configPath)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, apiError{Error: "could not read config"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"config": redactConfig(string(data))})
}

func runCommand(parent context.Context, args []string) commandResult {
	timeout := commandTimeout()
	ctx, cancel := context.WithTimeout(parent, timeout)
	defer cancel()

	cmd := exec.CommandContext(ctx, "kanidmd", args...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()
	res := commandResult{
		OK:       err == nil,
		Command:  "kanidmd " + strings.Join(args, " "),
		Stdout:   stdout.String(),
		Stderr:   stderr.String(),
		ExitCode: 0,
		Timeout:  errors.Is(ctx.Err(), context.DeadlineExceeded),
	}
	if err == nil {
		return res
	}

	res.ExitCode = 1
	var exitErr *exec.ExitError
	if errors.As(err, &exitErr) {
		res.ExitCode = exitErr.ExitCode()
	}
	return res
}

func writeCommandResponse(w http.ResponseWriter, res commandResult) {
	if res.OK {
		writeJSON(w, http.StatusOK, res)
		return
	}
	if res.Timeout {
		writeJSON(w, http.StatusGatewayTimeout, res)
		return
	}
	writeJSON(w, http.StatusInternalServerError, res)
}

func authorized(r *http.Request) bool {
	token := os.Getenv("OPS_ADMIN_TOKEN")
	if token == "" {
		return false
	}
	const prefix = "Bearer "
	header := r.Header.Get("Authorization")
	return strings.HasPrefix(header, prefix) && strings.TrimPrefix(header, prefix) == token
}

func commandTimeout() time.Duration {
	raw := envDefault("OPS_COMMAND_TIMEOUT_SECONDS", "30")
	seconds, err := strconv.Atoi(raw)
	if err != nil || seconds <= 0 {
		return 30 * time.Second
	}
	return time.Duration(seconds) * time.Second
}

func redactConfig(input string) string {
	var out []string
	for _, line := range strings.Split(input, "\n") {
		key := strings.ToLower(strings.TrimSpace(strings.SplitN(line, "=", 2)[0]))
		switch {
		case key == "partner_cert",
			strings.Contains(key, "password"),
			strings.Contains(key, "secret"),
			strings.Contains(key, "token"),
			strings.Contains(key, "auth_key"):
			out = append(out, fmt.Sprintf("%s = \"<redacted>\"", strings.TrimSpace(strings.SplitN(line, "=", 2)[0])))
		default:
			out = append(out, line)
		}
	}
	return strings.Join(out, "\n")
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(value); err != nil {
		log.Printf("[kanidm-ops-api] failed to write response: %v", err)
	}
}

func logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		log.Printf("[kanidm-ops-api] %s %s", r.Method, r.URL.Path)
		next.ServeHTTP(w, r)
	})
}

func envDefault(name, fallback string) string {
	if value := os.Getenv(name); value != "" {
		return value
	}
	return fallback
}

func isTrue(value string) bool {
	switch strings.ToLower(value) {
	case "true", "1", "yes", "on":
		return true
	default:
		return false
	}
}
