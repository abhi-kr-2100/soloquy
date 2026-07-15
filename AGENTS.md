# AGENTS.md

This file provides guidance to agents when working with code in this repository.

## Project Overview

* The project is being developed inside a Nix development shell. If a program is missing, ensure the Nix shell is active and retry. See flake.nix for all available packages.
* The project is a monorepo. The frontend is inside the soloquy-web-frontend directory. The backend is inside the soloquybackend directory.

### Frontend

* The frontend uses Next.js.
* Read the relevant guide in soloquy-web-frontend/node_modules/next/dist/docs/ before writing any Next.js code.

### Backend

* The backend uses Spring Boot version 4.
* Note that version 4 of Spring Boot is very different from version 3. Perform web searches to learn more about version 4 before making any Spring Boot changes.
