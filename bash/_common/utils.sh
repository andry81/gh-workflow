#!/bin/bash

# Script both for execution and inclusion.
[[ -z "$BASH" || (-n "$SOURCE_GHWF_COMMON_UTILS_SH" && SOURCE_GHWF_COMMON_UTILS_SH -ne 0) ]] && return

SOURCE_GHWF_COMMON_UTILS_SH=1 # including guard

source "$GH_WORKFLOW_ROOT/_externals/tacklelib/bash/tacklelib/bash_tacklelib" || exit $?


function gh_trim_leading_line_return_chars()
{
  tkl_ltrim_chars "$1" $'\n\r'
}

function gh_trim_trailing_line_return_chars()
{
  tkl_rtrim_chars "$1" $'\n\r'
}

function gh_trim_leading_white_space_chars()
{
  tkl_ltrim_chars "$1" $' \t'
}

function gh_trim_trailing_white_space_chars()
{
  tkl_rtrim_chars "$1" $' \t'
}

function gh_encode_line_return_chars()
{
  local line="$1"

  RETURN_VALUE="${line//%/%25}"
  RETURN_VALUE="${RETURN_VALUE//$'\r'/%0D}"
  RETURN_VALUE="${RETURN_VALUE//$'\n'/%0A}"
}

function gh_decode_line_return_chars()
{
  local line="$1"

  RETURN_VALUE="${line//%0D/$'\r'}"
  RETURN_VALUE="${RETURN_VALUE//%0A/$'\n'}"
  RETURN_VALUE="${RETURN_VALUE//%25/%}"
}

tkl_set_return