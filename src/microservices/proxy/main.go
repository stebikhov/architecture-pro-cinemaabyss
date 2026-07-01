package main

import (
	"encoding/json"
	"io"
	"log"
	"math/rand"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

type ProxyConfig struct {
	Port                  string
	MonolithURL           string
	MoviesServiceURL      string
	EventsServiceURL      string
	GradualMigration      bool
	MoviesMigrationPercent int
}

func main() {
	config := loadConfig()
	
	mux := http.NewServeMux()
	mux.HandleFunc("/health", healthHandler)
	mux.HandleFunc("/api/", proxyHandler(config))
	
	log.Printf("Proxy service starting on port %s", config.Port)
	log.Printf("Monolith URL: %s", config.MonolithURL)
	log.Printf("Movies Service URL: %s", config.MoviesServiceURL)
	log.Printf("Events Service URL: %s", config.EventsServiceURL)
	log.Printf("Gradual Migration: %v", config.GradualMigration)
	log.Printf("Movies Migration Percent: %d%%", config.MoviesMigrationPercent)
	
	log.Fatal(http.ListenAndServe(":"+config.Port, mux))
}

func loadConfig() *ProxyConfig {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8000"
	}
	
	gradualMigration := false
	if os.Getenv("GRADUAL_MIGRATION") == "true" {
		gradualMigration = true
	}
	
	migrationPercent := 0
	if percent := os.Getenv("MOVIES_MIGRATION_PERCENT"); percent != "" {
		if p, err := strconv.Atoi(percent); err == nil {
			migrationPercent = p
		}
	}
	
	return &ProxyConfig{
		Port:                  port,
		MonolithURL:           os.Getenv("MONOLITH_URL"),
		MoviesServiceURL:      os.Getenv("MOVIES_SERVICE_URL"),
		EventsServiceURL:      os.Getenv("EVENTS_SERVICE_URL"),
		GradualMigration:      gradualMigration,
		MoviesMigrationPercent: migrationPercent,
	}
}

func healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]bool{"status": true})
}

func proxyHandler(config *ProxyConfig) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		path := r.URL.Path
		log.Printf("Proxy received request: %s %s", r.Method, path)
		
		targetURL := selectTarget(config, path)
		log.Printf("Routing to: %s", targetURL)
		
		proxyRequest(w, r, targetURL)
	}
}

func selectTarget(config *ProxyConfig, path string) string {
	switch {
	case strings.HasPrefix(path, "/api/movies"):
		return selectMoviesTarget(config)
	case strings.HasPrefix(path, "/api/events"):
		return config.EventsServiceURL
	case strings.HasPrefix(path, "/api/users"),
	     strings.HasPrefix(path, "/api/payments"),
	     strings.HasPrefix(path, "/api/subscriptions"),
	     strings.HasPrefix(path, "/health"):
		return config.MonolithURL
	default:
		return config.MonolithURL
	}
}

func selectMoviesTarget(config *ProxyConfig) string {
	if !config.GradualMigration {
		log.Println("Gradual migration disabled, routing to movies-service")
		return config.MoviesServiceURL
	}
	
	randomPercent := rand.Intn(100)
	if randomPercent < config.MoviesMigrationPercent {
		log.Printf("Random %d < %d, routing to movies-service", randomPercent, config.MoviesMigrationPercent)
		return config.MoviesServiceURL
	}
	
	log.Printf("Random %d >= %d, routing to monolith", randomPercent, config.MoviesMigrationPercent)
	return config.MonolithURL
}

func proxyRequest(w http.ResponseWriter, r *http.Request, targetURL string) {
	target, err := url.Parse(targetURL)
	if err != nil {
		log.Printf("Error parsing target URL: %v", err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}
	
	target.Path = r.URL.Path
	target.RawQuery = r.URL.RawQuery
	
	proxyReq, err := http.NewRequest(r.Method, target.String(), r.Body)
	if err != nil {
		log.Printf("Error creating proxy request: %v", err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}
	
	copyHeaders(proxyReq.Header, r.Header)
	
	client := &http.Client{
		Timeout: 30 * time.Second,
	}
	
	resp, err := client.Do(proxyReq)
	if err != nil {
		log.Printf("Error forwarding request: %v", err)
		http.Error(w, "Service Unavailable", http.StatusBadGateway)
		return
	}
	defer resp.Body.Close()
	
	copyHeaders(w.Header(), resp.Header)
	w.WriteHeader(resp.StatusCode)
	
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		log.Printf("Error reading response body: %v", err)
		http.Error(w, "Internal Server Error", http.StatusInternalServerError)
		return
	}
	
	w.Write(body)
}

func copyHeaders(dst, src http.Header) {
	for key, values := range src {
		for _, value := range values {
			dst.Add(key, value)
		}
	}
}

func init() {
	rand.Seed(time.Now().UnixNano())
}
