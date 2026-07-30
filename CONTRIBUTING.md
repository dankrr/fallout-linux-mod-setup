# Contributing

Bug reports and tested fixes are welcome.

When reporting an installation problem, include:

- Linux distribution and version
- Native or Flatpak Steam
- Steam library paths, with private usernames removed if desired
- The full terminal output from the installer
- Whether either game directory had previously been modified

Do not upload copyrighted Fallout data files or downloaded mod archives.

Before submitting a change, run:

```bash
bash -n fallout-linux-mod-setup.sh
shellcheck fallout-linux-mod-setup.sh
```

Keep changes compatible with Bash and avoid distribution-specific paths unless they are guarded by detection logic.
