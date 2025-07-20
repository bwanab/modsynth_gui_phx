repeats = 1
chords = MusicBuild.Examples.ArpeggioProgressions.build_chords([:I, :V, :vi, :iii, :IV, :I, :IV, :V], :C, 3, 1, 0)
patterns = [
  [4,1,2,3],
  [1,2,4,3],
  [2,3,4,2],
  [1,4,3,1],
  [1,2,3,4],
  [1,4,3,1],
  [1,2,3,2],
  [2,3,4,1]
]
arpeggios = (Enum.map(Enum.zip(chords, patterns), fn {c, p} -> Arpeggio.new(c, p, 0.5, 0) end)
            |> List.duplicate(repeats)
            |> List.flatten)
%{0 => STrack.new(arpeggios, name: "arpeggios", tpqn: 960, type: :instrument, program_number: 73, bpm: 100)}
