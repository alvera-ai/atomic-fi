# Introduction

Welcome to the Alvera Phoenix Template Server - a production-ready Phoenix application template that combines best practices from Alvera's internal projects.

## Overview

This template provides a solid foundation for building Phoenix applications with:

- **Multi-Tenancy**: Tenant-scoped data with row-level security
- **Authentication**: Email/password auth with 2FA support
- **REST API**: OpenAPI-documented endpoints
- **LiveView UI**: Real-time interfaces with Petal Components
- **Testing**: Comprehensive test suite with high coverage
- **CI/CD**: GitHub Actions workflows for quality and deployment
- **Documentation**: ExDoc with extensive guides

## Project Goals

This template aims to:

1. **Reduce boilerplate**: Start new projects faster with proven patterns
2. **Enforce best practices**: Built-in code quality and security checks
3. **Enable rapid development**: Custom generators for common patterns
4. **Maintain consistency**: Standardized structure across Alvera projects
5. **Support scaling**: Multi-tenancy and background jobs from day one

## What's Included

### Core Features

- Phoenix 1.8.3 with LiveView 1.0+
- PostgreSQL with Ecto 3.12+
- Multi-tenant architecture with row-level security
- User authentication with bcrypt
- Two-factor authentication (TOTP)
- OAuth placeholders (Auth0/Keycloak)

### API & Documentation

- OpenAPI 3.0 specification
- Automatic schema validation
- TypeScript SDK generation
- ExDoc documentation

### UI Components

- Petal Components 3.0
- TailwindCSS styling
- Heroicons
- Phoenix Storybook (dev only)

### Development Tools

- Custom Alvera generators (alvera.gen.*)
- Tidewave MCP for AI-assisted development
- Code quality tools (Credo, Sobelow, Dialyxir)
- Comprehensive testing (ExUnit, Wallaby, Vitest)

### DevOps

- Docker multi-arch builds (amd64/arm64)
- GitHub Actions CI/CD
- Structured logging with logger_json
- Oban background jobs

## What's NOT Included

This template intentionally excludes:

- Multiple datalakes (single DB only)
- AI/ML integrations (can be added as needed)
- FHIR healthcare resources
- Complex org memberships
- Oban Pro (using free version)

These features are available in the full `platform` project but are optional for most applications.

## Architecture

The template follows a layered architecture:

```
┌─────────────────────────────────────┐
│         Web Layer (Phoenix)          │
│  ┌──────────────┬─────────────────┐ │
│  │  LiveView    │   REST API      │ │
│  │  (Browser)   │  (JSON/OpenAPI) │ │
│  └──────────────┴─────────────────┘ │
└─────────────────────────────────────┘
              ↓
┌─────────────────────────────────────┐
│       Context Layer (Business)       │
│  ┌──────────┬──────────┬──────────┐ │
│  │  Users   │ Tenants  │  Roles   │ │
│  └──────────┴──────────┴──────────┘ │
└─────────────────────────────────────┘
              ↓
┌─────────────────────────────────────┐
│      Data Layer (Ecto/Postgres)      │
│         Multi-Tenant (RLS)           │
└─────────────────────────────────────┘
```

## Multi-Tenancy Model

All data is scoped by `owner_id` (tenant):

```
Tenant (root entity)
  └── User (belongs_to :owner, Tenant)
       ├── UserRole
       └── UserToken
```

See [Multi-Tenancy Guide](multi-tenancy.md) for details.

## Getting Started

New to this template? Start here:

1. [Getting Started](getting-started.md) - Setup and configuration
2. [Architecture](architecture.md) - Understanding the structure
3. [Generators](generators.md) - Using alvera.gen.* tasks
4. [Testing](testing.md) - Running and writing tests

## Need Help?

- Check the guides in this documentation
- Review the `.claude/commands/` for code generation patterns
- See CLAUDE.md for development conventions

## Next Steps

Continue to [Getting Started](getting-started.md) to set up your development environment.
