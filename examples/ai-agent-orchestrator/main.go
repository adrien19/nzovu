package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var (
	// Global flags
	serverAddr string
	insecure   bool
	verbose    bool
)

func main() {
	rootCmd := &cobra.Command{
		Use:   "ai-orchestrator",
		Short: "AI Agent Task Orchestrator - Nzovu Demo",
		Long: `AI Agent Task Orchestrator demonstrates how Nzovu orchestrates
multiple specialized AI agents working in parallel to solve complex tasks.

Features:
  • Multi-agent coordination and parallel execution
  • Priority-based task routing
  • Intelligent task decomposition using LLM
  • Long-running tasks with heartbeat renewal
  • Automatic retry with exponential backoff
  • Dead Letter Queue (DLQ) management
  • Calendar-based scheduled maintenance
  • Real-time monitoring dashboard`,
	}

	defaultServer := os.Getenv("NZOVU_SERVER")
	if defaultServer == "" {
		defaultServer = "localhost:9000"
	}
	// Global flags
	rootCmd.PersistentFlags().StringVar(&serverAddr, "server", defaultServer, "Nzovu server address")
	rootCmd.PersistentFlags().BoolVar(&insecure, "insecure", true, "Use insecure connection")
	rootCmd.PersistentFlags().BoolVarP(&verbose, "verbose", "v", false, "Verbose output")

	// Add subcommands
	rootCmd.AddCommand(newInitCommand())
	rootCmd.AddCommand(newSubmitCommand())
	rootCmd.AddCommand(newStatusCommand())
	rootCmd.AddCommand(newMonitorCommand())
	rootCmd.AddCommand(newLogsCommand())
	rootCmd.AddCommand(newResultsCommand())
	rootCmd.AddCommand(newCoordinatorCommand())
	rootCmd.AddCommand(newAgentsCommand())
	rootCmd.AddCommand(newCleanupCommand())

	if err := rootCmd.Execute(); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}
