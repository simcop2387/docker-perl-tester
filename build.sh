#!/bin/bash

set -euxo pipefail

for build in ~/docker-perl/5*; do 
	VERSION=$(basename $build | perl -pE 's/,/-/g')
	OUT_TAG=simcop2387/perl-tester:$VERSION
	IN_TAG=simcop2387/perl:$VERSION
	LOCAL_TAG=registry.docker.home.simcop2387.info:443/simcop2387/perl:$(echo $build | perl -pE 's/,/-/g')
	LOCAL_OUT_TAG=registry.docker.home.simcop2387.info:443/simcop2387/perl-tester:$(echo $build | perl -pE 's/,/-/g')
	PLATFORMS=linux/amd64,linux/arm64
	if [[ $build == *"quadmath"* ]]; then
		# exclude arm64 from quadmath builds since it doesn't apply
		PLATFORMS=linux/amd64
	fi
	echo building $TAG... $PLATFORMS
	( docker pull $OUT_TAG; docker buildx build --progress=simple --platform=$PLATFORMS -t $OUT_TAG -t $LOCAL_OUT_TAG --build-arg BASE=$LOCAL_TAG .;
	docker push $OUT_TAG ) | ts "$OUT_TAG %H:%M:%S" || echo "Failed to build $OUT_TAG"
done
