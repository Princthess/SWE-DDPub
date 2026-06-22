# Git reference

Commands for syncing this project with GitHub. Run from the project root in
PowerShell or Git Bash.

## Clone (new machine)

```sh
git clone https://github.com/Princthess/Oddpub-postprocessing.git
cd Oddpub-postprocessing
```

Then run `restore.R` in RStudio (see [README.md](README.md)).

## Everyday updates

```sh
git add -A
git commit -m "describe what changed"
git push
```

## Checks

```sh
git status        # uncommitted changes
git log --oneline # commit history
git remote -v     # configured remotes
```

## What gets uploaded

Everything except the patterns in `.gitignore`: `renv/library/` (rebuilt by
`restore.R`), all PDFs/`.txt`, and `results.csv`. This is automatic.
