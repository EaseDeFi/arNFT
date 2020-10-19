#! /bin/sh

rm -rf ./docs ./build
npx truffle compile
npx leafleth -s build/contracts -t scripts/template.sqrl -o docs/
