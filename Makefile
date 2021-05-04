all    :; dapp build
clean  :; dapp clean
update:
	dapp update
test: update
	dapp testdeploy :; dapp create actions

export DAPP_TEST_TIMESTAMP=1234567
export DAPP_SOLC_VERSION=0.5.12
