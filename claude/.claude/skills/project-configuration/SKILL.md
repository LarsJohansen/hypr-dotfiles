---
name: project-configuration
description: Manage project-specific settings, constraints, and preferences that guide all agents
---

# Project Configuration Skill

## Purpose
Manage project-specific settings, constraints, and preferences that guide all agents.

## Configuration Location
Each project has a configuration file at the projects root path in Obsidian:
`project-config.md`

## Configuration Structure
```yaml
---
type: project-config
project: "Project Name"
created: YYYY-MM-DD
updated: YYYY-MM-DD
---

# Project Configuration: [Project Name]

## Overview
Brief description of the project.

## Technology Stack
- **Backend**: .NET 8, C#
- **Frontend**: React, TypeScript
- **Database**: PostgreSQL
- **Infrastructure**: Docker, Kubernetes

## Architecture Patterns
- Domain-Driven Design (DDD)
- Clean Architecture
- CQRS for write operations
- Event Sourcing for audit trail

## Testing Strategy

### .NET Tests
- **Framework**: xUnit
- **Assertions**: Shouldly
- **Mocking**: NSubstitute
- **Coverage Target**: 80% minimum

### TypeScript Tests
- **Framework**: Jest
- **Assertions**: Jest matchers
- **Mocking**: Jest mocks
- **Coverage Target**: 80% minimum

## Code Standards

### .NET
- Follow Microsoft C# conventions
- Use nullable reference types
- Async/await for I/O operations
- Use records for DTOs

### TypeScript
- Strict mode enabled
- Prefer functional components (React)
- Use TypeScript interfaces over types
- ESLint + Prettier configured

## Directory Structure
```
project-root/
├── src/
│   ├── Domain/
│   ├── Application/
│   ├── Infrastructure/
│   └── WebApi/
├── tests/
│   ├── UnitTests/
│   └── IntegrationTests/
└── docs/
```

## Git Workflow
- Feature branches from `main`
- Conventional commits
- PR required for `main`
- Agents must ask before committing

## Agent Constraints

### Product Agent
- No code access
- Focus on business value
- Must create user stories in Obsidian

### Architecture Agent
- Can create code examples in documentation
- Cannot modify production code
- Must create ADRs for significant decisions

### TDD Test Agent
- Must read requirements from Obsidian
- Must follow test framework configuration
- Must get approval before implementation phase

### Implementation Agent
- Must make tests pass
- Must follow architecture guidelines
- Should request architecture review if uncertain

### Code Review Agent
- Must check against architecture patterns
- Must reference ADRs when relevant
- Must suggest, not mandate, changes

## Documentation Requirements
- All architectural decisions → ADRs
- All user-facing features → User stories
- All technical designs → Architecture docs
- Keep Obsidian vault updated
```

## Reading Configuration

Agents should:
1. Read the project config at the start of each session
2. Reference specific sections relevant to their role
3. Flag inconsistencies or missing information
4. Suggest config updates when appropriate

## Updating Configuration

Configuration updates require:
1. Clear justification for the change
2. User approval
3. Update to `updated` date
4. Notification to relevant agents (if in multi-agent session)
