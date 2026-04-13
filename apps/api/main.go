// API server — simple HTTP service that returns JSON.
// Demonstrates: health checks, version injection via env var, JSON responses.
package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"
)

func main() {
	version := os.Getenv("APP_VERSION")
	if version == "" {
		version = "dev"
	}

	// /health — used by ALB target group health check and Kubernetes probes.
	// Must return 200 quickly — no dependencies, no logic.
	http.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		fmt.Fprint(w, "ok")
	})

	// / — returns a JSON response with version info.
	// The frontend calls this to display the current deployed version.
	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		w.Header().Set("Access-Control-Allow-Origin", "*") // allow the frontend to call this
		if err := json.NewEncoder(w).Encode(map[string]string{
			"message":   "Hello from the API",
			"version":   version,
			"timestamp": time.Now().UTC().Format(time.RFC3339),
			"status":    "ok",
		}); err != nil {
			http.Error(w, "encode error", http.StatusInternalServerError)
		}
	})

	port := "8080"
	log.Printf("API server starting — version=%s port=%s", version, port)
	log.Fatal(http.ListenAndServe(":"+port, nil))
}
 
