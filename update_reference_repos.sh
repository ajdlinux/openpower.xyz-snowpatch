#!/bin/bash

cd /var/lib/jenkins-slave/git

for repo in *; do
	pushd "$repo"
	git remote update
	popd
done

