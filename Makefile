.PHONY: test coverage
test:
	forge test --no-match-path "test/foundry/tmp/*"

coverage:
	forge coverage --no-match-path "test/foundry/tmp/*"
