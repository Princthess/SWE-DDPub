# Git cheat-sheet

Quick commands for getting this project onto GitHub and keeping it updated.
Run them in **PowerShell** or **Git Bash**, from inside the project folder.

```powershell
cd "C:\Users\thereset\Documents\Oddpub-postprocessing"
```

---

## First-time setup (only once, on this machine)

Connects this folder to the GitHub repo and uploads everything.

```powershell
git remote add origin https://github.com/Princthess/Oddpub-postprocessing.git
git fetch origin
git reset --soft origin/main
git commit -m "Add renv lockfile and reproducibility setup"
git push origin main
```

> A browser window opens the first time to sign in to GitHub. Sign in once;
> it's remembered after that.

---

## Everyday updates (every time after that)

Whenever you change the script, the README, or run `renv::snapshot()`:

```powershell
git add -A
git commit -m "describe what you changed"
git push
```

---

## Useful checks

```powershell
git status        # what's changed but not yet committed
git log --oneline # history of your commits
```

---

## Setting up on a brand-new computer

```powershell
git clone https://github.com/Princthess/Oddpub-postprocessing.git
cd Oddpub-postprocessing
```

Then open `restore.R` in RStudio and run it (see README.md).

---

## What gets uploaded

Everything in the folder **except** what's listed in `.gitignore`:
`renv/library/` (the installed packages — huge, rebuilt by `restore.R`),
your PDFs, and `results.csv`. You don't have to manage this — it's automatic.
```
