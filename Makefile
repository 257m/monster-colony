ODIN ?= odin
SRC  := src
BIN  := bin

.PHONY: run build check clean

# Run the game directly (compiles + executes).
run:
	$(ODIN) run $(SRC)

# Build a standalone executable into bin/.
build:
	@mkdir -p $(BIN)
	$(ODIN) build $(SRC) -out:$(BIN)/vibegambling -o:speed

# Type/compile check without running.
check:
	$(ODIN) check $(SRC)

clean:
	rm -rf $(BIN)
