package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/segmentio/kafka-go"
)

type Event struct {
	Type      string                 `json:"type"`
	Payload   map[string]interface{} `json:"payload"`
	Timestamp time.Time              `json:"timestamp"`
}

type EventsService struct {
	kafkaBrokers []string
	producers    map[string]*kafka.Writer
	consumers    map[string]*kafka.Reader
}

func NewEventsService(brokers []string) *EventsService {
	return &EventsService{
		kafkaBrokers: brokers,
		producers:    make(map[string]*kafka.Writer),
		consumers:    make(map[string]*kafka.Reader),
	}
}

func (s *EventsService) getProducer(topic string) (*kafka.Writer, error) {
	if _, exists := s.producers[topic]; !exists {
		s.producers[topic] = &kafka.Writer{
			Addr:     kafka.TCP(s.kafkaBrokers...),
			Topic:    topic,
			Balancer: &kafka.LeastBytes{},
		}
	}
	return s.producers[topic], nil
}

func (s *EventsService) PublishEvent(topic string, event Event) error {
	writer, err := s.getProducer(topic)
	if err != nil {
		return fmt.Errorf("failed to get producer: %w", err)
	}

	eventBytes, err := json.Marshal(event)
	if err != nil {
		log.Printf("Failed to marshal event: %v", err)
		return fmt.Errorf("failed to marshal event: %w", err)
	}

	msg := kafka.Message{
		Key:   []byte(event.Type),
		Value: eventBytes,
		Time:  time.Now(),
	}

	maxRetries := 3
	var lastErr error
	for i := 0; i < maxRetries; i++ {
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		log.Printf("Attempting to write message to %s (attempt %d/%d)", topic, i+1, maxRetries)
		err := writer.WriteMessages(ctx, msg)
		cancel()
		if err == nil {
			log.Printf("Published event to %s: %s", topic, event.Type)
			return nil
		}
		lastErr = err
		log.Printf("Failed to write message to %s (attempt %d/%d): %v", topic, i+1, maxRetries, err)
		if i < maxRetries-1 {
			time.Sleep(2 * time.Second)
		}
	}

	return fmt.Errorf("failed to write message after %d retries: %w", maxRetries, lastErr)
}

func (s *EventsService) StartConsuming(topic string) {
	reader := kafka.NewReader(kafka.ReaderConfig{
		Brokers:  s.kafkaBrokers,
		Topic:    topic,
		GroupID:  "events-service-group",
		MinBytes: 10e3,
		MaxBytes: 10e6,
	})
	s.consumers[topic] = reader

	go func() {
		ctx := context.Background()
		for {
			msg, err := reader.FetchMessage(ctx)
			if err != nil {
				log.Printf("Error fetching message from %s: %v", topic, err)
				continue
			}

			var event Event
			if err := json.Unmarshal(msg.Value, &event); err == nil {
				log.Printf("Consumed event from %s: Type=%s, Payload=%v",
					topic, event.Type, event.Payload)
			}

			if err := reader.CommitMessages(ctx, msg); err != nil {
				log.Printf("Error committing message: %v", err)
			}
		}
	}()

	log.Printf("Started consuming from topic: %s", topic)
}

func main() {
	brokers := strings.Split(os.Getenv("KAFKA_BROKERS"), ",")
	if len(brokers) == 0 || brokers[0] == "" {
		brokers = []string{"localhost:9092"}
	}

	service := NewEventsService(brokers)

	topics := []string{"movie-events", "user-events", "payment-events"}
	for _, topic := range topics {
		service.StartConsuming(topic)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/health", service.healthHandler)
	mux.HandleFunc("/api/events/health", service.healthHandler)
	mux.HandleFunc("/api/events/publish", service.publishEventHandler)
	mux.HandleFunc("/api/events/movie", service.movieEventHandler)
	mux.HandleFunc("/api/events/user", service.userEventHandler)
	mux.HandleFunc("/api/events/payment", service.paymentEventHandler)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8082"
	}

	log.Printf("Events service starting on port %s", port)
	log.Fatal(http.ListenAndServe(":"+port, mux))
}

func (s *EventsService) healthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]bool{"status": true})
}

func (s *EventsService) publishEventHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var req struct {
		Topic   string                 `json:"topic"`
		Type    string                 `json:"type"`
		Payload map[string]interface{} `json:"payload"`
	}

	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	event := Event{
		Type:      req.Type,
		Payload:   req.Payload,
		Timestamp: time.Now(),
	}

	if err := s.PublishEvent(req.Topic, event); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]string{
		"status":    "published",
		"topic":     req.Topic,
		"eventType": req.Type,
	})
}

func (s *EventsService) movieEventHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var payload map[string]interface{}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	event := Event{
		Type:      "movie_event",
		Payload:   payload,
		Timestamp: time.Now(),
	}

	if err := s.PublishEvent("movie-events", event); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]string{
		"status": "success",
	})
}

func (s *EventsService) userEventHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var payload map[string]interface{}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	event := Event{
		Type:      "user_event",
		Payload:   payload,
		Timestamp: time.Now(),
	}

	if err := s.PublishEvent("user-events", event); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]string{
		"status": "success",
	})
}

func (s *EventsService) paymentEventHandler(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var payload map[string]interface{}
	if err := json.NewDecoder(r.Body).Decode(&payload); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	event := Event{
		Type:      "payment_event",
		Payload:   payload,
		Timestamp: time.Now(),
	}

	if err := s.PublishEvent("payment-events", event); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(map[string]string{
		"status": "success",
	})
}
