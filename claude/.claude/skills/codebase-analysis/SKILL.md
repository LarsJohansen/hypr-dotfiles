---
name: codebase-analysis
description: Analyze existing codebases to understand architecture, patterns, and conventions
---

# Codebase Analysis Skill

## Purpose
Analyze existing codebases (especially client projects) to understand their:
- Architecture patterns and structure
- Technology stack and frameworks
- Testing approach and tools
- Coding conventions and style
- Common patterns and practices

This enables agents to contribute to existing projects following THEIR standards, not impose new patterns.

## When to Use

### Use This Skill When:
- Setting up workspace for existing client project
- Contributing to mature codebase
- Working on brownfield project
- Joining a project with established patterns
- Need to understand "how they do things"

### Don't Use For:
- New greenfield projects (use architecture profiles instead)
- Projects where you're defining the architecture
- Prototypes or MVPs starting from scratch

## Analysis Process

### Phase 1: Repository Structure Analysis

#### What to Examine
```bash
# Get directory structure
find [repo-path] -type d -name "*.Tests" -o -name "tests" -o -name "test"
find [repo-path] -type d -name "src" -o -name "lib" -o -name "app"

# Count files by type
find [repo-path] -name "*.cs" | wc -l
find [repo-path] -name "*.ts" | wc -l
find [repo-path] -name "*.js" | wc -l

# Find key files
find [repo-path] -name "*.sln" -o -name "*.csproj" -o -name "package.json" -o -name "build.gradle"
```

#### Document Findings
```markdown
## Repository Structure

### Source Code Organization
```
repo-root/
├── src/
│   ├── Controllers/      # HTTP endpoints
│   ├── Services/         # Business logic layer
│   ├── Repositories/     # Data access layer
│   ├── Models/           # Data models
│   └── DTOs/            # Data transfer objects
├── tests/
│   ├── UnitTests/
│   └── IntegrationTests/
└── docs/
```

### Technology Detected
- **Primary Language**: C# (.NET 6)
- **Framework**: ASP.NET Core Web API
- **Database**: Entity Framework Core with SQL Server
- **Testing**: xUnit
```

### Phase 2: Architecture Pattern Detection

#### Look For Common Patterns

**Clean Architecture / Onion Architecture:**
```bash
# Check for these folder names
ls [repo] | grep -i "domain\|application\|infrastructure\|presentation"

# Check for dependency flow (inner layers don't reference outer)
# Domain has no dependencies on other layers
# Application only depends on Domain
```

**Layered Architecture:**
```bash
# Check for these patterns
ls [repo] | grep -i "controller\|service\|repository\|model"

# Traditional: Controllers → Services → Repositories → Database
```

**MVC:**
```bash
ls [repo] | grep -i "model\|view\|controller"
```

**Microservices:**
```bash
# Multiple services in separate folders
ls [repo] | grep -i "service"
# Each with own database, API
```

**Feature-Based:**
```bash
# Organized by feature/module rather than technical concern
ls src/ # features/users, features/products, features/orders
```

#### Document Pattern
```markdown
## Architecture Pattern: Traditional Layered Architecture

### Pattern Characteristics
- **Type**: Three-tier layered architecture
- **Layers**:
  1. Presentation (Controllers)
  2. Business Logic (Services)
  3. Data Access (Repositories)
- **Dependency Flow**: Controllers → Services → Repositories → Database
- **NOT using**: DDD, Clean Architecture, CQRS

### Key Observations
- Services contain business logic
- Repositories handle all database access
- Controllers are thin, delegate to services
- Models are anemic (data holders, no behavior)

### Do's
✅ Follow their layered structure
✅ Put business logic in services
✅ Keep controllers thin
✅ Use repositories for data access

### Don'ts
❌ Don't introduce DDD entities with behavior
❌ Don't create domain/application layer split
❌ Don't suggest Clean Architecture refactoring
❌ Don't use CQRS unless they already use it
```

### Phase 3: Code Style Analysis

#### Sample Files to Read
```bash
# Read a few representative files
# Controllers
find [repo]/src -name "*Controller.cs" | head -3

# Services
find [repo]/src -name "*Service.cs" | head -3

# Tests
find [repo]/tests -name "*Tests.cs" | head -3
```

#### What to Look For

**Naming Conventions:**
```csharp
// Analyze their patterns:

// Fields
private readonly IService _service;  // _camelCase prefix?
private readonly IService m_service; // m_ prefix?
private readonly IService service;   // no prefix?

// Methods
public async Task<Result> ProcessAsync()  // Async suffix?
public async Task<Result> Process()       // No suffix?

// Classes
public class ProductService : IProductService  // Concrete : Interface?
public class ProductServiceImpl : IProductService  // Impl suffix?

// Files
ProductService.cs, IProductService.cs  // Interface in separate file?
```

**Code Organization:**
```csharp
// Do they use regions?
#region Constructors
#region Public Methods
#region Private Methods

// Order of members?
// 1. Fields
// 2. Constructors
// 3. Properties
// 4. Methods

// Or different order?
```

**Error Handling:**
```csharp
// What's their approach?

// Option 1: Exceptions
throw new NotFoundException($"Product {id} not found");

// Option 2: Result pattern
return Result.Failure("Product not found");

// Option 3: Nullable returns
return null; // caller checks
```

**Async Patterns:**
```csharp
// How do they handle async?
public async Task<Product> GetProductAsync(int id)

// Naming: Async suffix?
// CancellationToken usage?
// ConfigureAwait(false)?
```

#### Document Style
```markdown
## Coding Conventions

### Naming
- **Private fields**: `_camelCase` (underscore prefix)
- **Async methods**: `Async` suffix (GetProductAsync)
- **Interfaces**: `I` prefix in separate file
- **Concrete classes**: No suffix (ProductService, not ProductServiceImpl)

### Code Organization
- **Regions**: Used extensively (even though old-school)
  - #region Constructors
  - #region Public Methods
  - #region Private Methods
- **Member order**: Fields → Constructor → Properties → Public Methods → Private Methods
- **File organization**: One class per file

### Error Handling
- **Primary approach**: Exceptions for exceptional cases
- **Common exceptions**:
  - NotFoundException
  - ValidationException
  - UnauthorizedException
- **NOT using**: Result pattern, Either monad

### Async/Await
- **Suffix**: All async methods use `Async` suffix
- **CancellationToken**: Used in API methods, not internal services
- **ConfigureAwait**: NOT used (assume ASP.NET Core context)

### Comments
- **XML comments**: On all public APIs
- **Inline comments**: Sparingly, only for complex logic
- **TODO comments**: Tracked as GitHub issues, not left in code

### Line Length
- Max ~120 characters (observed, not enforced)

### Follow Their Style
Even if some choices seem dated (regions, etc.), match their style for consistency.
```

### Phase 4: Testing Analysis

#### Examine Test Structure
```bash
# Find test files
find [repo]/tests -name "*.cs"

# Look at test organization
ls tests/
# UnitTests/
# IntegrationTests/

# Check test naming
grep -r "public void" tests/ | head -20
grep -r "public async Task" tests/ | head -20
```

#### Analyze Testing Approach
```csharp
// What frameworks?
// xUnit vs NUnit vs MSTest
[Fact]  // xUnit
[Test]  // NUnit
[TestMethod]  // MSTest

// What assertion library?
result.Should().Be(expected);  // FluentAssertions
Assert.Equal(expected, result);  // xUnit
result.ShouldBe(expected);  // Shouldly

// What mocking library?
var mock = Substitute.For<IService>();  // NSubstitute
var mock = new Mock<IService>();  // Moq
```

#### Document Testing Standards
```markdown
## Testing Approach

### Test Frameworks
- **Unit Tests**: xUnit
- **Assertions**: xUnit Assert.* (NOT FluentAssertions or Shouldly)
- **Mocking**: Moq (NOT NSubstitute)
- **Integration Tests**: xUnit with TestServer

### Test Organization
```
tests/
├── UnitTests/
│   ├── Services/
│   │   └── ProductServiceTests.cs
│   └── Repositories/
│       └── ProductRepositoryTests.cs
└── IntegrationTests/
    └── Controllers/
        └── ProductControllerTests.cs
```

### Test Naming Convention
```csharp
// Pattern: MethodName_Scenario_ExpectedBehavior
[Fact]
public void GetProduct_WhenProductExists_ReturnsProduct()

[Fact]
public async Task CreateProduct_WhenValidInput_CreatesAndReturnsProduct()

[Fact]
public void GetProduct_WhenProductNotFound_ThrowsNotFoundException()
```

### Test Structure
```csharp
[Fact]
public async Task MethodName_Scenario_Expected()
{
    // Arrange
    var mock = new Mock<IDependency>();
    mock.Setup(x => x.Method()).Returns(value);
    var sut = new ServiceUnderTest(mock.Object);

    // Act
    var result = await sut.MethodAsync(param);

    // Assert
    Assert.NotNull(result);
    Assert.Equal(expected, result.Value);
    mock.Verify(x => x.Method(), Times.Once);
}
```

### Coverage
- **Target**: ~60% (don't enforce higher without approval)
- **Focus**: Critical business logic, not getters/setters
- **Integration**: Happy paths and error cases

### Follow Their Patterns
- Use Moq, not NSubstitute (match their choice)
- Use xUnit Assert, not FluentAssertions
- Follow their test naming exactly
- Match their Arrange/Act/Assert structure
```

### Phase 5: Dependency Analysis

#### Check Dependencies
```bash
# .NET
cat *.csproj | grep PackageReference

# Node
cat package.json

# Python
cat requirements.txt

# Java
cat pom.xml  # or build.gradle
```

#### Common Libraries
```xml
<!-- What libraries do they use? -->
<PackageReference Include="AutoMapper" Version="12.0.0" />
<PackageReference Include="FluentValidation" Version="11.5.0" />
<PackageReference Include="Serilog" Version="3.0.0" />
```

#### Document Dependencies
```markdown
## Key Dependencies

### Core Frameworks
- ASP.NET Core 6.0
- Entity Framework Core 6.0.10
- SQL Server

### Common Libraries
- **Mapping**: AutoMapper 12.0
- **Validation**: FluentValidation 11.5
- **Logging**: Serilog 3.0
- **API Docs**: Swashbuckle (Swagger)

### Testing Libraries
- xUnit 2.4.2
- Moq 4.18.4
- Microsoft.AspNetCore.TestHost

### Important Notes
- They use AutoMapper - use it for mappings, don't write manual mapping
- They use FluentValidation - put validation rules there
- They use Serilog - use ILogger<T> with Serilog under the hood
```

### Phase 6: Git & PR Analysis

#### Check Git History
```bash
# Analyze recent commits
git log --oneline -20

# Check commit message format
git log --format="%s" -20

# Check branch naming
git branch -r | head -20
```

#### Analyze Commit Patterns
```bash
# Conventional commits?
git log --oneline | grep "^feat:\|^fix:\|^refactor:"

# Their custom format?
git log --oneline | head -10

# Average commit size
git log --shortstat -20
```

#### Check PR Process
```bash
# Find PR template
find [repo] -name "PULL_REQUEST_TEMPLATE.md"
cat .github/PULL_REQUEST_TEMPLATE.md

# Check PR examples (if GitHub)
gh pr list --state merged --limit 10
```

#### Document Git Workflow
```markdown
## Git & PR Workflow

### Commit Message Format
**Format**: Conventional Commits (loosely)

Examples from their history:
```
feat(products): add price validation
fix(auth): handle expired token correctly
refactor(services): extract common validation
docs(readme): update setup instructions
```

**Pattern**: `<type>(<scope>): <description>`
- type: feat, fix, refactor, docs, test, chore
- scope: feature/module affected (optional)
- description: lowercase, imperative, no period

### Branch Naming
```
feature/add-product-validation
fix/null-reference-in-auth
refactor/extract-service-base
```

**Pattern**: `<type>/<description-in-kebab-case>`

### PR Process
- **Required**: 2 approvals before merge
- **Template**: Use .github/PULL_REQUEST_TEMPLATE.md
- **Checks**: All CI checks must pass
- **Description**: Link to Jira ticket (PROJ-123)

### PR Template Sections
1. **Description**: What and why
2. **Type of Change**: Bug fix, feature, refactor, etc.
3. **Testing**: How it was tested
4. **Screenshots**: For UI changes
5. **Checklist**:
   - [ ] Tests added/updated
   - [ ] Documentation updated
   - [ ] No breaking changes OR migration guide included
```

### Phase 7: Documentation Discovery

#### Find Existing Docs
```bash
# Common locations
ls docs/
ls Documentation/
find [repo] -name "*.md" | grep -i "architecture\|design\|guide"

# Architecture Decision Records?
find [repo] -name "ADR*" -o -name "*decision*"

# API docs
find [repo] -name "swagger.json" -o -name "openapi.*"
```

#### Read Key Documents
```markdown
## Existing Documentation

### Architecture Docs
- `docs/architecture/system-overview.md` - High-level system design
- `docs/architecture/database-schema.pdf` - DB schema
- NO ADRs found (they don't use formal ADRs)

### Development Guides
- `docs/development/setup.md` - Development environment setup
- `docs/development/coding-standards.md` - **IMPORTANT: READ THIS**
- `docs/development/testing-guide.md` - Testing conventions

### API Documentation
- Swagger UI available at `/swagger` when running
- `docs/api/endpoints.md` - Manual endpoint documentation

### Process Docs
- `docs/process/pr-guidelines.md` - PR process and expectations
- `docs/process/deployment.md` - Deployment process (handled by DevOps)

### Must-Read for Contributors
1. `docs/development/coding-standards.md` - Their official standards
2. `docs/development/testing-guide.md` - How they test
3. `docs/process/pr-guidelines.md` - PR expectations
```

## Output: Current State Document

After analysis, create: `_architecture/current-state.md`

### Template
```markdown
---
type: architecture-current-state
project: "[Project Name]"
analyzed-date: YYYY-MM-DD
repository: /path/to/repo
---

# Current State Analysis: [Project Name]

## Summary
Brief overview of the project and codebase.

## Repository Structure
[From Phase 1]

## Architecture Pattern
[From Phase 2]

## Technology Stack
[Languages, frameworks, databases]

## Coding Conventions
[From Phase 3]

## Testing Approach
[From Phase 4]

## Key Dependencies
[From Phase 5]

## Git & PR Workflow
[From Phase 6]

## Existing Documentation
[From Phase 7]

## Recommendations for Contributing

### DO ✅
- Follow their layered architecture
- Use their naming conventions (_camelCase fields, Async suffix)
- Use regions for code organization (match their style)
- Use Moq for mocking (not NSubstitute)
- Use xUnit Assert for assertions
- Follow their commit message format
- Get 2 approvals on PRs

### DON'T ❌
- Don't introduce DDD patterns
- Don't refactor to Clean Architecture
- Don't suggest removing regions (they like them)
- Don't use different test frameworks
- Don't skip their PR template
- Don't make breaking changes without RFC

## Open Questions
[Anything unclear that needs clarification from client]

## Client Guidelines to Request
[What documentation would be helpful to get from them]
```

## Integration with Client Guidelines

After creating current-state.md, if client provides additional guidelines:

### Create: `_architecture/client-guidelines.md`
```markdown
---
type: client-guidelines
project: "[Project Name]"
source: "[Confluence/Wiki/Email]"
date-received: YYYY-MM-DD
---

# Client Guidelines: [Project Name]

## Source
[Link to their documentation or "Provided via email on [date]"]

## Architecture Guidelines

### Principles
[Their stated principles]

### Patterns to Follow
[Specific patterns they mandate]

### Patterns to Avoid
[Anti-patterns they've identified]

## Code Quality Standards

### Required Practices
[What they require]

### Forbidden Practices
[What they explicitly forbid]

## Security Requirements

### Authentication/Authorization
[Their requirements]

### Data Handling
[PII, encryption, etc.]

## Performance Requirements

### Response Time Targets
[Their SLAs]

### Scalability Requirements
[Expected load]

## Compliance

### Standards
[SOC2, GDPR, HIPAA, etc.]

### Audit Requirements
[Logging, traceability]

## Breaking Changes

### RFC Process
[How to propose breaking changes]

### Approval Required
[Who must approve]

## Questions & Clarifications
[Things to verify with them]
```

## How Agents Use This

### TDD Test Agent
```markdown
Before writing tests, reads:
1. _architecture/current-state.md
   → Use xUnit + Moq
   → Follow their test naming convention
   → Match their Arrange/Act/Assert structure
2. _architecture/client-guidelines.md (if exists)
   → Check for test coverage requirements
   → Check for compliance needs (audit logging in tests)
```

### Implementation Agent
```markdown
Before implementing, reads:
1. _architecture/current-state.md
   → Follow their layered architecture
   → Use their naming conventions
   → Match their error handling approach
   → Use regions like they do
2. _architecture/client-guidelines.md
   → Check for security requirements
   → Check for performance requirements
   → Check for forbidden practices
```

### Code Review Agent
```markdown
Before reviewing, reads:
1. _architecture/current-state.md
   → Check against THEIR standards, not ideal
   → Verify follows their patterns
   → Flag deviations from their conventions
2. _architecture/client-guidelines.md
   → Check compliance requirements
   → Check security requirements
   → Verify no forbidden practices used
```

## Best Practices

### DO ✅
- Spend time upfront analyzing thoroughly
- Read multiple files to understand patterns
- Document both what they DO and DON'T do
- Note their rationale when discoverable
- Identify must-follow vs. optional practices
- Ask clarifying questions about unclear patterns

### DON'T ❌
- Rush the analysis
- Assume patterns without verification
- Impose your preferences
- Judge their choices
- Skip reading their existing docs
- Make changes to their architecture without permission

## Analysis Checklist

Before marking analysis complete:

- [ ] Repository structure documented
- [ ] Architecture pattern identified
- [ ] Technology stack catalogued
- [ ] Coding conventions extracted
- [ ] Testing approach understood
- [ ] Key dependencies listed
- [ ] Git workflow documented
- [ ] Existing docs reviewed
- [ ] Current-state.md created
- [ ] Project-config.md updated with findings
- [ ] Client guidelines incorporated (if provided)
- [ ] Open questions documented
- [ ] All agents can reference findings

## Example: Complete Analysis

See: `/home/lars/.claude/examples/existing-project-analysis/` for a complete example of analyzing an existing codebase.

## Version History
- 2025-01-26: Initial creation for brownfield project support
