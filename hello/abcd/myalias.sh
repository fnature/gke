k () { kubectl "$@"; }
k19 () { kubectx cilium19; }
k20 () { kubectx cilium20; }
kp () { kubectx primary; }
kb () { kubectx burst; }
kx () { kubectx; }

ga () { git add *; }
gc () { git commit -m 'CommitGKE'; }
gp () { git push -u origin master; }
gitsaveall () { git add * && git commit -m 'moi' && git push -u origin master; }

mytest() { echo 'mytest'; }
