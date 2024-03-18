default: build-docker

build-docker:
	docker build -t bitcoin-dsl .
