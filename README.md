# ModsynthGuiPhx

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

## Configuration

### Environment Variables

The following environment variables can be set to configure the application:

* `MODSYNTH_MIDI_DIRS` - A semicolon-delimited list of directories to show in the MIDI file selector. Default: `../sc_em/midi;deps/midifile/test`

Example:
```bash
export MODSYNTH_MIDI_DIRS="/home/user/midi;/opt/midi;../custom_midi"
```

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix
