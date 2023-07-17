# `maelstrom-exercises`

Contains my (poor) attempts at working through [Jepsen's maelstrom exercises - a workbench for learning distributed systems by writing your own](https://github.com/jepsen-io/maelstrom).
I'm using Haskell and [Control.Concurrent.Async + software transactional memory](https://www.oreilly.com/library/view/parallel-and-concurrent/9781449335939/) to muddle my way through.

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

You'll likely need to grab [the maelstrom binary and jars from Github](https://github.com/jepsen-io/maelstrom/releases/tag/v0.2.3)
