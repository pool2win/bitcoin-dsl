default: build-docker

build-docker:
	docker build -t bitcoin-dsl .

run script:
	docker run bitcoin-dsl ruby ./lib/run.rb -s {{script}}

test:
	docker run bitcoin-dsl rake spec
