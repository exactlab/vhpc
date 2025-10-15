.PHONY: all default vhpc-base vhpc-headnode vhpc-worker clean

vhpc-base:
	docker build -f Containerfile.slurm-base -t vhpc-base:latest .

vhpc-headnode: vhpc-base
	docker build -f Containerfile.slurm-headnode -t vhpc-headnode:latest --build-arg BASE_IMAGE=vhpc-base:latest .
	docker tag vhpc-headnode:latest ghcr.io/exactlab/vhpc-headnode:latest

vhpc-worker: vhpc-base
	docker build -f Containerfile.slurm-worker -t vhpc-worker:latest --build-arg BASE_IMAGE=vhpc-base:latest .
	docker tag vhpc-worker:latest ghcr.io/exactlab/vhpc-worker:latest

all: vhpc-headnode vhpc-worker

default: all

clean:
	docker rmi -f \
		vhpc-base:latest vhpc-headnode:latest vhpc-worker:latest || true
