# Membrane Multimedia Framework: Icecast Element

This package provides elements that can be used to send streams to the
[Icecast](http://icecast.org) streaming server.

At the moment it supports only MPEG Audio stream.

# Installation

Add the following line to your `deps` in `mix.exs`.  Run `mix deps.get`.

```elixir
{:membrane_element_icecast, git: "git@github.com:membraneframework/membrane-element-icecast.git"}
```

Then add the following line to your `applications` in `mix.exs`.

```elixir
:membrane_element_icecast
```

# Authors

Marcin Lewandowski
