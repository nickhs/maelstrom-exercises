# `maelstrom-exercises`

Contains my (poor) attempts at working through [Jepsen's maelstrom exercises](https://github.com/jepsen-io/maelstrom) using Haskell and Control.Concurrent.Async

Should not be used as example code for anything - very messy.

## Building

Uses [nix-flakes](https://nixos.wiki/wiki/Flakes) so enable them if you haven't already to get a Haskell environment

	$ nix develop
	$ cd maelstrom-exercises
	$ stack build

## Testing

To run the local unit tests

	$ cd maelstrom-exercises
	$ stack test

To run the actual maelstrom tests

	$ stack install
	$ ../maelstrom/maelstrom test -w broadcast --bin maelstrom-exercises-exe --rate 100 --time-limit 2 # for example
