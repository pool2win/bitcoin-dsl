set dotenv-load

dir := justfile_directory()

image_name := env_var_or_default("DSL_IMAGE", "notebooks")

find_notebooks := "find notebooks/ -name *.ipynb ! -path *ipynb_checkpoints* ! -path *Trash*"

default:
	@just --list

# Build docker image
dockerize:
	docker compose build dev-notebooks

# Run a script using local docker image
run script:
	docker compose run {{image_name}} ruby ./lib/run.rb -s {{script}}

# Run the test suite
test:
	docker compose run {{image_name}} bin/rake spec

# Get a bash shell on local docker image
bash:
	docker compose run {{image_name}} bash

# Start jupyterlab
lab:
	docker compose up {{image_name}}

# Pull latest docker image from github container repo
pull:
	docker compose pull notebooks

clean-notebooks:
	{{find_notebooks}} -exec jupyter nbconvert --clear-output {} \;

adoc-notebooks: clean-notebooks
	{{find_notebooks}} -exec jupyter nbconvert --to asciidoc {} \;
