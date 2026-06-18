# ── Regenerate renv.lock from scratch ─────────────────────────────────────────
# You normally DON'T need this — renv.lock already exists. Use restore.R on new
# machines instead. Only run this if you want to rebuild the lockfile from a
# clean slate (e.g. to capture deliberately updated package versions).
#
# Run the steps in order, one at a time.

# 1. Install renv
if (!requireNamespace("renv", quietly = TRUE)) install.packages("renv")

# 2. Install the packages the script uses (do this BEFORE init, so renv can
#    discover and record them). pak handles the GitHub install of oddpub.
install.packages("pak")
pak::pak("quest-bih/oddpub")
install.packages(c("dplyr", "stringr"))

# 3. Initialise renv and snapshot. init() detects the installed packages and
#    writes renv.lock. (If renv is already initialised, use renv::snapshot().)
renv::init()

message("Done. renv.lock written — back it up / commit it.")
