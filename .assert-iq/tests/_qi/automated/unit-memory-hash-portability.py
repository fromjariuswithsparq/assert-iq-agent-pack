#!/usr/bin/env python3
"""compute_memory_hash must yield the same value on every supported platform.

`memory_version` is stamped into every verdict, and the reproducibility
contract in qi-foundation.instructions.md ("restore the snapshot, re-run the
assessment, expect an identical verdict") only holds if the same memory store
hashes identically everywhere. Three host-dependent inputs used to break it:

  * `sorted(Path.rglob("*"))` collates case-sensitively on POSIX and
    case-insensitively on Windows;
  * `.gitattributes` marks `*.md` as `text` without pinning `eol`, so memory
    topics check out CRLF on Windows and LF on macOS, and the digest read
    raw bytes;
  * macOS Finder drops `.DS_Store` into any directory a user opens (Windows
    Explorer does the same with `Thumbs.db`/`desktop.ini`). These are
    gitignored, so the working tree looks clean while the hash silently moves.
"""

import sys
import hashlib
import importlib.util
import tempfile
from pathlib import Path, PureWindowsPath, PurePosixPath

# Windows consoles default to cp1252, which cannot encode the ✅/❌ markers
# below; force UTF-8 so a failing assertion reports the assertion rather than
# a UnicodeEncodeError.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

# This file lives at .assert-iq/tests/_qi/automated/, so reaching .assert-iq/
# needs four parents (automated -> _qi -> tests -> .assert-iq).
ASSERT_IQ = Path(__file__).resolve().parent.parent.parent.parent
RECORDER = ASSERT_IQ / "analysis" / "verdict-recorder.py"

spec = importlib.util.spec_from_file_location("aiq_recorder_hash_test", RECORDER)
recorder = importlib.util.module_from_spec(spec)
spec.loader.exec_module(recorder)

# Names deliberately chosen so POSIX and Windows collation disagree:
# POSIX orders uppercase first, Windows folds case.
_STORE = {
    "MEMORY.md": "- [Auth](topics/Auth.md)\n",
    "Zebra.md": "# Zebra\nlate in POSIX order, first-ish on Windows\n",
    "apple.md": "# apple\n",
    "topics/Auth.md": "# Auth\nrotation policy\n",
    "topics/flake.md": "# Flake\nquarantine history\n",
}


def _build_store(crlf=False):
    root = Path(tempfile.mkdtemp()) / "memory"
    for rel, text in _STORE.items():
        target = root / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        body = text.replace("\n", "\r\n") if crlf else text
        # Write bytes so the newline form is exactly what we intend.
        target.write_bytes(body.encode("utf-8"))
    return root


def test_crlf_and_lf_checkouts_agree():
    """A Windows (CRLF) checkout must hash the same as a macOS (LF) one."""
    lf = recorder.compute_memory_hash(str(_build_store(crlf=False)))
    crlf = recorder.compute_memory_hash(str(_build_store(crlf=True)))
    assert lf == crlf, f"line endings changed the hash:\n  LF   {lf}\n  CRLF {crlf}"
    print("✅ Test 1: CRLF and LF checkouts hash identically")
    return True


def test_posix_and_windows_collation_genuinely_differ():
    """Document the hazard, independently of which host runs this test.

    Both sides are computed with explicit pure-path flavours, so this holds
    on macOS and Windows alike.
    """
    posix_order = sorted(_STORE, key=PurePosixPath)
    windows_order = sorted(_STORE, key=lambda r: str(PureWindowsPath(r)).lower())
    assert posix_order != windows_order, (
        "fixture no longer distinguishes the collations; pick different names")
    print("✅ Test 2: POSIX and Windows path collation differ on this fixture")
    return True


def test_hash_is_independent_of_path_collation():
    """The digest must not depend on how Path objects compare.

    `sorted(Path.rglob("*"))` delegates to the OS flavour's comparison, which
    is case-sensitive on POSIX and case-folded on Windows -- so the old
    implementation fed the digest a different file order on each platform.
    Injecting an alternative collation proves the ordering is now a property
    of the store rather than of the host. A reversed-string collation is used
    rather than a Windows one so this test is meaningful on every host,
    including Windows itself.
    """
    store = _build_store()

    class _AltCollatedPath(type(Path())):
        """Stands in for 'some other platform's path collation'."""

        def __lt__(self, other):
            return str(self)[::-1] < str(other)[::-1]

    # Precondition: the injected collation must actually reorder the walk,
    # otherwise this test would pass vacuously.
    host_walk = [p.name for p in sorted(Path(str(store)).rglob("*"))]
    alt_walk = [p.name for p in sorted(_AltCollatedPath(str(store)).rglob("*"))]
    assert host_walk != alt_walk, "injected collation did not reorder the walk"

    baseline = recorder.compute_memory_hash(str(store))

    original = recorder.Path
    try:
        recorder.Path = _AltCollatedPath
        under_alt_collation = recorder.compute_memory_hash(str(store))
    finally:
        recorder.Path = original

    assert under_alt_collation == baseline, (
        "path collation changed the hash:\n"
        f"  host order {baseline}\n"
        f"  alt  order {under_alt_collation}")
    print("✅ Test 3: hash is independent of Path collation")
    return True


def test_finder_visit_does_not_change_the_hash():
    """macOS-specific: opening the memory folder in Finder must be a no-op.

    Finder writes .DS_Store into any directory it displays, at any depth. The
    file is gitignored, so `git status` stays clean and nothing warns the user
    that memory_version just moved -- which reads downstream as memory drift
    on a store nobody edited.
    """
    store = _build_store()
    before = recorder.compute_memory_hash(str(store))

    ds_store = b"\x00\x00\x00\x01Bud1" + b"\x00" * 40
    (store / ".DS_Store").write_bytes(ds_store)
    (store / "topics" / ".DS_Store").write_bytes(ds_store)

    after = recorder.compute_memory_hash(str(store))
    assert after == before, (
        "a Finder visit changed memory_version:\n"
        f"  before {before}\n  after  {after}")
    print("✅ Test 4: .DS_Store from a Finder visit does not change the hash")
    return True


def test_appledouble_and_windows_metadata_ignored():
    """The same rule covers AppleDouble sidecars and Explorer's droppings.

    macOS writes ._Name sidecars when a store lives on a non-APFS volume
    (USB stick, SMB share); Windows Explorer writes Thumbs.db/desktop.ini.
    """
    store = _build_store()
    before = recorder.compute_memory_hash(str(store))

    (store / "topics" / "._Auth.md").write_bytes(b"\x00\x05\x16\x07AppleDouble")
    (store / "Thumbs.db").write_bytes(b"\x00thumbs")
    (store / "topics" / "desktop.ini").write_text("[.ShellClassInfo]\n")

    after = recorder.compute_memory_hash(str(store))
    assert after == before, (
        "desktop metadata changed memory_version:\n"
        f"  before {before}\n  after  {after}")
    print("✅ Test 5: AppleDouble and Explorer metadata are ignored")
    return True


def test_metadata_filter_is_not_over_broad():
    """Only known desktop metadata is skipped -- not dotfiles in general.

    Asserted on the predicate directly, plus an end-to-end check.
    """
    assert recorder._is_desktop_metadata(".DS_Store") is True
    assert recorder._is_desktop_metadata("topics/.DS_Store") is True
    assert recorder._is_desktop_metadata("topics/._Auth.md") is True
    assert recorder._is_desktop_metadata("Thumbs.db") is True
    assert recorder._is_desktop_metadata("topics/desktop.ini") is True

    for keep in (".gitkeep", "MEMORY.md", "topics/Auth.md",
                 "topics/notes.DS_Store.md", ".hidden-topic.md"):
        assert recorder._is_desktop_metadata(keep) is False, keep

    store = _build_store()
    before = recorder.compute_memory_hash(str(store))
    (store / ".hidden-topic.md").write_text("# Hidden\nreal content\n")
    assert recorder.compute_memory_hash(str(store)) != before, \
        "a real dotfile was skipped as if it were desktop metadata"
    print("✅ Test 6: metadata filter is not over-broad")
    return True


def test_file_boundaries_are_framed():
    """Distinct stores must not collide.

    The digest used to be a bare concatenation of file contents, so nothing
    recorded where one file ended and the next began: moving a character
    across the boundary produced an identical hash.
    """
    def digest(files):
        root = Path(tempfile.mkdtemp()) / "memory"
        root.mkdir(parents=True)
        for name, body in files.items():
            (root / name).write_text(body)
        return recorder.compute_memory_hash(str(root))

    split_one = digest({"a.md": "ab", "b.md": "c"})
    split_two = digest({"a.md": "a", "b.md": "bc"})
    assert split_one != split_two, \
        "two different stores collided: file boundaries are not encoded"
    print("✅ Test 7: file boundaries are framed")
    return True


def test_empty_files_are_visible():
    """A zero-byte file is part of the store and must affect the hash.

    .gitkeep is what holds the shipped memory/logs and memory/topics
    directories in git, and it is empty -- under a bare concatenation it
    contributed nothing at all.
    """
    store = _build_store()
    before = recorder.compute_memory_hash(str(store))
    (store / "logs").mkdir(exist_ok=True)
    (store / "logs" / ".gitkeep").write_text("")
    assert recorder.compute_memory_hash(str(store)) != before, \
        "adding an empty file left the hash unchanged"
    print("✅ Test 8: empty files are visible to the hash")
    return True


def test_rename_changes_the_hash():
    """Renaming a topic changes the store, so it must change the version."""
    store = _build_store()
    before = recorder.compute_memory_hash(str(store))
    (store / "topics" / "Auth.md").rename(store / "topics" / "Authentication.md")
    assert recorder.compute_memory_hash(str(store)) != before, \
        "a pure rename was invisible: the path never reached the digest"
    print("✅ Test 9: renames change the hash")
    return True


def test_moving_content_between_topics_changes_the_hash():
    """A fact migrating between topics is a real memory edit.

    Constructed so the *concatenation* is byte-identical before and after --
    only the file boundary moves -- which is what makes this a framing test
    rather than an ordering one. This is the realistic /dream case: a fact
    consolidated from one topic into another.
    """
    def digest(auth_body, flake_body):
        root = Path(tempfile.mkdtemp()) / "memory"
        (root / "topics").mkdir(parents=True)
        (root / "topics" / "auth.md").write_text(auth_body)
        (root / "topics" / "flake.md").write_text(flake_body)
        return recorder.compute_memory_hash(str(root))

    # Sorted order is auth.md then flake.md, so both stores concatenate to "AB".
    before = digest("A", "B")
    after = digest("AB", "")
    assert before != after, \
        "a fact moving between topics was invisible to the digest"
    print("✅ Test 10: moving content between topics changes the hash")
    return True


def test_filename_unicode_normalization_is_stable():
    """macOS-specific: NFD and NFC filenames are the same name.

    Now that paths feed the digest, an unnormalized path would split macOS
    (which hands back decomposed filenames) from Linux and Windows -- the
    exact class of bug the framing fix is meant to close, reintroduced.
    """
    import unicodedata
    composed = unicodedata.normalize("NFC", "caf\u00e9.md")
    decomposed = unicodedata.normalize("NFD", "caf\u00e9.md")
    assert composed.encode() != decomposed.encode(), \
        "fixture is not exercising two encodings of the same name"

    def digest(name):
        root = Path(tempfile.mkdtemp()) / "memory"
        root.mkdir(parents=True)
        (root / name).write_text("# Cafe\nnotes\n")
        return recorder.compute_memory_hash(str(root))

    nfc_digest, nfd_digest = digest(composed), digest(decomposed)
    # A filesystem that re-normalizes on write (HFS+) makes both sides
    # identical on disk; the assertion still holds, it just proves less.
    assert nfc_digest == nfd_digest, (
        "filename normalization changed the hash:\n"
        f"  NFC {nfc_digest}\n  NFD {nfd_digest}")
    print("✅ Test 11: NFC and NFD filenames hash identically")
    return True


def test_binary_content_is_not_newline_normalized():
    """Normalization applies to text only; binaries hash verbatim."""
    root = Path(tempfile.mkdtemp()) / "memory"
    root.mkdir(parents=True)
    (root / "blob.bin").write_bytes(b"\x00\x01\r\n\x02")
    with_crlf = recorder.compute_memory_hash(str(root))

    (root / "blob.bin").write_bytes(b"\x00\x01\n\x02")
    with_lf = recorder.compute_memory_hash(str(root))

    assert with_crlf != with_lf, "binary bytes were newline-normalized"
    print("✅ Test 12: binary files are hashed verbatim")
    return True


def test_hash_still_tracks_real_content_changes():
    """Portability must not come at the cost of sensitivity."""
    base = recorder.compute_memory_hash(str(_build_store()))

    changed = _build_store()
    (changed / "topics" / "Auth.md").write_bytes(b"# Auth\nDIFFERENT policy\n")
    assert recorder.compute_memory_hash(str(changed)) != base, \
        "edited memory content did not change the hash"

    added = _build_store()
    (added / "topics" / "new.md").write_bytes(b"# New\n")
    assert recorder.compute_memory_hash(str(added)) != base, \
        "added memory file did not change the hash"
    print("✅ Test 13: hash still responds to real content changes")
    return True


def test_algorithm_tag_is_emitted():
    """The tag keeps v1-stamped verdicts distinguishable from v2 ones.

    Without it, re-hashing an unchanged store after this fix would read as
    memory drift rather than an algorithm change.
    """
    digest = recorder.compute_memory_hash(str(_build_store()))
    assert digest.startswith("sha256-v2:"), digest
    missing = recorder.compute_memory_hash(str(Path(tempfile.mkdtemp()) / "absent"))
    assert missing == "sha256-v2:uninitialized", missing
    print("✅ Test 14: algorithm tag distinguishes v1 from v2 values")
    return True


if __name__ == "__main__":
    tests = [test_crlf_and_lf_checkouts_agree,
             test_posix_and_windows_collation_genuinely_differ,
             test_hash_is_independent_of_path_collation,
             test_finder_visit_does_not_change_the_hash,
             test_appledouble_and_windows_metadata_ignored,
             test_metadata_filter_is_not_over_broad,
             test_file_boundaries_are_framed,
             test_empty_files_are_visible,
             test_rename_changes_the_hash,
             test_moving_content_between_topics_changes_the_hash,
             test_filename_unicode_normalization_is_stable,
             test_binary_content_is_not_newline_normalized,
             test_hash_still_tracks_real_content_changes,
             test_algorithm_tag_is_emitted]
    passed = 0
    failed = 0

    print("=== Memory Hash Portability Tests ===")
    for test in tests:
        try:
            if test():
                passed += 1
        except Exception as e:
            print(f"❌ {test.__name__} FAILED: {e}")
            failed += 1

    print(f"\nResults: {passed} PASS, {failed} FAIL")
    sys.exit(0 if failed == 0 else 1)
