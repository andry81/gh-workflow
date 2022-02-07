> :information_source: this log lists user most visible changes

> :warning: to find all changes use [changelog.txt](https://github.com/andry81/gh-workflow/blob/master/changelog.txt) file in a directory

## 2022.02.07:
* fixed: bash/*/accum-*.sh: basic protection from invalid values spread after read an invalid json file
* fixed: bash/github/accum-stats.sh: code cleanup

## 2022.02.06:
* fixed: bash: board/accum-stats.sh, inpage/accum-downloads.sh: exit with error if nothing is changed
* fixed: bash/github/accum-stats.sh: missed to check by_year json changes and if changed then change the timestamp

## 2022.01.16:
* new: bash: board/accum-stats.sh, inpage/accum-downloads.sh: `STATS_PREV_EXEC_*` and `STATS_PREV_DAY_*` variables to represent the script previous execution/day difference
* changed: bash: board/accum-stats.sh, inpage/accum-downloads.sh: calculate difference in the `COMMIT_MESSAGE_SUFFIX` variable between current json file and the last change from the previous day instead of from the previous json file (independently to the pipeline scheduler times)

## 2022.01.14:
* new: bash/*/accum-*.sh: `STATS_DATE_UTC` and `STATS_DATE_TIME_UTC` variables to represent the script execution times
* new: bash/github/accum-stats.sh: `STATS_PREV_EXEC_*` and `STATS_PREV_DAY_*` variables to represent the script previous execution/day difference
* changed: bash/github/accum-stats.sh: calculate difference in the `COMMIT_MESSAGE_SUFFIX` variable between current json file and the last change from the previous day instead of from the previous json file (independently to the pipeline scheduler times)

## 2022.01.01:
* fixed: bash: missed `stats_dir` and `stats_json` variables check in respective scripts

## 2022.01.01:
* new: bash: use `GH_WORKFLOW_ROOT` variable to include `gh-workflow` shell scripts as dependencies

## 2022.01.01:
* changed: bash/github/print-*.sh: avoid output duplication, always print warnings/errors into stderr including GitHub pipeline

## 2021.12.31:
* new: bash/github: `print-*.sh` scripts to directly call from GitHub pipeline for multiline messages (line per annotation)

## 2021.12.30:
* new: accum-stats.sh, accum-downloads.sh: create `COMMIT_MESSAGE_SUFFIX` variable and print statistics change into GitHub pipeline

## 2021.12.30:
* changed: accum-stats.sh, accum-downloads.sh: always print script main execution parameters, even if has no error or warning