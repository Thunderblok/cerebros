Dataset Directory
=================

This directory houses optional local datasets used by Cerebros demos.

Currently expected file(s):

- `ames.csv` – Ames Housing dataset (or a subset) used by `Cerebros.test_ames_housing_example/0`.

Search order for this file (see `Cerebros.find_ames_csv/0` helper):
1. `$CEREBROS_DATA_DIR/ames.csv`
2. `project_root/ames.csv` (legacy – now discouraged)
3. `project_root/data/ames.csv` (this path)
4. `project_root/priv/data/ames.csv`
5. `parent_directory/ames.csv` (legacy/dev convenience)

Housekeeping:
- Keep large raw datasets out of the repo. Commit only small subsets or synthetic data.
- If you add new datasets, document them here with source + license.

If `ames.csv` is missing the NAS housing demo will fall back to a simulated dataset and print a note.
