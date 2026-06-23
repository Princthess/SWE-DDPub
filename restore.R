# ── Run this on a new machine (or after reinstalling R) ───────────────────────
# Restores all packages to the exact versions recorded in renv.lock.

if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv")

renv::restore()

message("All packages restored. You can now run sweddpub.R.")
