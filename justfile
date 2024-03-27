dir := justfile_directory()
docker_command := "docker run -it --mount type=bind,source="+dir+"/lib,target=/bitcoin-dsl/lib --mount type=bind,source="+dir+"/spec,target=/bitcoin-dsl/spec bitcoin-dsl"
remote_docker_command := "docker run -it --mount type=bind,source="+dir+"/lib,target=/bitcoin-dsl/lib --mount type=bind,source="+dir+"/spec,target=/bitcoin-dsl/spec ghcr.io/pool2win/bitcoin-dsl:release"

default:
	@just --list

# Build docker image
build-docker:
	docker build -t bitcoin-dsl .

# Run a script using local docker image
run script:
	{{docker_command}} ruby ./lib/run.rb -s {{script}}

# Run a script using remote docker image
run_script script:
	{{remote_docker_command}} ruby ./lib/run.rb -s {{script}}

# Run the test suite
test:
	{{docker_command}} rake spec

# Get a bash shell on local docker image
bash:
	{{docker_command}} bash
