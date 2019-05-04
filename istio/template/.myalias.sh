#!/bin/bash

function k () { kubectl "$@"; }
function k19 () { kubectx cilium19; }
function k20 () { kubectx cilium20; }
function kp () { kubectx primary; }
function kb () { kubectx burst; }
function kx () { kubectx; }

function ga () { git add *; }
function gc () { git commit -m 'CommitGKE'; }
function gp () { git push -u origin master; }
function gitsaveall () { git add * && git commit -m 'moi' && git push -u origin master; }
