# TODO Application

A todo application built with FastAPI and Docker.

## Requirements

### System Requirements
- `git` (for version control and cloning the repository)
- `docker` (for building container images)
- `k3d` (Kubernetes in Docker, for running the application in Kubernetes)
- `kubectl` (Kubernetes command-line tool)
- `docker-buildx` plugin (for building multi-arch images)
- `make` (for using the Makefile commands)

### Other Dependencies (Handled by the Makefile via Dockerfile)
- `python` 3.12+ (for running the application directly)
- `uvicorn`
- `fastapi`

## Quick Start
The project includes a comprehensive Makefile that automates the entire development workflow using Docker and Kubernetes (via k3d).

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

# 2. Verify the application is running
make logs

# 3. Clean up all resources
#   - Deletes pod
#   - Removes k3d cluster
#   - Cleans Docker image
make clean

# View all available commands
make help
```

## Troubleshooting

### Common Issues

1. **Missing Dependencies**
   - Install required system dependencies using package manager
   - Verify versions match minimum requirements

2. **Permission Errors**
   - Run commands with sudo if necessary
   - Check Docker socket permissions

3. **Resource Cleanup**
   - Use `make clean` to remove all resources
   - Check for orphaned containers/images with `docker ps -a` and `docker images`

## Additional Notes

- The application is designed to run in a containerized environment

