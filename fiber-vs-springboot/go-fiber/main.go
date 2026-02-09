package main

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"net/http"
	"time"

	"github.com/gofiber/fiber/v3"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

type HashResponse struct {
	Hash      string `json:"hash"`
	Timestamp int64  `json:"timestamp"`
	Source    string `json:"source"`
}

var hashSeed = []byte("benchmark-test-data")

func main() {
	// Start Prometheus metrics server on port 2112
	// The default Go collector automatically exports go_goroutines
	go func() {
		http.Handle("/metrics", promhttp.Handler())
		fmt.Println("Prometheus metrics server starting on :2112")
		if err := http.ListenAndServe(":2112", nil); err != nil {
			panic(err)
		}
	}()

	app := fiber.New()

	app.Get("/hash", hashHandler)
	app.Get("/health", healthHandler)

	fmt.Println("Fiber server starting on :3000")
	if err := app.Listen(":3000"); err != nil {
		panic(err)
	}
}

func hashHandler(c fiber.Ctx) error {
	// Keep the hash loop allocation-free:
	// - sha256.Sum256 returns a fixed-size array
	// - input is reused without building new slices per iteration
	sum := sha256.Sum256(hashSeed)
	for i := 1; i < 100; i++ {
		sum = sha256.Sum256(sum[:])
	}

	response := HashResponse{
		Hash:      hex.EncodeToString(sum[:]),
		Timestamp: time.Now().UnixMilli(),
		Source:    "go-fiber",
	}

	return c.JSON(response)
}

func healthHandler(c fiber.Ctx) error {
	return c.SendStatus(http.StatusOK)
}
