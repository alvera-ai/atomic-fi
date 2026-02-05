# Introduction

Welcome to the Payment Compliance Platform - a specialized system for screening payments and account holders against international sanctions lists with manual review and override capabilities.

## Overview

This platform provides comprehensive sanctions screening and compliance management for financial institutions:

- **Sanctions Screening**: Automated screening against US OFAC, CSL, and other watchlists
- **Onboarding Compliance**: Screen new account holders (individuals and businesses) during onboarding
- **Payment Monitoring**: Verify transactions against sanctioned entities
- **Manual Review**: Human oversight with review workflows and override capabilities
- **Multi-Tenancy**: Isolated data and compliance decisions per financial institution
- **Audit Trail**: Complete history of screening decisions and manual overrides
- **REST API**: OpenAPI-documented endpoints for integration with existing systems

## Project Goals

This platform aims to:

1. **Automate compliance**: Reduce manual screening workload with intelligent automation
2. **Prevent violations**: Block transactions involving sanctioned individuals or entities
3. **Enable oversight**: Provide compliance officers with tools for manual review and overrides
4. **Ensure auditability**: Maintain complete records of all screening decisions
5. **Scale efficiently**: Multi-tenant architecture supporting multiple financial institutions

## What's Included

### Compliance Features

- **Sanctions Screening**: Integration with Watchman screening service
- **Onboarding Screening**: Screen account holders (individuals and businesses) during sign-up
- **Match Scoring**: Configurable match thresholds (default: 70% similarity)
- **Entity Screening**: Screen individuals, companies, addresses, and contacts
- **Decision Management**: Track screening results (pass, potential_match, blocked)
- **Manual Override**: Compliance officer review and approval workflows
- **Audit Logging**: Complete history of screening decisions and overrides

### Sanctions Data Sources

- **US OFAC** (Office of Foreign Assets Control) - ~18,598 entities
- **US CSL** (Consolidated Screening List) - ~6,482 entities
- **US Non-SDN** (Non-Specially Designated Nationals) - ~462 entities
- **US FinCEN 311** (Section 311 Special Measures) - ~35 entities
- **Real-time Updates**: Automatic synchronization with latest sanctions data

### Technical Stack

- Phoenix 1.8.3 with LiveView 1.0+
- PostgreSQL with Ecto 3.12+ (multi-tenant with RLS)
- Watchman API integration for sanctions screening
- OpenAPI 3.0 specification with auto-generated schemas
- User authentication with 2FA support
- Oban for background screening jobs

### Development Tools

- Custom Alvera generators (alvera.gen.*)
- Tidewave MCP for AI-assisted development
- Code quality tools (Credo, Sobelow, Dialyxir)
- Comprehensive testing (ExUnit with 100% coverage goal)
- ExDoc documentation with guides

### DevOps

- Docker multi-arch builds (amd64/arm64)
- GitHub Actions CI/CD
- Structured logging with logger_json
- Multi-environment configuration (dev/test/prod)

## What's NOT Included

This platform currently excludes (but may be added in future versions):

- **Transaction Monitoring**: Real-time payment screening (coming soon)
- **Risk Scoring**: ML-based risk assessment algorithms
- **Case Management**: Full workflow system for compliance investigations
- **Reporting Dashboard**: Analytics and compliance reporting UI
- **Bulk Screening**: Batch screening of existing customer databases
- **Custom Watchlists**: Institution-specific screening lists
- **Oban Pro**: Using free version (can be upgraded for better performance)

These features are planned for future releases as the platform matures.

## Architecture

The platform follows a compliance-focused layered architecture:

```
┌─────────────────────────────────────┐
│         Web Layer (Phoenix)          │
│  ┌──────────────┬─────────────────┐ │
│  │  LiveView    │   REST API      │ │
│  │  (Reviews)   │  (Screening)    │ │
│  └──────────────┴─────────────────┘ │
└─────────────────────────────────────┘
              ↓
┌─────────────────────────────────────┐
│       Context Layer (Business)       │
│  ┌──────────┬──────────┬──────────┐ │
│  │ Account  │ Decision │  Manual  │ │
│  │ Holders  │ Context  │ Override │ │
│  └──────────┴──────────┴──────────┘ │
└─────────────────────────────────────┘
              ↓
┌─────────────────────────────────────┐
│  External Services (Watchman API)    │
│    US OFAC, CSL, Non-SDN, FinCEN    │
└─────────────────────────────────────┘
              ↓
┌─────────────────────────────────────┐
│      Data Layer (Ecto/Postgres)      │
│         Multi-Tenant (RLS)           │
└─────────────────────────────────────┘
```

## Screening Workflow

```
Onboarding Request (Individual/Business)
              ↓
    Screen Interested Parties
    (Individuals + Companies)
              ↓
    Watchman API Search
    (minMatch: 0.7 threshold)
              ↓
    Decision Generation
    ┌─────────┬─────────┬─────────┐
    │  Pass   │ Potential│ Blocked │
    │         │  Match   │         │
    └─────────┴─────────┴─────────┘
              ↓
    Manual Review (if needed)
              ↓
    Override/Approve/Reject
```

## Multi-Tenancy Model

All screening data is scoped by `tenant_id` (financial institution):

```
Tenant (financial institution)
  ├── User (compliance officers)
  ├── AccountHolder (customers)
  ├── Decision (screening results)
  └── Override (manual reviews)
```

See [Multi-Tenancy Guide](multi-tenancy.md) for details.

## Getting Started

New to this platform? Start here:

1. [Getting Started](getting-started.md) - Setup and configuration
2. [Architecture](architecture.md) - Understanding the structure
3. [Onboarding Screening](onboarding.md) - Screen account holders during sign-up
4. [Manual Override](override.md) - Review and override screening decisions
5. [Testing](testing.md) - Running and writing tests

## API Endpoints

Key endpoints for integration:

- **POST /api/onboarding/screen** - Screen account holder during onboarding
- **GET /api/decisions** - List screening decisions
- **POST /api/overrides** - Create manual override for a decision

See the [OpenAPI documentation](http://localhost:4000/api/docs) for complete API reference.

## Need Help?

- Check the guides in this documentation
- Review the CLAUDE.md for development conventions
- See the OpenAPI docs at http://localhost:4000/api/docs

## Next Steps

Continue to [Getting Started](getting-started.md) to set up your development environment and configure Watchman API access.
