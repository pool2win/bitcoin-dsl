dir := justfile_directory()
local_docker_command := "docker run -p 8888:8888 -it --mount type=bind,source="+dir+"/lib,target=/bitcoin-dsl/lib --mount type=bind,source="+dir+"/spec,target=/bitcoin-dsl/spec --mount type=bind,source="+dir+"/notebooks,target=/bitcoin-dsl/notebooks bitcoin-dsl"
remote_docker_command := "docker run -p 8888:8888 -it --mount type=bind,source="+dir+"/lib,target=/bitcoin-dsl/lib --mount type=bind,source="+dir+"/spec,target=/bitcoin-dsl/spec --mount type=bind,source="+dir+"/notebooks,target=/bitcoin-dsl/notebooks ghcr.io/pool2win/bitcoin-dsl:release"

default_image := env_var_or_default("DSL_IMAGE", "remote")

docker_command := if default_image == "remote" { remote_docker_command }  else { local_docker_command }

default:
	@just --list

# Build docker image
build-docker:
	docker build -t bitcoin-dsl .

# Run a script using local docker image
run script:
	{{docker_command}} ruby ./lib/run.rb -s {{script}}

# # Run a script using remote docker image
# run_script script:
# 	{{remote_docker_command}} ruby ./lib/run.rb -s {{script}}

# Run the test suite
test:
	{{local_docker_command}} rake spec

# Get a bash shell on local docker image
bash:
	{{docker_command}} bash

# Start jupyterlab
lab:
	{{docker_command}}

# Pull latest docker image from github container repo
pull:
	docker pull ghcr.io/pool2win/bitcoin-dsl:release
