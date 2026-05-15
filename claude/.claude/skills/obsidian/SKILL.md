---
name: obsidian-integration
description: Standards for reading from and writing to Lars's Obsidian vault
---

# Obsidian Integration Skill

## Purpose
Defines standards for all agents to read from and write to Lars's Obsidian vault, ensuring consistent structure, naming, and cross-referencing.

## Vault Location

Paths differ by machine. Detect using `uname -s`:

| Machine | `uname -s` | Vault Root | Projects Base |
|---------|-----------|------------|---------------|
| Linux   | `Linux`   | `/home/lars/Documents/Productivity` | `/home/lars/Documents/Productivity/02 Projects` |
| macOS   | `Darwin`  | `/Users/larsj/Productivity` | `/Users/larsj/Productivity/02 Projects` |

**Before any file operation**, run `uname -s` to determine the correct base path, then use it for all subsequent paths in the session.

## Project Structure
Projects are organized by category:
```
02 Projects/
├── Personal/          # Personal projects
├── Forte/             # Forte company projects
├── DNK/              # DNK projects
├── SGDN/             # SGDN projects
└── [Client Name]/    # Client-specific projects
```

Each actual project lives in: `02 Projects/[Category]/[Project Name]/`

## Agent Documentation Structure
For each project with agent-assisted development, create these folders:

```
02 Projects/[Category]/[Project Name]/
├── _product/                    # Product Strategy Agent outputs
│   ├── goals/
│   │   └── [project-name]-goals.md
│   ├── personas/
│   │   └── [persona-name].md
│   ├── user-stories/
│   │   └── [story-id]-[title].md
│   └── roadmaps/
│       └── [project-name]-roadmap.md
│
├── _architecture/               # Architecture Agent outputs
│   ├── system-design/
│   │   └── [project-name]-architecture.md
│   ├── decisions/              # ADRs
│   │   ├── 0001-[decision-title].md
│   │   ├── 0002-[decision-title].md
│   │   └── README.md
│   ├── diagrams/
│   │   └── [diagram-name].md
│   └── tech-stack.md
│
├── _ux/                        # UX Planner Agent outputs
│   ├── user-journeys/
│   │   └── [journey-name].md
│   ├── interaction-patterns/
│   │   └── [pattern-name].md
│   └── wireframes/
│       └── [screen-name].md
│
├── _tests/                     # TDD Test Agent outputs
│   ├── test-plans/
│   │   └── [feature-name]-test-plan.md
│   └── test-documentation/
│       └── [feature-name]-test-docs.md
│
├── _reviews/                   # Code Review Agent outputs
│   └── [feature-name]-review-[date].md
│
├── _optimization/              # Token Optimization Agent outputs
│   ├── token-analysis-[date].md
│   └── token-dashboard.md
│
├── project-config.md          # Project configuration (read by all agents)
└── README.md                  # Project overview
```

## File Naming Conventions

### General Rules
- Use lowercase with hyphens: `feature-name.md`
- Include dates for time-sensitive docs: `review-2025-01-26.md`
- Use numeric prefixes for sequential items: `0001-decision.md`
- Keep names concise but descriptive

### Specific Patterns
- **Goals**: `[project-name]-goals.md`
- **Personas**: `[persona-name].md` (e.g., `product-manager.md`)
- **User Stories**: `[story-id]-[short-title].md` (e.g., `US-001-create-feature.md`)
- **ADRs**: `[NNNN]-[decision-title].md` (e.g., `0001-use-clean-architecture.md`)
- **Test Plans**: `[feature-name]-test-plan.md`
- **Reviews**: `[feature-name]-review-[YYYY-MM-DD].md`

## Frontmatter Standards

### Product Documents
```yaml
---
type: [goal|persona|user-story|roadmap]
project: "Project Name"
status: [draft|review|approved]
created: YYYY-MM-DD
updated: YYYY-MM-DD
tags:
  - product
  - [project-tag]
---
```

### Architecture Documents
```yaml
---
type: [adr|system-design|diagram|tech-stack]
project: "Project Name"
status: [proposed|accepted|deprecated|superseded]
created: YYYY-MM-DD
updated: YYYY-MM-DD
number: NNNN              # For ADRs only
supersedes: []            # For ADRs only
superseded-by: null       # For ADRs only
tags:
  - architecture
  - [project-tag]
---
```

### UX Documents
```yaml
---
type: [user-journey|interaction-pattern|wireframe]
project: "Project Name"
status: [draft|review|approved]
created: YYYY-MM-DD
updated: YYYY-MM-DD
related-stories:
  - "[[US-001-story-name]]"
personas:
  - "[[persona-name]]"
tags:
  - ux
  - [project-tag]
---
```

### Test Documents
```yaml
---
type: [test-plan|test-documentation]
project: "Project Name"
feature: "Feature Name"
created: YYYY-MM-DD
updated: YYYY-MM-DD
related-story: "[[user-story]]"
tags:
  - testing
  - [project-tag]
---
```

### Review Documents
```yaml
---
type: code-review
project: "Project Name"
feature: "Feature Name"
reviewer: "Code Review Agent"
date: YYYY-MM-DD
status: [pending|addressed|approved]
tags:
  - review
  - [project-tag]
---
```

### Project Configuration
```yaml
---
type: project-config
project: "Project Name"
category: [Personal|Forte|Client]
created: YYYY-MM-DD
updated: YYYY-MM-DD
status: [active|on-hold|completed|archived]
tags:
  - project-config
  - [project-tag]
---
```

## Wikilink Standards

### Creating Links
- Always use double brackets: `[[document-name]]`
- Use display text when helpful: `[[document-name|Display Text]]`
- Link to sections: `[[document-name#Section Heading]]`

### Common Link Patterns
```markdown
# In User Stories
Related Stories: [[US-002-other-story]], [[US-003-another-story]]
Persona: [[product-manager-persona]]
Goals: [[project-goals#Increase Efficiency]]

# In Architecture Docs
See: [[0001-use-clean-architecture]]
System Design: [[system-architecture#Component Diagram]]

# In UX Docs
User Journey: [[onboarding-journey]]
Related Story: [[US-001-create-feature]]

# In Test Docs
User Story: [[US-001-create-feature]]
Architecture Reference: [[0007-error-handling]]

# In Reviews
Implementation: [[US-001-create-feature]]
Architecture Violation: [[0001-use-clean-architecture#Dependency Rules]]
```

### Cross-Agent References
Agents should create links between their outputs:
```markdown
# Product Agent creates user story
[[US-001-create-feature]]

# UX Agent references it
Related Story: [[US-001-create-feature]]

# TDD Test Agent references both
User Story: [[US-001-create-feature]]
UX Spec: [[feature-form-wireframe]]

# Implementation Agent references all
Requirements: [[US-001-create-feature]]
UX: [[feature-form-wireframe]]
Architecture: [[0015-form-validation]]
Tests: [[feature-form-test-plan]]
```

## Status Workflow

### Document Lifecycle
```
draft → review → approved
  ↓
deprecated (if superseded)
```

### Status Meanings
- **draft**: Initial creation, work in progress, expect changes
- **review**: Ready for Lars to review
- **approved**: Lars has approved, guides other agents
- **deprecated**: No longer recommended (architecture docs)
- **superseded**: Replaced by another document (ADRs only)

### Agent Responsibilities
- **Always create as "draft"** initially
- **Request review** when ready: "This document is ready for review. Should I change status to 'review'?"
- **Never auto-approve**: Lars must explicitly approve
- **Update timestamps**: Change `updated` field when modifying

## Reading Documents

### Before Reading
1. Check if document exists
2. Verify it's the correct type
3. Check status (prefer `approved` over `draft`)
4. Note the last update date

### Reading Strategy
```markdown
# ✅ Good: Read only what you need
Read the specific ADR: [[0007-error-handling]]

# ❌ Bad: Read everything
Read all files in _architecture/decisions/

# ✅ Good: Reference previous reads
As mentioned in [[0007-error-handling]] which we read earlier...

# ❌ Bad: Re-read unnecessarily
[Reads same file 3 times in one conversation]
```

### Caching Strategy
- **Project config**: Read once per session, cache in memory
- **ADRs**: Cache frequently referenced ADRs
- **User stories**: Cache current story being worked on
- **Reference previously read content** instead of re-reading

## Writing Documents

### Before Writing
1. **Check if exists**: Don't overwrite existing docs without asking
2. **Follow naming conventions**: Use standard patterns
3. **Create parent folders**: Use `mkdir -p` if needed
4. **Include frontmatter**: Always use proper YAML frontmatter
5. **Add wikilinks**: Link to related documents

### Writing Best Practices
```markdown
# ✅ Good: Clear structure
---
type: user-story
project: "My Project"
status: draft
created: 2025-01-26
updated: 2025-01-26
---

# User Story: Create Feature

## As a [persona]
I want to [action]
So that [benefit]

## Acceptance Criteria
- [ ] Criterion 1
- [ ] Criterion 2

## Related Documents
- Goals: [[project-goals]]
- Personas: [[product-manager-persona]]

# ❌ Bad: No structure, no frontmatter
Just some text about a feature...
```

### Creating Cross-References
After creating a document, mention related documents:
```markdown
I've created the user story at [[US-001-create-feature]].

This story supports the goal defined in [[project-goals#Goal 2]].
Target persona: [[product-manager-persona]].

Next steps:
- UX Agent can reference this story
- Architecture Agent can design for this requirement
- TDD Agent can create tests from acceptance criteria
```

## Project Configuration File

Every project with agent work should have a `project-config.md`:

### Minimal Template
```markdown
---
type: project-config
project: "Project Name"
category: Personal
created: YYYY-MM-DD
updated: YYYY-MM-DD
status: active
tags:
  - project-config
---

# Project Configuration: [Project Name]

## Overview
Brief description of what this project is.

## Technology Stack
- **Backend**: [Language/Framework]
- **Frontend**: [Language/Framework]
- **Database**: [Database]
- **Infrastructure**: [Docker/K8s/etc]

## Architecture Patterns
- [Pattern 1, e.g., Clean Architecture]
- [Pattern 2, e.g., DDD]
- [Pattern 3, e.g., CQRS]

## Testing Strategy
### Backend Tests
- **Framework**: [e.g., xUnit]
- **Assertions**: [e.g., Shouldly]
- **Mocking**: [e.g., NSubstitute]
- **Coverage Target**: 80%

### Frontend Tests (if applicable)
- **Framework**: [e.g., Jest]
- **Coverage Target**: 80%

## Code Standards
[Language-specific conventions]

## Git Workflow
- Feature branches from `main`
- Conventional commits
- PR required for `main`

## Repository
- **Location**: [Git repo URL or path]
- **Structure**: [Brief description]

## Notes
[Any special considerations for this project]
```

## Common Tasks

### Starting a New Project
1. Create project folder: `02 Projects/[Category]/[Project Name]/`
2. Create `project-config.md` using template above
3. Fill in basic information
4. Agents will create other folders as needed

### Finding a Project
```bash
# Detect machine first
PROJECTS_BASE=$([ "$(uname -s)" = "Darwin" ] && echo "/Users/larsj/Productivity/02 Projects" || echo "/home/lars/Documents/Productivity/02 Projects")

# If project name known
cd "$PROJECTS_BASE/[Category]/[Project Name]"

# If searching for project
find "$PROJECTS_BASE" -name "*project-name*" -type d
```

### Creating Folder Structure
```bash
# From project root
mkdir -p _product/{goals,personas,user-stories,roadmaps}
mkdir -p _architecture/{system-design,decisions,diagrams}
mkdir -p _ux/{user-journeys,interaction-patterns,wireframes}
mkdir -p _tests/{test-plans,test-documentation}
mkdir -p _reviews
mkdir -p _optimization
```

### Checking What Exists
```bash
# List all agent documents in project
find . -type d -name "_*"

# Find all user stories
find _product/user-stories -name "*.md"

# Find all ADRs
find _architecture/decisions -name "*.md" | sort
```

## Error Handling

### File Not Found
```markdown
# ✅ Good response
The user story [[US-001-create-feature]] doesn't exist yet.
Should I create it based on our discussion?

# ❌ Bad response
[Fails silently or creates without asking]
```

### Directory Not Found
```markdown
# ✅ Good: Create and inform
The _product/user-stories directory doesn't exist.
I'll create it and add the user story there.

Created: 02 Projects/Personal/MyProject/_product/user-stories/US-001-create-feature.md
```

### Ambiguous Path
```markdown
# ✅ Good: Ask for clarification
I found multiple projects named "API":
1. 02 Projects/Personal/API
2. 02 Projects/Forte/API
3. 02 Projects/SGDN/Customer-API

Which one should I work with?
```

## Integration with Git Repository

Some documents should exist in BOTH Obsidian AND the git repository:

### Dual-Location Documents
- **ADRs**:
  - Obsidian: `02 Projects/[Category]/[Project]/Forte/_architecture/decisions/`
  - Git repo: `docs/architecture/decisions/`

- **Architecture diagrams**:
  - Obsidian: `02 Projects/[Category]/[Project]/_architecture/diagrams/`
  - Git repo: `docs/architecture/diagrams/`

### Agent Responsibilities
When creating ADRs or architecture diagrams:
1. **Always** create in Obsidian first
2. **Ask Lars** if it should also go in git repo
3. **If yes**: Copy to repo (don't move, keep both)
4. Keep Obsidian version as "source of truth"

## Best Practices Summary

### DO ✅
- Always include proper frontmatter
- Use wikilinks for cross-references
- Follow naming conventions
- Create documents in `draft` status
- Ask before overwriting existing files
- Cache frequently read documents
- Reference previous reads instead of re-reading
- Create parent directories as needed
- Link related documents together

### DON'T ❌
- Create documents without frontmatter
- Use absolute file paths in wikilinks
- Auto-approve documents (Lars decides)
- Read entire directories when one file would suffice
- Re-read documents unnecessarily
- Overwrite files without confirming
- Skip creating proper folder structure
- Create orphaned documents (no links to/from)

## Troubleshooting

### "Cannot find document"
1. Check if path is correct (use `find` command)
2. Verify category and project name spelling
3. Check if project-config.md exists
4. Ensure using correct wikilink format

### "Too many results when searching"
1. Be more specific with search terms
2. Use full path or category filter
3. Check tags in frontmatter
4. Ask Lars which one to use

### "Don't know where to put document"
1. Check document type (product/architecture/ux/etc)
2. Refer to folder structure above
3. Follow similar existing documents
4. Ask Lars if still uncertain

## Examples

### Example 1: Product Agent Creating User Story
```markdown
I'll create a user story for the "Create Feature" requirement.

Path: 02 Projects/Personal/MyProject/_product/user-stories/US-001-create-feature.md

Content includes:
- Frontmatter with type: user-story, status: draft
- User story format (As a... I want... So that...)
- Acceptance criteria
- Links to [[project-goals]] and [[product-manager-persona]]

Created! Ready for your review.
```

### Example 2: Architecture Agent Creating ADR
```markdown
I'll document the decision to use Clean Architecture in an ADR.

Obsidian path: 02 Projects/Forte/MyProject/_architecture/decisions/0001-use-clean-architecture.md

The ADR includes:
- Context: Why we need to decide on architecture pattern
- Decision: Use Clean Architecture with DDD
- Consequences: Benefits and trade-offs
- Alternatives considered

Status: proposed (pending your approval)

Should this also be copied to the git repository at docs/architecture/decisions/?
```

### Example 3: Reading Project Context
```markdown
Let me read the project configuration...

Found: 02 Projects/Personal/MyProject/project-config.md

Key details:
- Technology: .NET 8 backend, React frontend
- Architecture: Clean Architecture + DDD
- Testing: xUnit + Shouldly, 80% coverage target

I'll keep this context for the rest of our session.
```

## Version History
- 2025-01-26: Recreated with comprehensive standards for agent integration
