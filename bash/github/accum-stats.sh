#!/bin/bash

# NOTE:
#   This is a composite script to use from a composite GitHub action.
#

[[ -z "$GH_WORKFLOW_ROOT" ]] && {
  echo "$0: error: \`GH_WORKFLOW_ROOT\` variable must be defined." >&2
  exit 255
}

source "$GH_WORKFLOW_ROOT/_externals/tacklelib/bash/tacklelib/bash_tacklelib" || exit $?

tkl_include "$GH_WORKFLOW_ROOT/bash/github/init-basic-workflow.sh" || tkl_abort_include
tkl_include "$GH_WORKFLOW_ROOT/bash/github/init-stats-workflow.sh" || tkl_abort_include
tkl_include "$GH_WORKFLOW_ROOT/bash/github/init-jq-workflow.sh" || tkl_abort_include


[[ -z "$stats_list_key" ]] && {
  gh_print_error "$0: error: \`stats_list_key\` variable must be defined."
  exit 255
}

[[ -z "$stats_by_year_dir" ]] && stats_by_year_dir="$stats_dir/by_year"
[[ -z "$stats_json" ]] && stats_json="$stats_dir/latest.json"
[[ -z "$stats_accum_json" ]] && stats_accum_json="$stats_dir/latest-accum.json"

current_date_time_utc=$(date --utc +%FT%TZ)

gh_print_notice_and_changelog_text_ln "current date/time: $current_date_time_utc" "$current_date_time_utc:"

current_date_utc=${current_date_time_utc/%T*}

# CAUTION:
#   Sometimes the json data file comes empty for some reason.
#   We must check that special case to avoid invalid accumulation!
#
IFS=$'\n' read -r -d '' count uniques stats_length <<< $(jq ".count,.uniques,.$stats_list_key|length" $stats_json)

# CAUTION:
#   Prevent of invalid values spread if upstream user didn't properly commit completely correct json file or didn't commit at all.
#
jq_fix_null \
  count:0 \
  uniques:0 \
  stats_length:0

gh_print_notice_and_changelog_text_bullet_ln "last 14d: all unq: $count $uniques"

IFS=$'\n' read -r -d '' count_outdated_prev uniques_outdated_prev count_prev uniques_prev <<< "$(jq -c -r ".count_outdated,.uniques_outdated,.count,.uniques" $stats_accum_json)"

# CAUTION:
#   Prevent of invalid values spread if upstream user didn't properly commit completely correct json file or didn't commit at all.
#
jq_fix_null \
  count_outdated_prev:0 \
  uniques_outdated_prev:0 \
  count_prev:0 \
  uniques_prev:0

gh_print_notice_and_changelog_text_bullet_ln "prev accum: outdated-all outdated-unq / all unq: $count_outdated_prev $uniques_outdated_prev / $count_prev $uniques_prev"

(( ! count && ! uniques && ! stats_length )) && {
  gh_print_error_and_changelog_text_bullet_ln "$0: error: json data is invalid or empty." "json data is invalid or empty"

  # try to request json generic response fields to print them as a notice
  IFS=$'\n' read -r -d '' json_message json_url json_documentation_url <<< $(jq ".message,.url,.documentation_url" $stats_json)

  jq_fix_null \
    json_message \
    json_url \
    json_documentation_url

  [[ -n "$json_message" ]] && gh_print_notice_and_changelog_text_bullet_ln "json generic response: message: \`$json_message\`"
  [[ -n "$json_url" ]] && gh_print_notice_and_changelog_text_bullet_ln "json generic response: url: \`$json_url\`"
  [[ -n "$json_documentation_url" ]] && gh_print_notice_and_changelog_text_bullet_ln "json generic response: documentation_url: \`$json_documentation_url\`"

  (( ! CONTINUE_ON_INVALID_INPUT )) && exit 255
}

stats_accum_timestamp=()
stats_accum_count=()
stats_accum_uniques=()

stats_timestamp_prev_seq=""
stats_count_prev_seq=""
stats_unique_prev_seq=""

# CAUTION:
#   Statistic can has values interpolation from, for example, per hour basis to day basis, which means the edge values can fluctuate to lower levels.
#   To prevent save up lower levels of outdated values we must to calculate the min and max values per day fluctuation for all days and save the maximum instead of
#   an interpolated value for all being removed records (after 14'th day).
#
stats_accum_count_max=()
stats_accum_uniques_max=()

for i in $(jq ".$stats_list_key|keys|.[]" $stats_accum_json); do
  # CAUTION:
  #   Prevent of invalid values spread if upstream user didn't properly commit completely correct json file or didn't commit at all.
  #
  jq_is_null i && break

  IFS=$'\n' read -r -d '' timestamp count uniques count_max uniques_max <<< \
    "$(jq -c -r ".$stats_list_key[$i].timestamp,.$stats_list_key[$i].count,.$stats_list_key[$i].uniques,
        .$stats_list_key[$i].count_minmax[1],.$stats_list_key[$i].uniques_minmax[1]" $stats_accum_json)"

  # CAUTION:
  #   Prevent of invalid values spread if upstream user didn't properly commit completely correct json file or didn't commit at all.
  #
  jq_fix_null \
    count:0 \
    uniques:0

  stats_accum_timestamp[${#stats_accum_timestamp[@]}]="$timestamp"
  stats_accum_count[${#stats_accum_count[@]}]=$count
  stats_accum_uniques[${#stats_accum_uniques[@]}]=$uniques

  jq_fix_null \
    count_max:$count \
    uniques_max:$uniques

  stats_accum_count_max[${#stats_accum_count_max[@]}]=$count_max
  stats_accum_uniques_max[${#stats_accum_uniques_max[@]}]=$uniques_max

  stats_timestamp_prev_seq="$stats_timestamp_prev_seq|$timestamp"
  stats_count_prev_seq="$stats_count_prev_seq|$count"
  stats_uniques_prev_seq="$stats_uniques_prev_seq|$uniques"
done

# stats between previos/next script execution (dependent to the pipeline scheduler times)
stats_prev_exec_count_inc=0
stats_prev_exec_uniques_inc=0
stats_prev_exec_count_dec=0
stats_prev_exec_uniques_dec=0

first_stats_timestamp=""

stats_timestamp=()
stats_count=()
stats_uniques=()

stats_timestamp_next_seq=""
stats_count_next_seq=""
stats_unique_next_seq=""

stats_count_min=()
stats_count_max=()
stats_uniques_min=()
stats_uniques_max=()

for i in $(jq ".$stats_list_key|keys|.[]" $stats_json); do
  # CAUTION:
  #   Prevent of invalid values spread if upstream user didn't properly commit completely correct json file or didn't commit at all.
  #
  jq_is_null i && break

  IFS=$'\n' read -r -d '' timestamp count uniques <<< "$(jq -c -r ".$stats_list_key[$i].timestamp,.$stats_list_key[$i].count,.$stats_list_key[$i].uniques" $stats_json)"

  # CAUTION:
  #   Prevent of invalid values spread if upstream user didn't properly commit completely correct json file or didn't commit at all.
  #
  jq_fix_null \
    count:0 \
    uniques:0

  (( ! i )) && first_stats_timestamp="$timestamp"

  stats_timestamp[${#stats_timestamp[@]}]="$timestamp"
  stats_count[${#stats_count[@]}]=$count
  stats_uniques[${#stats_uniques[@]}]=$uniques

  stats_timestamp_next_seq="$stats_timestamp_next_seq|$timestamp"
  stats_count_next_seq="$stats_count_next_seq|$count"
  stats_uniques_next_seq="$stats_uniques_next_seq|$uniques"

  timestamp_date_utc=${timestamp/%T*}
  timestamp_year_utc=${timestamp_date_utc/%-*}

  timestamp_year_dir="$stats_by_year_dir/$timestamp_year_utc"
  year_date_json="$timestamp_year_dir/$timestamp_date_utc.json"

  [[ ! -d "$timestamp_year_dir" ]] && mkdir -p "$timestamp_year_dir"

  count_min=$count
  count_max=$count
  uniques_min=$uniques
  uniques_max=$uniques

  count_inc=0
  count_dec=0
  uniques_inc=0
  uniques_dec=0

  count_saved=0
  uniques_saved=0
  count_prev_day_inc_saved=0
  count_prev_day_dec_saved=0
  uniques_prev_day_inc_saved=0
  uniques_prev_day_dec_saved=0
  count_min_saved=0
  count_max_saved=0
  uniques_min_saved=0
  uniques_max_saved=0

  # calculate min/max
  if [[ -f "$year_date_json" ]]; then
    IFS=$'\n' read -r -d '' count_saved uniques_saved count_prev_day_inc_saved count_prev_day_dec_saved uniques_prev_day_inc_saved uniques_prev_day_dec_saved count_min_saved count_max_saved uniques_min_saved uniques_max_saved <<< \
      "$(jq -c -r ".count,.uniques,.count_prev_day_inc,.count_prev_day_dec,.uniques_prev_day_inc,.uniques_prev_day_dec,.count_minmax[0],.count_minmax[1],.uniques_minmax[0],.uniques_minmax[1]" $year_date_json)"

    # CAUTION:
    #   Prevent of invalid values spread if upstream user didn't properly commit completely correct json file or didn't commit at all.
    #
    jq_fix_null \
      count_saved:0 uniques_saved:0 \
      count_prev_day_inc_saved:0 count_prev_day_dec_saved:0 \
      uniques_prev_day_inc_saved:0 uniques_prev_day_dec_saved:0 \
      count_min_saved:$count_saved count_max_saved:$count_saved \
      uniques_min_saved:$uniques_saved uniques_max_saved:$uniques_saved

    (( count_max_saved > count_max )) && count_max=$count_max_saved
    (( count_min_saved < count_min )) && count_min=$count_min_saved
    (( uniques_max_saved > uniques_max )) && uniques_max=$uniques_max_saved
    (( uniques_min_saved < uniques_min )) && uniques_min=$uniques_min_saved
  fi

  stats_count_min[${#stats_count_min[@]}]=$count_min
  stats_count_max[${#stats_count_max[@]}]=$count_max
  stats_uniques_min[${#stats_uniques_min[@]}]=$uniques_min
  stats_uniques_max[${#stats_uniques_max[@]}]=$uniques_max

  (( count > count_saved )) && (( count_inc=count-count_saved ))
  (( uniques > uniques_saved )) && (( uniques_inc=uniques-uniques_saved ))

  (( count < count_saved )) && (( count_dec=count_saved-count ))
  (( uniques < uniques_saved )) && (( uniques_dec=uniques_saved-uniques ))

  (( stats_prev_exec_count_inc+=count_inc ))
  (( stats_prev_exec_uniques_inc+=uniques_inc ))

  (( stats_prev_exec_count_dec+=count_dec ))
  (( stats_prev_exec_uniques_dec+=uniques_dec ))

  if (( count != count_saved || uniques != uniques_saved || \
        count_min != count_min_saved || count_max != count_max_saved || \
        uniques_min != uniques_min_saved || uniques_max != uniques_max_saved )); then
  echo "\
{
  \"timestamp\" : \"$current_date_time_utc\",
  \"count\" : $count,
  \"count_minmax\" : [ $count_min, $count_max ],
  \"count_prev_day_inc\" : $count_prev_day_inc_saved,
  \"count_prev_day_dec\" : $count_prev_day_dec_saved,
  \"uniques\" : $uniques,
  \"uniques_minmax\" : [ $uniques_min, $uniques_max ],
  \"uniques_prev_day_inc\" : $uniques_prev_day_inc_saved,
  \"uniques_prev_day_dec\" : $uniques_prev_day_dec_saved
}" > "$year_date_json"
  fi
done

# stats between last change in previous/next day (independent to the pipeline scheduler times)
stats_prev_day_count_inc=0
stats_prev_day_uniques_inc=0
stats_prev_day_count_dec=0
stats_prev_day_uniques_dec=0

count_saved=0
uniques_saved=0
count_prev_day_inc_saved=0
count_prev_day_dec_saved=0
uniques_prev_day_inc_saved=0
uniques_prev_day_dec_saved=0
count_min_saved=0
count_max_saved=0
uniques_min_saved=0
uniques_max_saved=0

timestamp_date_utc=$current_date_utc
timestamp_year_utc=${current_date_utc/%-*}
timestamp_year_dir="$stats_by_year_dir/$timestamp_year_utc"
year_date_json="$timestamp_year_dir/$timestamp_date_utc.json"

if [[ -f "$year_date_json" ]]; then
  IFS=$'\n' read -r -d '' count_saved uniques_saved count_prev_day_inc_saved count_prev_day_dec_saved uniques_prev_day_inc_saved uniques_prev_day_dec_saved count_min_saved count_max_saved uniques_min_saved uniques_max_saved <<< \
    "$(jq -c -r ".count,.uniques,.count_prev_day_inc,.count_prev_day_dec,.uniques_prev_day_inc,.uniques_prev_day_dec,.count_minmax[0],.count_minmax[1],.uniques_minmax[0],.uniques_minmax[1]" $year_date_json)"

  # CAUTION:
  #   Prevent of invalid values spread if upstream user didn't properly commit completely correct json file or didn't commit at all.
  #
  jq_fix_null \
    count_saved:0 uniques_saved:0 \
    count_prev_day_inc_saved:0 count_prev_day_dec_saved:0 \
    uniques_prev_day_inc_saved:0 uniques_prev_day_dec_saved:0 \
    count_min_saved:$count_saved count_max_saved:$count_saved \
    uniques_min_saved:$uniques_saved uniques_max_saved:$uniques_saved
fi

(( stats_prev_day_count_inc+=count_prev_day_inc_saved+stats_prev_exec_count_inc ))
(( stats_prev_day_uniques_inc+=uniques_prev_day_inc_saved+stats_prev_exec_uniques_inc ))

(( stats_prev_day_count_dec+=count_prev_day_dec_saved+stats_prev_exec_count_dec ))
(( stats_prev_day_uniques_dec+=uniques_prev_day_dec_saved+stats_prev_exec_uniques_dec ))

# CAUTION:
#   The changes over the current day can unexist, but nonetheless they can exist for all previous days
#   because upstream may update any of previous day at the current day, so we must detect changes irrespective
#   to previously saved values.
#
if (( stats_prev_exec_count_inc || stats_prev_exec_uniques_inc || stats_prev_exec_count_dec || stats_prev_exec_uniques_dec )); then
  [[ ! -d "$timestamp_year_dir" ]] && mkdir -p "$timestamp_year_dir"

  echo "\
{
  \"timestamp\" : \"$current_date_time_utc\",
  \"count\" : $count_saved,
  \"count_minmax\" : [ $count_min_saved, $count_max_saved ],
  \"count_prev_day_inc\" : $stats_prev_day_count_inc,
  \"count_prev_day_dec\" : $stats_prev_day_count_dec,
  \"uniques\" : $uniques_saved,
  \"uniques_minmax\" : [ $uniques_min_saved, $uniques_max_saved ],
  \"uniques_prev_day_inc\" : $stats_prev_day_uniques_inc,
  \"uniques_prev_day_dec\" : $stats_prev_day_uniques_dec
}" > "$year_date_json"
fi

# accumulate statistic
count_outdated_next=$count_outdated_prev
uniques_outdated_next=$uniques_outdated_prev

j=0
for (( i=0; i < ${#stats_accum_timestamp[@]}; i++)); do
  if [[ -z "$first_stats_timestamp" || "${stats_accum_timestamp[i]}" < "$first_stats_timestamp" ]]; then
    if (( j )); then
      (( count_outdated_next += ${stats_accum_count[i]} ))
      (( uniques_outdated_next += ${stats_accum_uniques[i]} ))
    else
      (( count_outdated_next += ${stats_accum_count_max[i]} ))
      (( uniques_outdated_next += ${stats_accum_uniques_max[i]} ))
    fi
    (( j++ ))
  fi
done

count_next=0
uniques_next=0

for (( i=0; i < ${#stats_timestamp[@]}; i++)); do
  (( count_next += ${stats_count[i]} ))
  (( uniques_next += ${stats_uniques[i]} ))
done

(( count_next += count_outdated_next ))
(( uniques_next += uniques_outdated_next ))

gh_print_notice_and_changelog_text_bullet_ln "next accum: outdated-all outdated-unq / all unq: $count_outdated_next $uniques_outdated_next / $count_next $uniques_next"

gh_print_notice "prev json diff: unq all: +$stats_prev_exec_uniques_inc +$stats_prev_exec_count_inc / -$stats_prev_exec_uniques_dec -$stats_prev_exec_count_dec"

gh_print_notice "prev day diff: unq all: +$stats_prev_day_uniques_inc +$stats_prev_day_count_inc / -$stats_prev_day_uniques_dec -$stats_prev_day_count_dec"

gh_write_notice_to_changelog_text_bullet_ln \
  "prev json diff // prev day diff: unq all: +$stats_prev_exec_uniques_inc +$stats_prev_exec_count_inc / -$stats_prev_exec_uniques_dec -$stats_prev_exec_count_dec // +$stats_prev_day_uniques_inc +$stats_prev_day_count_inc / -$stats_prev_day_uniques_dec -$stats_prev_day_count_dec"

if (( count_outdated_prev == count_outdated_next && uniques_outdated_prev == uniques_outdated_next && \
      count_prev == count_next && uniques_prev == uniques_next )) && [[ \
      "$stats_timestamp_next_seq" == "$stats_timestamp_prev_seq" && \
      "$stats_count_next_seq" == "$stats_count_prev_seq" && \
      "$stats_uniques_next_seq" == "$stats_uniques_prev_seq" ]]; then
  gh_print_warning_and_changelog_text_bullet_ln "$0: warning: nothing is changed, no new statistic." "nothing is changed, no new statistic"

  (( ! CONTINUE_ON_EMPTY_CHANGES )) && exit 255
fi

{
  echo -n "\
{
  \"timestamp\" : \"$current_date_time_utc\",
  \"count_outdated\" : $count_outdated_next,
  \"uniques_outdated\" : $uniques_outdated_next,
  \"count\" : $count_next,
  \"uniques\" : $uniques_next,
  \"$stats_list_key\" : ["

  for (( i=0; i < ${#stats_timestamp[@]}; i++)); do
    (( i )) && echo -n ','
    echo ''

    echo -n "\
    {
      \"timestamp\": \"${stats_timestamp[i]}\",
      \"count\": ${stats_count[i]},
      \"count_minmax\": [ ${stats_count_min[i]}, ${stats_count_max[i]} ],
      \"uniques\": ${stats_uniques[i]},
      \"uniques_minmax\": [ ${stats_uniques_min[i]}, ${stats_uniques_max[i]} ]
    }"
  done

  (( i )) && echo -e -n "\n  "

  echo ']
}'
} > $stats_accum_json || exit $?

# CAUTION:
#   The GitHub has an issue with the `latest.json` file residual (no effect) changes related to the statistic interpolation issue,
#   when the first record (or set of records from beginning) related to not current day does change (decrease) or remove but nothing else does change.
#   That triggers a consequences like a repository commit with residual changes after script exit. To avoid that we must detect residual changes in the
#   `latest.json` file and return non zero return code with a warning.
#
has_not_residual_changes=0
has_residual_changes=0

for i in $(jq ".$stats_list_key|keys|.[]" $stats_json); do
  # CAUTION:
  #   Prevent of invalid values spread if upstream user didn't properly commit completely correct json file or didn't commit at all.
  #
  jq_is_null i && break

  IFS=$'\n' read -r -d '' timestamp count uniques <<< "$(jq -c -r ".$stats_list_key[$i].timestamp,.$stats_list_key[$i].count,.$stats_list_key[$i].uniques" $stats_json)"

  # CAUTION:
  #   Prevent of invalid values spread if upstream user didn't properly commit completely correct json file or didn't commit at all.
  #
  jq_fix_null \
    count:0 \
    uniques:0

  timestamp_date_utc=${timestamp/%T*}

  # changes at current day is always not residual
  if [[ "$timestamp_date_utc" == "$current_date_utc" ]]; then
    has_not_residual_changes=1
    break
  fi

  timestamp_year_utc=${timestamp_date_utc/%-*}

  timestamp_year_dir="$stats_by_year_dir/$timestamp_year_utc"
  year_date_json="$timestamp_year_dir/$timestamp_date_utc.json"

  if [[ -f "$year_date_json" ]]; then
    IFS=$'\n' read -r -d '' count_saved uniques_saved count_min_saved count_max_saved uniques_min_saved uniques_max_saved <<< \
      "$(jq -c -r ".count,.uniques,.count_minmax[0],.count_minmax[1],.uniques_minmax[0],.uniques_minmax[1]" $year_date_json)"

    # CAUTION:
    #   Prevent of invalid values spread if upstream user didn't properly commit completely correct json file or didn't commit at all.
    #
    jq_fix_null \
      count_saved:0 \
      uniques_saved:0 \
      count_min_saved:$count_saved \
      count_max_saved:$count_saved \
      uniques_min_saved:$uniques_saved \
      uniques_max_saved:$uniques_saved
  else
    has_not_residual_changes=1
    break
  fi

  if (( count > count_saved || uniques > uniques_saved )); then
    has_not_residual_changes=1
    break
  elif (( count < count_saved || uniques < uniques_saved )); then
    has_residual_changes=1
  fi
done

# treat equality as not residual change
if (( has_residual_changes && ! has_not_residual_changes )); then
  gh_print_warning_and_changelog_text_bullet_ln "$0: warning: json data has only residual changes which has no effect and ignored." "json data has only residual changes which has no effect and ignored"

  (( ! CONTINUE_ON_RESIDUAL_CHANGES )) && exit 255
fi

# update changelog file
gh_prepend_changelog_file

# return output variables

# CAUTION:
#   We must explicitly state the statistic calculation time in the script, because
#   the time taken from a script and the time set to commit changes ARE DIFFERENT
#   and may be shifted to the next day.
#
gh_set_env_var STATS_DATE_UTC                     "$current_date_utc"
gh_set_env_var STATS_DATE_TIME_UTC                "$current_date_time_utc"

gh_set_env_var STATS_PREV_EXEC_COUNT_INC          "$stats_prev_exec_count_inc"
gh_set_env_var STATS_PREV_EXEC_UNIQUES_INC        "$stats_prev_exec_uniques_inc"
gh_set_env_var STATS_PREV_EXEC_COUNT_DEC          "$stats_prev_exec_count_dec"
gh_set_env_var STATS_PREV_EXEC_UNIQUES_DEC        "$stats_prev_exec_uniques_dec"

gh_set_env_var STATS_PREV_DAY_COUNT_INC           "$stats_prev_day_count_inc"
gh_set_env_var STATS_PREV_DAY_UNIQUES_INC         "$stats_prev_day_uniques_inc"
gh_set_env_var STATS_PREV_DAY_COUNT_DEC           "$stats_prev_day_count_dec"
gh_set_env_var STATS_PREV_DAY_UNIQUES_DEC         "$stats_prev_day_uniques_dec"

gh_set_env_var COMMIT_MESSAGE_SUFFIX              " | unq all: +$stats_prev_day_uniques_inc +$stats_prev_day_count_inc / -$stats_prev_day_uniques_dec -$stats_prev_day_count_dec"

tkl_set_return
