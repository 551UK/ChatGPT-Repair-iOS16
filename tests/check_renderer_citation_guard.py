from pathlib import Path

root=Path(__file__).resolve().parents[1]
guard=(root/"src/RendererCitationGuard.m").read_text()
make=(root/"Makefile").read_text()

assert 'src/RendererCitationGuard.m' in make
assert 'OAIMarkdown' in guard
assert 'CustomCopyingTextView' in guard
assert '\\uE200cite\\uE202' not in guard
assert '"\uE200cite\uE202"' in guard
assert '"\uE200filecite\uE202"' in guard
assert '@"[source]"' in guard
assert '@"[file]"' in guard
assert '@selector(setAttributedText:)' in guard
assert '@selector(setText:)' in guard
assert 'turn' not in guard

print("PASS: raw renderer citation markers are cleaned only in markdown text views")
