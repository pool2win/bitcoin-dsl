dir := justfile_directory()
docker_command := "docker run -it --mount type=bind,source="+dir+"/lib,target=/bitcoin-dsl/lib --mount type=bind,source="+dir+"/spec,target=/bitcoin-dsl/spec bitcoin-dsl"

default: build-docker

build-docker:
	docker build -t bitcoin-dsl .

run script:
	{{docker_command}} ruby ./lib/run.rb -s {{script}}

test:
	{{docker_command}} rake spec

bash:
	{{docker_command}} bash
