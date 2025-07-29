.PHONY: all default slurm-base slurm-headnode slurm-worker clean

slurm-base:
	docker build -f Containerfile.slurm-base -t slurm-base:latest .

slurm-headnode: slurm-base
	docker build -f Containerfile.slurm-headnode -t slurm-headnode:latest .

slurm-worker: slurm-base
	docker build -f Containerfile.slurm-worker -t slurm-worker:latest .

all: slurm-headnode slurm-worker

default: all

clean:
	docker rmi -f \
		slurm-base:latest slurm-headnode:latest slurm-worker:latest || true
