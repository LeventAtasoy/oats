#!/bin/bash
oats_dir=$(dirname $(dirname $0))
[ "$OS" ==  "Windows_NT"  ] && oats_dir=$(cygpath -w $oats_dir)
java -jar $oats_dir/vendor/selenium-server-standalone.jar -port 4445 $*
