#!/bin/bash

set -euxo pipefail

for build in ~/docker-perl/5*; do 
	VERSION=$(basename $build | perl -pE 's/,/-/g')
	OUT_TAG=simcop2387/perl-tester:$VERSION
	IN_TAG=simcop2387/perl:$VERSION
	( docker build -t $OUT_TAG --build-arg BASE=$IN_TAG .;
	docker push $OUT_TAG ) | ts "$OUT_TAG %H:%M:%S" || echo "Failed to build $OUT_TAG"
done
