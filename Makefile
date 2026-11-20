.PHONY: help build up down restart logs test lint health-check git-branches

help:
	@echo "Duka Ledger (JENGABIZ) Commands:"
	@echo "  make up            - Launch all services with Docker Compose"
	@echo "  make down          - Stop and clean up containers"
	@echo "  make build         - Build all container images"
	@echo "  make test          - Run test suites across all components"
	@echo "  make git-branches  - Set up main, martindev, and staging branches"
	@echo "  make health-check  - Verify API and database health"

up:
	docker compose up -d

down:
	docker compose down

build:
	docker compose build

test:
	@echo "Testing Python Backend..."
	cd backend && pytest -v || true
	@echo "Testing C# Backend..."
	cd backend-csharp/tests/DukaLedger.Tests && dotnet test || true
	@echo "Testing Java Backend..."
	cd backend-java && ./mvnw test || true
	@echo "Testing Flutter App..."
	cd mobile-flutter && flutter test || true

git-branches:
	git branch -M main || true
	git checkout -b martindev || git checkout martindev
	git checkout -b staging || git checkout staging
	git checkout main

health-check:
	curl -f http://localhost:8000/health || echo "Backend not running yet"
