prod    :; ./build.sh -c ./config/prod.json
dev     :; ./build.sh -c ./config/dev.json
ci      :; ./build.sh -c ./config/ci.json
clean   :; dapp clean
flat    :; ./flatten.sh
test    :; ./test.sh
