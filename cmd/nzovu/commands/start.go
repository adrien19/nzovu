package commands

import (
	"fmt"

	"github.com/spf13/cobra"

	"github.com/adrien19/nzovu/cmd/nzovu/outputs"
	"github.com/adrien19/nzovu/internal/server"
)

// NewStartCommand creates the start command group
func NewStartCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "start",
		Short: "Start Nzovu server (legacy)",
		Long: `Start a Nzovu server instance with various configuration options.

Note: This command is provided for backward compatibility. The recommended 
approach is to use 'nzovu server' directly.

Examples:
  nzovu start --dev-server
  nzovu start dev-server --log-level debug`,
		RunE: runStart,
	}

	// Add flags for direct dev server access
	config := server.DefaultConfig()
	server.AddServerFlags(cmd, config)
	cmd.Flags().Bool("dev-server", false, "Start in development server mode")

	cmd.AddCommand(newDevServerCommand())

	return cmd
}

// runStart handles the direct start command with --dev-server flag
func runStart(cmd *cobra.Command, args []string) error {
	devServer, _ := cmd.Flags().GetBool("dev-server")

	if devServer {
		// Run the dev server directly
		return runDevServer(cmd, args)
	}

	// If no --dev-server flag, show help
	return cmd.Help()
}

// newDevServerCommand creates the dev server subcommand
func newDevServerCommand() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "dev-server",
		Short: "Start a development Nzovu server",
		Long: `Start a Nzovu server configured for local development.
This starts both gRPC and HTTP gateway servers with development-friendly defaults.

The server will use SQLite for storage by default. You can specify a different
storage backend (PostgreSQL or SQLite) using the --storage-type flag.

Examples:
  nzovu start dev-server
  nzovu start dev-server --storage-type postgres
  nzovu start dev-server --grpc-addr :9001 --http-addr :8081
  nzovu start dev-server --log-level debug`,
		RunE: runDevServer,
	}

	// Add server configuration flags
	config := server.DefaultConfig()
	server.AddServerFlags(cmd, config)

	return cmd
}

// runDevServer handles the dev server command execution
func runDevServer(cmd *cobra.Command, args []string) error {
	// Parse configuration from flags
	config, err := server.ParseConfigFromFlags(cmd, server.DefaultConfig())
	if err != nil {
		return fmt.Errorf("failed to parse configuration: %w", err)
	}

	// Force development mode
	config.IsDevelopment = true

	// Print CLI-specific startup messages
	outputs.PrintSuccess("Development server configuration loaded successfully")
	outputs.PrintInfo(fmt.Sprintf("gRPC server will listen on: %s", config.GRPCAddr))
	outputs.PrintInfo(fmt.Sprintf("HTTP gateway will listen on: %s", config.HTTPAddr))
	outputs.PrintInfo(fmt.Sprintf("Storage backend: %s", config.StorageType))
	outputs.PrintInfo(fmt.Sprintf("Log level: %s", config.LogLevel))
	outputs.PrintInfo("Press Ctrl+C to stop the server")

	// Create and start server using the new server package
	srv, err := server.New(config)
	if err != nil {
		outputs.PrintError(fmt.Sprintf("Failed to create server: %v", err))
		return fmt.Errorf("failed to create server: %w", err)
	}

	ctx := cmd.Context()
	if err := srv.Start(ctx); err != nil {
		outputs.PrintError(fmt.Sprintf("Server error: %v", err))
		return err
	}

	outputs.PrintSuccess("Development server stopped successfully")
	return nil
}
