#!/bin/sh
export PLENV_ROOT=/usr/local/opt/plenv
export PATH=$PLENV_ROOT/bin:$PATH
eval "$(plenv init -)"
DIR=$(cd $(dirname $0);pwd)
cd $DIR
carton exec -- $@
