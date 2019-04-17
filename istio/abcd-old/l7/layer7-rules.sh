#!/bin/bash

source myalias.sh

k19
k create -f l7-a.yaml
k create -f l7-b.yaml
k create -f l7-c.yaml
k create -f l7-d.yaml

k20
k create -f l7-a.yaml
k create -f l7-b.yaml
k create -f l7-c.yaml
k create -f l7-d.yaml

