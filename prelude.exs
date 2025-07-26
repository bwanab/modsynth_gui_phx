# this file will always be included in scripts prior to their compilation when being played.

# Helper functions to make scripts more user-friendly

# Simple helper to create STrack with default values
  def make_arpeggios(patterns, chord_syms, opts \\ []) do
    root = Keyword.get(opts, :root, :C)
    octave = Keyword.get(opts, :octave, 3)
    duration = Keyword.get(opts, :duration, 0.5)
    repeats = Keyword.get(opts, :repeats, 1)
    chords = MusicBuild.Examples.ArpeggioProgressions.build_chords(chord_syms, root, octave, duration, 0)
    Enum.map(Enum.zip(chords, patterns), fn {c, p} -> Arpeggio.new(c, p, duration, 0) end)
            |> List.duplicate(repeats)
            |> List.flatten
  end

  def strack(sonorities, bpm \\ 100) do
    %{0 => STrack.new(sonorities, name: "", tpqn: 960, type: :instrument, program_number: 10, bpm: bpm)}
  end
