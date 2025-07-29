#!/usr/bin/env bash


slurm-base:
	docker build -f Containerfile.slurm-base -t slurm-base:latest .

slurm-headnode: slurm-base
	docker build -f Containerfile.slurm-headnode -t slurm-headnode:latest .

slurm-worker: slurm-base
	docker build -f Containerfile.slurm-worker -t slurm-worker:latest .

all: slurm-headnode slurm-worker

default: all
