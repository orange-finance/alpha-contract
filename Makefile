.PHONEY: test
test/fork:
	forge test --fork-url ${ARB_URL} --fork-block-number ${ARB_BLOCK} --no-match-path 'test/foundry/tmp/*' --no-match-contract 'Camelot'
