#!/bin/bash

source myalias.sh

k19
k create -f l4-a.yaml
k create -f l4-b.yaml
k create -f l4-c.yaml
k create -f l4-d.yaml

k20
k create -f l4-a.yaml
k create -f l4-b.yaml
k create -f l4-c.yaml
k create -f l4-d.yaml

