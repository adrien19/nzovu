package main

import (
	"context"
	"fmt"
	"os"

	"github.com/spf13/cobra"

	"github.com/adrien19/nzovu/cmd/nzovu/commands"
	"github.com/adrien19/nzovu/internal/server"
	"github.com/adrien19/nzovu/pkg/version"
)

func main() {
	ctx := context.Background()

	rootCmd := &cobra.Command{
		Use:   "nzovu",
		Short: "Nzovu - A powerful message queue management tool",
		Long: `Nzovu is a high-performance message queue system with scheduling capabilities.

This unified CLI provides both server operations and client management commands.

Examples:
  # Start development server
  nzovu server --dev

  # Start production server
  nzovu server --grpc-addr :9000 --http-addr :8080

  # Client operations
  nzovu queue create my-queue --type simple
  nzovu message post my-queue "Hello World" --id hello-1
  nzovu message get my-queue
  nzovu schedule create my-queue "Scheduled task" --cron "*/5 * * * *"`,
		Version: version.Info(),
	}

	// Global flags for client operations
	rootCmd.PersistentFlags().String("server", "localhost:8080", "Nzovu server address")
	rootCmd.PersistentFlags().Bool("insecure", false, "Use insecure connection (no TLS)")
	rootCmd.PersistentFlags().String("cert-file", "", "Path to client certificate file")
	rootCmd.PersistentFlags().String("key-file", "", "Path to client private key file")
	rootCmd.PersistentFlags().String("ca-file", "", "Path to CA certificate file")
	rootCmd.PersistentFlags().String("api-key", "", "API key for server authentication")
	rootCmd.PersistentFlags().String("output", "table", "Output format (table, json, yaml)")
	rootCmd.PersistentFlags().Bool("verbose", false, "Enable verbose output")
	rootCmd.PersistentFlags().Duration("timeout", 0, "Request timeout (0 for no timeout)")

	// Add command groups
	rootCmd.AddCommand(newServerCommand())
	rootCmd.AddCommand(commands.NewQueueCommand())
	rootCmd.AddCommand(commands.NewMessageCommand())
	rootCmd.AddCommand(commands.NewScheduleCommand())
	rootCmd.AddCommand(commands.NewDLQCommand())
	rootCmd.AddCommand(commands.NewSchemaCommand()) // Schema registry commands
	rootCmd.AddCommand(commands.NewWebUICommand())  // Web UI
	rootCmd.AddCommand(commands.NewStartCommand())  // Legacy compatibility

	// Execute root command
	if err := rootCmd.ExecuteContext(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

// newServerCommand creates the unified server command
func newServerCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "server",
		Short: "Start Nzovu server",
		Long: `Start a Nzovu server instance.

This command starts both gRPC and HTTP gateway servers. Use --dev for development
mode with additional features like API documentation and CORS enabled.

Storage Backends:
  - PostgreSQL (default): enterprise-grade relational database
  - SQLite: Development/testing backend, single-file database (requires CGO)

Examples:
  # Development server with defaults (PostgreSQL)
  nzovu server --dev

  # Development server with SQLite (convenience flags)
  nzovu server --dev --database nzovu.db
  nzovu server --dev --db ./data/nzovu.db
  nzovu server --dev -d nzovu.db

  # Development server with SQLite (explicit)
  nzovu server --dev --storage-type sqlite --sqlite-db-path ./nzovu.db

  # Production server with PostgreSQL
  API_KEYS=secret METRICS_BEARER_TOKEN=metrics-secret CERT_FILE=server.crt KEY_FILE=server.key POSTGRES_PASSWORD=secret ENCRYPTION_KEY_SOURCE_TYPE=VAULT nzovu server --production --storage-type postgres --postgres-sslmode verify-full --postgres-root-cert root.crt

  # Server with TLS enabled
  nzovu server --enable-tls --cert-file server.crt --key-file server.key`,
		RunE: runServer,
	}

	// Server configuration flags
	config := server.DefaultConfig()
	cmd.AddCommand(commands.NewServerCommand().Commands()...)
	server.AddServerFlags(cmd, config)

	// Add mode flags
	cmd.Flags().Bool("dev", false, "Start in development mode (enables CORS, API docs, reflection)")
	cmd.Flags().Bool("production", false, "Start in production mode (optimized for production use)")

	return cmd
}

// runServer handles the server command execution
func runServer(cmd *cobra.Command, args []string) error {
	// Determine configuration based on mode
	var config *server.Config

	devMode, _ := cmd.Flags().GetBool("dev")
	prodMode, _ := cmd.Flags().GetBool("production")

	if devMode && prodMode {
		return fmt.Errorf("cannot specify both --dev and --production modes")
	}

	if devMode {
		config = server.DefaultConfig() // Development mode
		config.IsDevelopment = true
	} else if prodMode {
		config = server.ProductionConfig() // Production mode
		config.IsDevelopment = false
	} else {
		// Default mode - development for ease of use
		config = server.DefaultConfig()
		config.IsDevelopment = true
	}

	// Parse configuration from flags
	parsedConfig, err := server.ParseConfigFromFlags(cmd, config)
	if err != nil {
		return fmt.Errorf("failed to parse configuration: %w", err)
	}

	config = parsedConfig

	// Inject version information
	config.Version = version.Short()
	config.GitCommit = version.GitCommit
	config.BuildDate = version.BuildDate

	// Create and start server
	srv, err := server.New(config)
	if err != nil {
		return fmt.Errorf("failed to create server: %w", err)
	}

	ctx := cmd.Context()
	return srv.Start(ctx)
}
