#!/bin/sh
set -eu
task_tools_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
exec /opt/homebrew/bin/openocd -f "$task_tools_dir/openocd-stm32c552-attach.cfg"
