# Log Output Application

This is a simple Python application that continuously outputs timestamped log messages with a unique identifier. The application generates a random UUID at startup and then prints it along with an ISO 8601 formatted timestamp every 5 seconds.

## Requirements

### System Requirements
- Git (for version control and cloning the repository)
- Docker (for building container images)
- k3d (Kubernetes in Docker, for running the application in Kubernetes)
- kubectl (Kubernetes command-line tool)
- Make (for using the Makefile commands)

### Other Dependencies (Handled by the Makefile via Dockerfile)
- Python 3.12+ (for running the application directly)
- Standard Python libraries (no external packages required)

## What the Application Does

The main application (`app.py`) performs the following operations:
- Generates a random UUID string when the application starts
- Enters an infinite loop that:
  - Gets the current UTC timestamp
  - Formats it as ISO 8601 with milliseconds (e.g., `2024-01-15T10:30:45.123Z`)
  - Prints the timestamp followed by the UUID
  - Waits 5 seconds before repeating

This creates a continuous stream of timestamped log entries, making it useful for testing log aggregation systems, monitoring setups, or demonstrating containerized applications.

## Using the Makefile

The project includes a comprehensive Makefile that automates the entire development workflow using Docker and Kubernetes (via k3d).

### Getting Started

Here are the recommended steps to get started:

```bash
# 1. Start the application with kubernetes (via k3d)
#   - Checks dependencies
#   - Cleans up existing resources
#   - Builds Docker image
#   - Creates k3d cluster
#   - Deploys application
make rebuild

# or with detailed debug output
make rebuild DEBUG_ENABLED=true

# 2. View application logs in real-time
make logs

# 3. Clean up all resources
#   - Deletes pod
#   - Removes k3d cluster
#   - Cleans Docker image
make clean

# View all available commands
make help
```

### Additional Notes

- The application is designed to run in a containerized environment
- All timestamps are in UTC to maintain consistency across different time zones
- The UUID remains constant throughout the application's lifetime until restart

