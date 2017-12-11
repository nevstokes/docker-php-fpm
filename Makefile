IMAGE_NAME = nevstokes/php-fpm

export

.DEFAULT_GOAL := help
.PHONY: build help

help: ## Displays list and descriptions of available targets
	@awk -F ':|\#\#' '/^[^\t].+:.*\#\#/ {printf "\033[36m%-30s\033[0m %s\n", $$1, $$NF }' $(MAKEFILE_LIST) | sort

build: ## Build the Docker image
	@./hooks/build
