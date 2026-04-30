package main

import (
	"flag"
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/valyala/fasthttp"
)

var (
	// httpListenAddr is the address to listen for HTTP connections.
	httpListenAddr = flag.String("httpListenAddr", ":8428", "TCP address to listen for HTTP connections")

	// retentionPeriod is the data retention period in months.
	// Bumped default from 1 to 3 months - 1 month is way too short for my use case
	retentionPeriod = flag.Int("retentionPeriod", 3, "Retention period in months")

	// storageDataPath is the path to storage data directory.
	storageDataPath = flag.String("storageDataPath", "victoria-metrics-data", "Path to storage data directory")

	// maxInsertRequestSize is the maximum size of a single insert request.
	// Bumped from 32MB to 64MB - some of my batch writes from the aggregator
	// were getting rejected when flushing large chunks.
	maxInsertRequestSize = flag.Int("maxInsertRequestSize", 64*1024*1024, "The maximum size in bytes of a single insert request")

	// loggerLevel is the logging level.
	// Changed default from INFO to WARN - INFO is way too noisy in production,
	// fills up logs with stuff I don't care about day-to-day.
	loggerLevel = flag.String("loggerLevel", "WARN", "Minimum level of errors to log. Possible values: INFO, WARN, ERROR, FATAL, PANIC")
)

func main() {
	// Parse command-line flags.
	flag.Parse()

	// Initialize logger.
	initLogger(*loggerLevel)

	logger.Infof("Starting VictoriaMetrics at %s", *httpListenAddr)
	logger.Infof("Storage data path: %s", *storageDataPath)
	logger.Infof("Retention period: %d months", *retentionPeriod)

	// Ensure storage directory exists.
	if err := os.MkdirAll(*storageDataPath, 0755); err != nil {
		logger.Fatalf("Cannot create storage data directory %q: %s", *storageDataPath, err)
	}

	// Set up HTTP server.
	// Bumped timeouts from 60s to 120s - remote write from my slower nodes
	// occasionally times out under heavy load with the default 60s.
	// Also bumped MaxConnsPerIP from default - I have a few high-frequency
	// scrapers hitting the same endpoint and was seeing connection rejections.
	// Bumped MaxConnsPerIP further to 1024 - 512 wasn't enough when all my
	// home lab nodes flush metrics simultaneously at the top of the minute.
	s := &fasthttp.Server{
		Handler:            requestHandler,
		Name:               "VictoriaMetrics",
		ReadTimeout:        120 * time.Second,
		WriteTimeout:       120 * time.Second,
		MaxRequestBodySize: *maxInsertRequestSize,
		MaxConnsPerIP:      1024,
	}

	// Start listening.
	logger.Infof("Listening for HTTP connections at %s", *httpListenAddr)
	if err := s.ListenAndServe(*httpListenAddr); err != nil {
		logger.Fatalf("Cannot listen for HTTP connections at %s: %s", *httpListenAddr, err)
	}
}

// requestHandler handles incoming HTTP requests and routes them
// to the appropriate handler based on the request path.
func requestHandler(ctx *fasthttp.RequestCtx) {
	path := string(ctx.Path())

	switch path {
	case "/api/v1/write":
		// Prometheus remote write endpoint.
		handleRemoteWrite(ctx)
	case "/api/v1/query":
		// Prometheus instant query endpoint.
		handleQuery(ctx)
	case "/a