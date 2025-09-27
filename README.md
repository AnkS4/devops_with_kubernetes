# DevOps with Kubernetes

This repository contains a collection of test applications for 'DevOps with Kubernetes' course.

## Project Structure

### Applications

1. **Log Output Application**
   - A simple Python application that continuously outputs timestamped log messages with a unique identifier
   - Location: `/log-output`
   - Generates a random UUID at startup and prints it along with an ISO 8601 formatted timestamp every 5 seconds

2. **Project/TODO Application**
   - A test application
   - Location: `/project`

3. **Ping Pong Application**
   - A simple Python application that manages a counter
   - Location: `/ping-pong`
   - Returns "pong count" with a counter that increments with each request

## System Requirements

### Common Requirements
- `git` (for version control and cloning the repository)
- `docker` (for building container images)
- `k3d` (Kubernetes in Docker, for running the application in Kubernetes)
- `kubectl` (Kubernetes command-line tool)
- `docker-buildx` plugin (for building multi-arch images)
- `make` (for using the Makefile commands)

### Additional Requirements for Log Output Application
- `kubectl-ingress-nginx` (for ingress controller)

## Quick Start

Both applications include a comprehensive Makefile that automates the entire development workflow using Docker and Kubernetes (via k3d).

```bash
make rebuild PROJECT_NAME=<project_name>
```

### Other Make Commands
- `make` or `make help` - View all available commands
- `make rebuild` - To build all projects
- `make logs PROJECT_NAME=<project_name>` - View application logs
- `make clean PROJECT_NAME=<project_name>` - Clean up all resources

## Exercises

### Chapter 2

- [1.1.](https://github.com/AnkS4/devops_with_kubernetes/tree/1.1-patch1/log_output)
- [1.2.](https://github.com/AnkS4/devops_with_kubernetes/tree/1.2/project)
- [1.3.](https://github.com/AnkS4/devops_with_kubernetes/tree/1.3/log_output)
- [1.4.](https://github.com/AnkS4/devops_with_kubernetes/tree/1.4-patch2/project)
- [1.5.](https://github.com/AnkS4/devops_with_kubernetes/tree/1.5/project)
- [1.6.](https://github.com/AnkS4/devops_with_kubernetes/tree/1.6/project)
- [1.7.](https://github.com/AnkS4/devops_with_kubernetes/tree/1.7/log_output)
- [1.8.](https://github.com/AnkS4/devops_with_kubernetes/tree/1.8/project)
- [1.9.](https://github.com/AnkS4/devops_with_kubernetes/tree/1.9/ping_pong)
- [1.10.](https://github.com/AnkS4/devops_with_kubernetes/tree/1.10/log_output)
- [1.11.](https://github.com/AnkS4/devops_with_kubernetes/tree/1.11)
- [1.12.](https://github.com/AnkS4/devops_with_kubernetes/tree/1.12)
- [1.13.](https://github.com/AnkS4/devops_with_kubernetes/tree/1.13)
- [2.1.](https://github.com/AnkS4/devops_with_kubernetes/tree/2.1)
