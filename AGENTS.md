# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## Commit Guidelines

* Only commit when explicitly asked to.
* Use `jj status --no-pager` and `jj diff --git --no-pager` to see uncommitted changes.
* Use `jj desc -m {commit_message}` to commit changes.
* Follow the Conventional Commits format:
  - **Header**: `type(scope): description`
    - **Type**: One of `feat`, `fix`, `docs`, `refactor`, `perf`, `style`, `test`, `chore`, `ci`, `revert`, `build`.
    - **Scope** (optional): The name of the feature or module being modified.
    - **Description**: A brief summary of the change.
  - **Body** (optional): A detailed description of the change. Start with the motivation for the change and then list the changes made.
  - **Footer** (optional): Any additional information about the change, like `BREAKING CHANGE` notices or issue references (e.g., `Closes #123`).

Example:

```
feat(user): add user authentication

Motivation:
- To secure user accounts and provide personalized experiences.

Changes:
- Add a new user model.
- Add a new user repository.
- Add a new user service.
- Add a new user controller.

BREAKING CHANGE: Authentication is now required for all API endpoints.
```

## Project Overview

* The project is being developed inside a Nix development shell. If a program is missing, ensure the Nix shell is active and retry. See flake.nix for all available packages.
* The project is a monorepo. The frontend is inside the soloquy-web-frontend directory. The backend is inside the soloquybackend directory.

### Frontend

* The frontend uses Next.js.
* Read the relevant guide in soloquy-web-frontend/node_modules/next/dist/docs/ before writing any Next.js code.

### Backend

* The backend uses Spring Boot version 4.
* Note that version 4 of Spring Boot is very different from version 3. Perform web searches to learn more about version 4 before making any Spring Boot changes.
