#!/bin/bash


source myalias.sh

k19
k create -f l3-a.yaml
k create -f l3-b.yaml
k create -f l3-c.yaml
k create -f l3-d.yaml

k20
k create -f l3-a.yaml
k create -f l3-b.yaml
k create -f l3-c.yaml
k create -f l3-d.yaml

