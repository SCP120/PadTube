# Contributing

**The most useful help now is a device report.** If you try PadTube on any iPad, open a [device report](../../issues/new?template=device-report.yml), even if all works.

For code:

1. Read the [README](README.md) build section. You need an Apple Silicon Mac and Command Line Tools.
2. Run `scripts/run_tests.sh`.
3. Keep iOS 6 working: an API newer than iOS 6 must sit behind a runtime check, and `@available` does not link for armv7. The build fails on an unguarded newer API.
4. Keep it fast on 512 MB: measure on a device when you can, and say what you measured.
5. Do not commit keys, tokens, screenshots of your account, test captures or third-party logos. `scripts/check_release.py` checks this.
