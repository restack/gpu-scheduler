# GPU Scheduler for Kubernetes

The GPU Scheduler is a Kubernetes extension designed to provide smart, atomic, and topology-aware GPU allocation for workloads. It addresses limitations in the default Kubernetes scheduler by offering fine-grained control over GPU resources, ensuring efficient utilization and preventing race conditions.

## Features

- **Atomic Allocation**: Uses Kubernetes Coordination Leases to lock GPUs, preventing double-booking and race conditions.
- **Topology Awareness**: Optimizes GPU assignment based on NVLink topology to maximize bandwidth for multi-GPU workloads.
- **Fine-Grained Control**: Supports requesting specific GPU counts, contiguous allocation policies, and specific GPU IDs.
- **Three-Component Architecture**: Scheduler Plugin, Webhook, and Agent.

## Documentation

For detailed documentation, including installation, usage, and architecture, please refer to the [docs/](docs/README.md).

- [Architecture](docs/architecture.md)
- [Usage Guide](docs/usage.md)
- [Development Guide](docs/development.md)
- [Docker Guide](docs/docker.md)
- [API Reference](docs/api-reference.md)
- [RBAC](docs/rbac.md)
- [Webhook Certificates](docs/webhook-certificates.md)

## Quick Start

### Installation

```bash
# Install with Helm
helm install gpu-scheduler charts/gpu-scheduler
```

For full installation instructions, including certificate setup, see the [Installation Guide](docs/README.md#installation).
