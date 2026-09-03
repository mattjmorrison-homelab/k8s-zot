.PHONY: check

check:
	nix shell nixpkgs#kubernetes-helm nixpkgs#bats nixpkgs#yq-go nixpkgs#jq -c bats test
