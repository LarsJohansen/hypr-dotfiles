---
name: git-workflow
description: Standards and best practices for git operations across all agents
---

# Git Workflow Skill

## Purpose
Defines standards for git operations that all agents must follow. Ensures consistent commit messages, branching strategy, and safe git practices.

## Core Principles

### 1. Ask Before Committing
**CRITICAL**: Agents must NEVER commit without explicit permission from Lars.

```markdown
# ✅ Good
Agent: "Implementation complete. Should I commit these changes?"
Lars: "Yes, go ahead"
Agent: [Commits]

# ❌ Bad
Agent: [Commits without asking]
```

### 2. Safety First
- Never use force push to main/master
- Never skip hooks (--no-verify)
- Never use destructive commands without permission
- Always create NEW commits (not --amend) unless explicitly requested

### 3. Clear Communication
- Show what will be committed before committing
- Explain what changed and why
- Provide commit message for review

---

## Branching Strategy

### Branch Naming
```
feature/[feature-name]     # New features
fix/[bug-description]      # Bug fixes
refactor/[what-refactored] # Refactoring
docs/[what-documented]     # Documentation only
chore/[task-description]   # Build, CI/CD, dependencies
```

### Examples
```bash
feature/user-authentication
feature/create-feature-form
fix/null-reference-in-repository
fix/validation-error-message
refactor/extract-validation-service
docs/add-architecture-decisions
chore/update-dependencies
```

### Main Branch Protection
- `main` (or `master`) is protected
- Pull Request required to merge
- Feature branches created from `main`
- Keep `main` always deployable

### Branch Lifecycle
```bash
# Create feature branch
git checkout main
git pull origin main
git checkout -b feature/my-feature

# Work on feature (multiple commits OK)
git add [files]
git commit -m "message"

# Keep up to date with main
git fetch origin main
git rebase origin/main  # Or merge if team prefers

# Push to remote
git push origin feature/my-feature -u

# Create Pull Request (via gh CLI or GitHub)
gh pr create --title "Add my feature" --body "Description..."

# After PR approved and merged
git checkout main
git pull origin main
git branch -d feature/my-feature  # Delete local branch
```

---

## Commit Messages

### Format: Conventional Commits
```
<type>(<scope>): <subject>

<body>

<footer>
```

### Types
- **feat**: New feature
- **fix**: Bug fix
- **refactor**: Code refactoring (no functional change)
- **test**: Adding or updating tests
- **docs**: Documentation only
- **style**: Code style changes (formatting, no logic change)
- **perf**: Performance improvement
- **chore**: Build process, dependencies, tooling
- **ci**: CI/CD changes

### Scope (Optional)
The area of the codebase affected:
- **domain**: Domain layer
- **application**: Application layer
- **infrastructure**: Infrastructure layer
- **api**: API/Presentation layer
- **tests**: Test code
- **docs**: Documentation
- Component name (e.g., **auth**, **users**, **features**)

### Subject
- Use imperative mood: "Add feature" not "Added feature"
- No capitalization of first letter (lowercase)
- No period at the end
- Max 50 characters
- Clear and concise

### Body (Optional but Recommended)
- Explain WHAT and WHY, not HOW (code shows HOW)
- Wrap at 72 characters
- Separate from subject with blank line
- Can have multiple paragraphs

### Footer (Required for certain cases)
- **Breaking changes**: `BREAKING CHANGE: description`
- **Issue references**: `Closes #123`, `Fixes #456`
- **Co-authoring**: Required for agent commits

### Examples

#### Simple Feature Addition
```
feat(auth): add user registration endpoint

Implement POST /api/auth/register endpoint following
Clean Architecture pattern. Includes input validation,
password hashing with bcrypt, and JWT token generation.

Closes #42

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

#### Bug Fix
```
fix(repository): handle null values in query result

GetByIdAsync was throwing NullReferenceException when
entity not found. Now returns null gracefully and lets
caller handle the not-found case.

Fixes #67

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

#### Refactoring
```
refactor(validation): extract validation into separate class

Moved validation logic from FeatureService to new
FeatureValidator class to follow Single Responsibility
Principle. No functional changes.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

#### Test Addition
```
test(auth): add edge cases for registration validation

Added tests for:
- Empty email
- Invalid email format
- Password too short
- Duplicate email registration

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

#### Documentation
```
docs(architecture): add ADR for authentication strategy

Document decision to use JWT tokens with refresh token
rotation for security. Covers alternatives considered
and trade-offs.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

#### Breaking Change
```
feat(api): change authentication endpoint structure

BREAKING CHANGE: Authentication endpoints moved from
/api/auth to /api/v1/auth. Clients must update their
API base URL.

Previous: POST /api/auth/login
New: POST /api/v1/auth/login

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

---

## Agent Commit Process

### Before Committing

1. **Check Status**
   ```bash
   git status
   git diff  # See unstaged changes
   git diff --staged  # See staged changes
   ```

2. **Show Lars What Will Be Committed**
   ```markdown
   Agent: "Ready to commit. Here's what changed:

   Modified files:
   - src/Domain/Features/Feature.cs (added validation)
   - src/Application/Features/CreateFeatureCommand.cs (new command)
   - tests/UnitTests/Features/FeatureTests.cs (added tests)

   Changes summary:
   - Added Feature entity with validation
   - Implemented CreateFeatureCommand handler
   - Added comprehensive unit tests

   Proposed commit message:
   feat(domain): add Feature entity with validation

   Implement Feature entity following DDD patterns with
   built-in validation for name and description. Includes
   factory method for safe instantiation.

   Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>

   Should I commit this?"
   ```

3. **Wait for Approval**
   ```markdown
   Lars: "Yes, commit"
   # OR
   Lars: "Change the message to focus on..."
   # OR
   Lars: "Don't commit yet, I want to review first"
   ```

### Committing

#### Good Commit Process
```bash
# Stage specific files (prefer this over git add -A)
git add src/Domain/Features/Feature.cs
git add src/Application/Features/CreateFeatureCommand.cs
git add tests/UnitTests/Features/FeatureTests.cs

# Commit with message via heredoc for good formatting
git commit -m "$(cat <<'EOF'
feat(domain): add Feature entity with validation

Implement Feature entity following DDD patterns with
built-in validation for name and description. Includes
factory method for safe instantiation.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"

# Verify commit
git log -1 --stat

# Inform Lars
Agent: "Committed successfully. SHA: abc1234"
```

#### What to Stage
```bash
# ✅ Good: Stage specific files by name
git add src/Domain/Feature.cs
git add tests/FeatureTests.cs

# ⚠️ Use with caution: Stage all modified tracked files
git add -u

# ❌ Risky: Stage everything including new files
git add -A
git add .

# Why risky?
# - Might include .env files with secrets
# - Might include node_modules or other large folders
# - Might include temporary or generated files
# - Prefer explicit file names for safety
```

### After Committing

```bash
# Show commit details
git show HEAD

# If pushing is needed (and approved)
git push origin [branch-name]
```

---

## Pre-Commit Hook Failures

### When Hooks Fail

Pre-commit hooks (linting, formatting, tests) may cause commit to fail.

#### Critical Rule
**NEVER use `--no-verify` unless explicitly asked by Lars.**

#### Correct Response to Hook Failure
```bash
# Hook fails (e.g., formatting check)
Agent: "Commit failed due to pre-commit hook:
- Linting error in Feature.cs line 42
- Should I fix this and try again?"

Lars: "Yes, fix it"

Agent:
1. Fixes the issue
2. Re-stages files: git add [files]
3. Creates NEW commit (not --amend unless requested)
4. Verifies commit succeeded
```

#### What NOT to Do
```bash
# ❌ WRONG: Skip hooks
git commit --no-verify

# ❌ WRONG: Amend previous commit (might destroy work)
git commit --amend

# When hook fails, the commit did NOT happen!
# Using --amend would modify the PREVIOUS commit, not create a new one.
# This can destroy previous work!
```

---

## Creating Pull Requests

### Using GitHub CLI (Preferred)

```bash
# After committing to feature branch
gh pr create --title "Add feature X" --body "$(cat <<'EOF'
## Summary
- Implemented feature X following Clean Architecture
- Added comprehensive tests
- All acceptance criteria met

## Changes
- Added Feature entity to Domain layer
- Implemented use case in Application layer
- Added API endpoint in Presentation layer

## Testing
- Unit tests: 15 new tests, all passing
- Integration tests: 3 new tests, all passing
- Coverage: 85%

## Related
- User Story: [[US-001-create-feature]]
- Architecture: [[0015-feature-validation]]

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

### PR Description Template
```markdown
## Summary
[Brief description of what this PR does]

## Changes
- [List of main changes]
- [Another change]

## Testing
- [How it was tested]
- [Test coverage]

## Related Documents
- User Story: [[link]]
- Architecture: [[link]]
- UX Spec: [[link]] (if applicable)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
```

### Before Creating PR

1. **Ensure all tests pass**
   ```bash
   dotnet test
   npm test
   ```

2. **Check for conflicts with main**
   ```bash
   git fetch origin main
   git rebase origin/main
   # Resolve any conflicts
   ```

3. **Review your changes**
   ```bash
   git diff main...HEAD
   ```

4. **Ask Lars**
   ```markdown
   Agent: "Feature complete. Should I create a Pull Request?"
   Lars: "Yes" / "No" / "Wait, I want to test first"
   ```

---

## Commit Scenarios

### Scenario 1: Single Feature, Single Commit
```bash
# All changes in one logical commit
git add [files]
git commit -m "feat(auth): implement user registration"
```

### Scenario 2: Feature with Multiple Commits
```bash
# Commit 1: Domain layer
git add src/Domain/
git commit -m "feat(domain): add User entity"

# Commit 2: Application layer
git add src/Application/
git commit -m "feat(application): add registration use case"

# Commit 3: Tests
git add tests/
git commit -m "test(auth): add registration tests"

# Commit 4: API
git add src/WebApi/
git commit -m "feat(api): add registration endpoint"
```

### Scenario 3: Bug Fix
```bash
# Add regression test first
git add tests/
git commit -m "test(feature): add regression test for null handling"

# Fix the bug
git add src/
git commit -m "fix(feature): handle null values in GetById"
```

### Scenario 4: Refactoring
```bash
# Keep tests green throughout
git add src/ tests/
git commit -m "refactor(validation): extract validator class"
```

---

## Reviewing Changes Before Commit

### What to Check

```bash
# See all changes
git diff

# See specific file
git diff src/Domain/Feature.cs

# See what's staged
git diff --staged

# Check for debug code
git diff | grep -i "console\|debug\|todo\|fixme"

# Check for secrets
git diff | grep -i "password\|secret\|key\|token"
```

### Agent Responsibility
Before asking to commit:
- Remove debug code (console.log, print statements)
- Remove TODO comments (or keep if intentional)
- Ensure no secrets are committed
- Verify formatting is correct
- Check that only relevant files are included

---

## Common Issues & Solutions

### Issue: "I accidentally committed to main"
```bash
# Don't panic, don't push!
git reset --soft HEAD~1  # Undo commit, keep changes
git checkout -b feature/my-feature  # Create feature branch
# Now commit again
```

### Issue: "Commit message has a typo"
```bash
# If not yet pushed
git commit --amend -m "new message"

# If already pushed, just move forward with new commits
```

### Issue: "Need to add more changes to last commit"
```bash
# If not yet pushed and Lars approves
git add [more files]
git commit --amend --no-edit

# If already pushed, create new commit
git add [more files]
git commit -m "feat(feature): add additional changes"
```

### Issue: "Want to undo last commit completely"
```bash
# If not yet pushed (with Lars approval)
git reset --hard HEAD~1

# If already pushed (requires force push - get Lars approval)
git reset --hard HEAD~1
git push origin [branch] --force  # DANGEROUS, only with approval
```

---

## Git Safety Checklist

Before any git operation, agents should verify:

### Commits
- [ ] Lars approved the commit
- [ ] Reviewed changes (git diff)
- [ ] No debug code or secrets
- [ ] Proper commit message format
- [ ] Co-authored-by line included
- [ ] Staging specific files, not git add -A

### Pushes
- [ ] Lars approved the push
- [ ] Branch name is correct
- [ ] Not pushing to main/master directly
- [ ] No force push unless explicitly requested

### Pull Requests
- [ ] All tests passing
- [ ] No conflicts with main
- [ ] PR description is complete
- [ ] Lars approved creating PR

### Dangerous Commands (Never without explicit approval)
- [ ] Force push (--force)
- [ ] Reset --hard
- [ ] Clean -f
- [ ] Checkout . (discards changes)
- [ ] Branch -D (force delete)

---

## Integration with Development Workflow

### After TDD Phase
```
TDD Agent: "Tests complete and failing"
Lars: "Good, commit the tests"
TDD Agent:
  → git add tests/
  → git commit -m "test(feature): add tests for feature X"
```

### After Implementation Phase
```
Implementation Agent: "Implementation complete, tests passing"
Lars: "Commit it"
Implementation Agent:
  → git add src/
  → git commit -m "feat(feature): implement feature X"
```

### After Code Review Phase
```
Code Review Agent: "Review complete, found minor issues"
Lars: "Fix them"
Implementation Agent: [Fixes issues]
Lars: "Commit the fixes"
Implementation Agent:
  → git add src/
  → git commit -m "refactor(feature): address code review feedback"
```

### Creating PR
```
Lars: "Create a PR for this feature"
Agent:
  → Ensures tests pass
  → Checks for conflicts
  → Creates PR with comprehensive description
  → Links to related Obsidian documents
```

---

## Best Practices Summary

### DO ✅
- Ask before every commit/push
- Use conventional commit format
- Include Co-Authored-By line
- Stage specific files by name
- Write clear, descriptive commit messages
- Create feature branches
- Keep commits focused and atomic
- Run tests before committing
- Review changes before committing

### DON'T ❌
- Commit without asking
- Skip pre-commit hooks (--no-verify)
- Force push to main/master
- Use git add -A blindly
- Commit secrets or .env files
- Create vague commit messages
- Mix multiple unrelated changes in one commit
- Commit broken code
- Amend commits after pre-commit hook failure

---

## Examples

### Example: Complete Feature Commit Flow

```bash
# 1. Start
Lars: "Implement feature X"
Implementation Agent: [Implements feature]

# 2. Check changes
Implementation Agent executes:
$ git status
$ git diff

# 3. Ask to commit
Implementation Agent: "Feature complete. Changes:
- src/Domain/Feature.cs (new)
- src/Application/CreateFeature.cs (new)
- tests/FeatureTests.cs (new)

Proposed commit:
feat(domain): implement Feature entity

Add Feature entity with validation following DDD
patterns. Includes factory method and business rules
for feature creation.

Should I commit?"

# 4. Lars approves
Lars: "Yes, go ahead"

# 5. Commit
Implementation Agent executes:
$ git add src/Domain/Feature.cs src/Application/CreateFeature.cs tests/FeatureTests.cs
$ git commit -m "$(cat <<'EOF'
feat(domain): implement Feature entity

Add Feature entity with validation following DDD
patterns. Includes factory method and business rules
for feature creation.

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
EOF
)"

# 6. Confirm
Implementation Agent: "✓ Committed successfully (SHA: abc1234)"

# 7. Ask about pushing (if needed)
Implementation Agent: "Should I push to origin/feature-x?"
Lars: "Yes"

Implementation Agent executes:
$ git push origin feature-x

Implementation Agent: "✓ Pushed successfully"
```

---

## Version History
- 2025-01-26: Initial creation with comprehensive git workflow standards
