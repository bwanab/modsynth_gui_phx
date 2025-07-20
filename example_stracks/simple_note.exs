# Create a simple note and STrack
note = Note.new(:C, octave: 3, duration: 100)
%{0 => STrack.new([note], name: "example", tpqn: 960, type: :instrument, program_number: 73, bpm: 100)}
