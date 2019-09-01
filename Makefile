BLOG_IMAGE := reg.quan.io/dan/quan.io
GITHUB_SHA ?= $(shell git rev-parse HEAD)

build:
	@docker build -t ${BLOG_IMAGE}:latest -t ${BLOG_IMAGE}:${GITHUB_SHA} .

push:
	@docker push ${BLOG_IMAGE}:latest
	@docker push ${BLOG_IMAGE}:${GITHUB_SHA}
